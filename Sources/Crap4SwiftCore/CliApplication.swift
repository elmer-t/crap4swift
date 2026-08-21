import Foundation

/// Wires the pieces together and owns the exit-code contract.
public struct CliApplication {
    public typealias Writer = (String) -> Void

    private let projectRoot: String
    private let executor: CommandExecutor
    private let fileManager: FileManager
    private let threshold: Double
    private let standardOutput: Writer
    private let standardError: Writer

    public init(
        projectRoot: String = FileManager.default.currentDirectoryPath,
        executor: CommandExecutor = ProcessCommandExecutor(),
        fileManager: FileManager = .default,
        threshold: Double = Crap4Swift.threshold,
        standardOutput: @escaping Writer = { print($0) },
        standardError: @escaping Writer = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    ) {
        self.projectRoot = projectRoot
        self.executor = executor
        self.fileManager = fileManager
        self.threshold = threshold
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public func run(arguments: [String]) -> Int32 {
        let parsed: CliArguments
        do {
            parsed = try CliArgumentsParser.parse(arguments)
        } catch {
            standardError("crap4swift: \(Self.message(for: error))")
            standardOutput(CliArgumentsParser.usage)
            return ExitCode.usageError
        }

        if parsed.mode == .help {
            standardOutput(CliArgumentsParser.usage)
            return ExitCode.success
        }

        do {
            return try analyze(parsed)
        } catch {
            standardError("crap4swift: \(Self.message(for: error))")
            return ExitCode.usageError
        }
    }

    private func analyze(_ arguments: CliArguments) throws -> Int32 {
        let files = try selectFiles(mode: arguments.mode)
        guard !files.isEmpty else {
            standardOutput("No Swift files to analyze.")
            return ExitCode.success
        }

        let metrics = CrapAnalyzer.sorted(try score(files: files, coveragePath: arguments.coveragePath))
        standardOutput(ReportFormatter(threshold: threshold).format(metrics, relativeTo: projectRoot))
        return exitCode(for: metrics)
    }

    /// Coverage either arrives ready-made or is generated here. Everything
    /// downstream of this choice is identical, which is the whole point: the
    /// score does not care who ran the tests.
    private func score(files: [String], coveragePath: String?) throws -> [MethodMetrics] {
        let analyzer = CrapAnalyzer()
        guard let coveragePath else {
            return try scorePerPackage(files: files, analyzer: analyzer)
        }
        return try analyzer.analyze(files: files, coverage: supplied(at: coveragePath, for: files))
    }

    /// Coverage is generated once per owning package, then reused for every
    /// selected file in it.
    private func scorePerPackage(files: [String], analyzer: CrapAnalyzer) throws -> [MethodMetrics] {
        let runner = CoverageRunner(executor: executor, fileManager: fileManager, warn: standardError)
        var metrics: [MethodMetrics] = []
        for group in PackageRootFinder(fileManager: fileManager).group(files: files, projectRoot: projectRoot) {
            let coverage = try runner.generateCoverage(packageRoot: group.packageRoot)
            metrics += try analyzer.analyze(files: group.files, coverage: coverage)
        }
        return metrics
    }

    private func supplied(at path: String, for files: [String]) throws -> CoverageData {
        let export = SourceFileFinder.absolutePath(path, relativeTo: projectRoot)
        let coverage = SuppliedCoverage(fileManager: fileManager)
        warnAboutStaleness(coverage.sourcesNewerThan(export, among: files), export: export)
        return try coverage.read(path: export)
    }

    /// Source newer than the export means the report describes code that has
    /// since been edited. That is still worth printing — it is not worth
    /// printing silently.
    private func warnAboutStaleness(_ stale: [String], export: String) {
        guard !stale.isEmpty else { return }
        let name = SourceFileFinder.displayPath(export, relativeTo: projectRoot)
        standardError("warning: \(stale.count) source file(s) changed after \(name) was written; the scores describe the code as it was measured")
    }

    private func exitCode(for metrics: [MethodMetrics]) -> Int32 {
        let worst = CrapAnalyzer.maximumCrap(metrics)
        guard worst > threshold else { return ExitCode.success }
        standardError(String(format: "CRAP threshold exceeded: %.2f > %.2f", worst, threshold))
        return ExitCode.thresholdExceeded
    }

    private func selectFiles(mode: CliMode) throws -> [String] {
        let finder = SourceFileFinder(fileManager: fileManager)
        switch mode {
        case .all:
            return finder.allSourceFiles(projectRoot: projectRoot)
        case .changed:
            return try ChangedFileDetector(executor: executor, fileManager: fileManager)
                .changedSourceFiles(projectRoot: projectRoot)
        case .paths(let paths):
            return finder.expand(paths: paths, projectRoot: projectRoot)
        case .help:
            return []
        }
    }

    static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }
}
