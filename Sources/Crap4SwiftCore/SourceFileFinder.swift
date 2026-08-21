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

    /// Vendored code and build products, plus anything that looks like a test
    /// directory. Under `Sources` the test rule never fires; outside it, where
    /// a project keeps `WadNavTests` beside `WadNav`, it is the only thing
    /// keeping the measuring stick out of the measurement.
    /// The package manifest is build configuration rather than code under
    /// test, and it is the one `.swift` file a SwiftPM project keeps at its
    /// root — exactly where the fallback scan would otherwise sweep it in.
    static func isManifest(_ fileName: String) -> Bool {
        fileName == PackageRootFinder.manifestName || fileName.hasPrefix("Package@swift-")
    }

    static func isExcluded(_ directoryName: String) -> Bool {
        skippedDirectories.contains(directoryName) || directoryName.hasSuffix("Tests")
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Every `.swift` file under `<projectRoot>/Sources` — or under the root
    /// itself when there is no `Sources` directory.
    ///
    /// SwiftPM's layout is a convention, not a law: an Xcode target keeps its
    /// sources wherever the project file says they are. Falling back to the
    /// root keeps the same promise for those projects — everything except the
    /// tests — rather than reporting that a codebase has no code in it.
    public func allSourceFiles(projectRoot: String) -> [String] {
        swiftFiles(under: sourceRoot(of: projectRoot))
    }

    /// `<directory>/Sources` when that exists, the directory itself otherwise.
    func sourceRoot(of directory: String) -> String {
        let sources = URL(fileURLWithPath: directory)
            .appendingPathComponent(Self.sourcesDirectoryName).path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sources, isDirectory: &isDirectory), isDirectory.boolValue
        else { return directory }
        return sources
    }

    /// Expands explicit CLI paths: files are taken as-is, directories are
    /// expanded to their `Sources` subtree — or to themselves, when they have
    /// none. Results are de-duplicated and sorted.
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
        guard let walk = makeEnumerator(for: directory) else { return [] }

        var found: [String] = []
        for case let url as URL in walk {
            if isDirectory(url) {
                skipDescendantsIfExcluded(url, in: walk)
            } else if url.pathExtension == "swift", !Self.isManifest(url.lastPathComponent) {
                found.append(Self.normalized(url.path))
            }
        }
        return Self.deduplicatedAndSorted(found)
    }

    private func makeEnumerator(for directory: String) -> FileManager.DirectoryEnumerator? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return fileManager.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private func skipDescendantsIfExcluded(_ url: URL, in walk: FileManager.DirectoryEnumerator) {
        guard Self.isExcluded(url.lastPathComponent) else { return }
        walk.skipDescendants()
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
