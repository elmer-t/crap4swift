import Foundation

/// Selects changed Swift sources using `git status --porcelain`.
///
/// Modified, added, renamed and untracked files are kept; deletions are not,
/// since there is nothing left to parse.
public struct ChangedFileDetector {
    private let executor: CommandExecutor
    private let fileManager: FileManager

    public init(executor: CommandExecutor, fileManager: FileManager = .default) {
        self.executor = executor
        self.fileManager = fileManager
    }

    public func changedSourceFiles(projectRoot: String) throws -> [String] {
        let result = try executor.execute(
            "git",
            arguments: ["status", "--porcelain"],
            workingDirectory: projectRoot
        )
        guard result.succeeded else {
            throw Crap4SwiftError.commandLaunchFailed(
                command: "git status --porcelain",
                reason: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return filter(porcelain: result.standardOutput, projectRoot: projectRoot)
    }

    func filter(porcelain: String, projectRoot: String) -> [String] {
        let sourcesPrefix = URL(fileURLWithPath: SourceFileFinder.normalized(projectRoot))
            .appendingPathComponent(SourceFileFinder.sourcesDirectoryName).path + "/"

        var found: [String] = []
        for line in porcelain.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let relativePath = Self.path(fromPorcelainLine: String(line)) else { continue }
            let absolute = SourceFileFinder.absolutePath(relativePath, relativeTo: projectRoot)
            guard absolute.hasSuffix(".swift"),
                  absolute.hasPrefix(sourcesPrefix),
                  fileManager.fileExists(atPath: absolute)
            else { continue }
            found.append(absolute)
        }
        return SourceFileFinder.deduplicatedAndSorted(found)
    }

    /// Parses one `git status --porcelain` line into a repository-relative path.
    /// Returns `nil` for deletions and unparsable lines.
    static func path(fromPorcelainLine line: String) -> String? {
        guard line.count > 3 else { return nil }
        let status = String(line.prefix(2))
        guard !status.contains("D") else { return nil }

        var payload = String(line.dropFirst(3))
        // Renames and copies are reported as `old -> new`; the new path is the
        // one that still exists on disk.
        if let arrow = payload.range(of: " -> ") {
            payload = String(payload[arrow.upperBound...])
        }
        return unquote(payload.trimmingCharacters(in: .whitespaces))
    }

    /// Git quotes paths containing unusual characters; strip the quoting.
    static func unquote(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let quote = "\""
        guard path.hasPrefix(quote), path.hasSuffix(quote), path.count >= 2 else { return path }
        let inner = String(path.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
