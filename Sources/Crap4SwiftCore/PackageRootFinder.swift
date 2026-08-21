import Foundation

/// Finds the SwiftPM package that owns a file: the nearest ancestor directory
/// containing `Package.swift`, without walking above the project root.
///
/// This is the analog of the Maven module lookup via `pom.xml` in `crap4java`.
public struct PackageRootFinder {
    public static let manifestName = "Package.swift"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func packageRoot(for filePath: String, projectRoot: String) -> String {
        let root = SourceFileFinder.normalized(projectRoot)
        var directory = URL(fileURLWithPath: SourceFileFinder.normalized(filePath))
            .deletingLastPathComponent()

        while true {
            let path = directory.path
            let manifest = directory.appendingPathComponent(Self.manifestName).path
            if fileManager.fileExists(atPath: manifest) {
                return path
            }
            if path == root || !path.hasPrefix(root) {
                return root
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == path { return root }
            directory = parent
        }
    }

    /// Groups files by owning package root. Keys and values are sorted so runs
    /// are reproducible.
    public func group(files: [String], projectRoot: String) -> [(packageRoot: String, files: [String])] {
        var groups: [String: [String]] = [:]
        for file in files {
            let root = packageRoot(for: file, projectRoot: projectRoot)
            groups[root, default: []].append(file)
        }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted()) }
    }
}
