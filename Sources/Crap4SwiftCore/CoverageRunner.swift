import Foundation

/// Produces fresh coverage for one SwiftPM package.
///
/// Same shape as the Maven/JaCoCo pipeline in `crap4java`: delete stale
/// artifacts, run the test command with coverage instrumentation, then read the
/// generated report.
public struct CoverageRunner {
    public static let buildDirectoryName = ".build"
    public static let coverageDirectoryName = "codecov"

    private let executor: CommandExecutor
    private let fileManager: FileManager
    private let parser: LlvmCovCoverageParser
    private let warn: (String) -> Void

    public init(
        executor: CommandExecutor,
        fileManager: FileManager = .default,
        parser: LlvmCovCoverageParser = LlvmCovCoverageParser(),
        warn: @escaping (String) -> Void = { _ in }
    ) {
        self.executor = executor
        self.fileManager = fileManager
        self.parser = parser
        self.warn = warn
    }

    /// Runs the package's tests with coverage and returns the parsed export.
    ///
    /// A missing export is a warning, not a failure: those methods report `N/A`.
    /// A failing test command *is* a failure — coverage measured against a red
    /// suite is not a number worth acting on.
    public func generateCoverage(packageRoot: String) throws -> CoverageData {
        removeStaleArtifacts(packageRoot: packageRoot)

        let test = try executor.execute(
            "swift",
            arguments: ["test", "--enable-code-coverage"],
            workingDirectory: packageRoot
        )
        guard test.succeeded else {
            throw Crap4SwiftError.coverageCommandFailed(
                command: "swift test --enable-code-coverage",
                exitCode: test.exitCode,
                output: test.standardError.isEmpty ? test.standardOutput : test.standardError
            )
        }

        guard let exportPath = locateCoverageExport(packageRoot: packageRoot) else {
            warn("warning: no llvm-cov export found under \(packageRoot)/\(Self.buildDirectoryName); coverage reported as N/A")
            return .unavailable
        }

        do {
            return try parser.parse(file: exportPath)
        } catch {
            warn("warning: cannot read coverage export \(exportPath): \(error); coverage reported as N/A")
            return .unavailable
        }
    }

    // MARK: - Artifacts

    /// Deletes every `codecov` directory under `.build`, so a run can never
    /// report scores from a previous build.
    func removeStaleArtifacts(packageRoot: String) {
        let buildDirectory = URL(fileURLWithPath: packageRoot)
            .appendingPathComponent(Self.buildDirectoryName)
        for directory in coverageDirectories(under: buildDirectory) {
            try? fileManager.removeItem(at: directory)
        }
    }

    /// Asks SwiftPM where it wrote the export, falling back to a search of
    /// `.build` when the query is unavailable or points at a missing file.
    func locateCoverageExport(packageRoot: String) -> String? {
        if let result = try? executor.execute(
            "swift",
            arguments: ["test", "--show-codecov-path"],
            workingDirectory: packageRoot
        ), result.succeeded {
            let reported = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reported.isEmpty, fileManager.fileExists(atPath: reported) {
                return reported
            }
        }

        let buildDirectory = URL(fileURLWithPath: packageRoot)
            .appendingPathComponent(Self.buildDirectoryName)
        let candidates = coverageDirectories(under: buildDirectory)
            .flatMap { directory -> [String] in
                let contents = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
                return contents
                    .filter { $0.hasSuffix(".json") }
                    .map { directory.appendingPathComponent($0).path }
            }
        return candidates.sorted().first
    }

    /// Directories named `codecov` within a few levels of `.build`, e.g.
    /// `.build/arm64-apple-macosx/debug/codecov`. Symlinks are not followed, so
    /// the `.build/debug` alias does not produce duplicates.
    private func coverageDirectories(under buildDirectory: URL, maxDepth: Int = 4) -> [URL] {
        var found: [URL] = []
        var frontier = [(url: buildDirectory, depth: 0)]

        while let current = frontier.popLast() {
            guard current.depth <= maxDepth else { continue }
            let contents = (try? fileManager.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )) ?? []
            for entry in contents {
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if entry.lastPathComponent == Self.coverageDirectoryName {
                    found.append(entry)
                } else {
                    frontier.append((url: entry, depth: current.depth + 1))
                }
            }
        }
        return found
    }
}
