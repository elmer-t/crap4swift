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
            return try analyze(mode: parsed.mode)
        } catch {
            standardError("crap4swift: \(Self.message(for: error))")
            return ExitCode.usageError
        }
    }

    private func analyze(mode: CliMode) throws -> Int32 {
        let files = try selectFiles(mode: mode)
        guard !files.isEmpty else {
            standardOutput("No Swift files to analyze.")
            return ExitCode.success
        }

        let runner = CoverageRunner(executor: executor, fileManager: fileManager, warn: standardError)
        let analyzer = CrapAnalyzer()
        var metrics: [MethodMetrics] = []

        // Coverage is generated once per owning package, then reused for every
        // selected file in it.
        for group in PackageRootFinder(fileManager: fileManager).group(files: files, projectRoot: projectRoot) {
            let coverage = try runner.generateCoverage(packageRoot: group.packageRoot)
            metrics += try analyzer.analyze(files: group.files, coverage: coverage)
        }
        metrics = CrapAnalyzer.sorted(metrics)

        standardOutput(ReportFormatter(threshold: threshold).format(metrics, relativeTo: projectRoot))

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
