import Foundation

/// Locates the Swift files to analyze.
///
/// SwiftPM's `Sources` directory is the analog of Maven's `src` in `crap4java`.
/// `Tests` is deliberately not scanned: test code is the measuring stick, not
/// the thing being measured.
public struct SourceFileFinder {
    public static let sourcesDirectoryName = "Sources"

    /// Directories never descended into while looking for sources.
    static let skippedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "DerivedData", "Carthage", "Pods",
    ]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Every `.swift` file under `<projectRoot>/Sources`.
    public func allSourceFiles(projectRoot: String) -> [String] {
        let sources = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(Self.sourcesDirectoryName).path
        return swiftFiles(under: sources)
    }

    /// Expands explicit CLI paths: files are taken as-is, directories are
    /// expanded to their `Sources` subtree. Results are de-duplicated and sorted.
    public func expand(paths: [String], projectRoot: String) -> [String] {
        var found: [String] = []
        for path in paths {
            let absolute = Self.absolutePath(path, relativeTo: projectRoot)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: absolute, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                found += allSourceFiles(projectRoot: absolute)
            } else if absolute.hasSuffix(".swift") {
                found.append(Self.normalized(absolute))
            }
        }
        return Self.deduplicatedAndSorted(found)
    }

    func swiftFiles(under directory: String) -> [String] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var found: [String] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if Self.skippedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension == "swift" {
                found.append(Self.normalized(url.path))
            }
        }
        return Self.deduplicatedAndSorted(found)
    }

    static func deduplicatedAndSorted(_ paths: [String]) -> [String] {
        Array(Set(paths)).sorted()
    }

    static func absolutePath(_ path: String, relativeTo root: String) -> String {
        let url = (path as NSString).isAbsolutePath
            ? URL(fileURLWithPath: path)
            : URL(fileURLWithPath: root).appendingPathComponent(path)
        return normalized(url.path)
    }

    static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Path relative to `root`, for display in the report.
    public static func displayPath(_ path: String, relativeTo root: String) -> String {
        let normalizedRoot = normalized(root)
        let normalizedPath = normalized(path)
        let prefix = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        guard normalizedPath.hasPrefix(prefix) else { return normalizedPath }
        return String(normalizedPath.dropFirst(prefix.count))
    }
}
