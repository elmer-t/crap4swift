import Foundation

/// Coverage that somebody else generated.
///
/// `swift test` is not the only way to instrument Swift. An Xcode scheme, a CI
/// job and a Bazel run all end at the same llvm-cov export, and reading one
/// that already exists keeps this tool out of the business of knowing how the
/// tests were run — which is the part that differs between build systems, and
/// the part most likely to lie when it is guessed.
public struct SuppliedCoverage {
    private let fileManager: FileManager
    private let parser: LlvmCovCoverageParser

    public init(
        fileManager: FileManager = .default,
        parser: LlvmCovCoverageParser = LlvmCovCoverageParser()
    ) {
        self.fileManager = fileManager
        self.parser = parser
    }

    /// Reads the export, or fails loudly.
    ///
    /// A missing export from `swift test` is a warning, because the tool went
    /// looking for it. An unreadable export named on the command line is an
    /// error, because somebody asked for that file by name and scoring every
    /// method `N/A` would answer a question they did not ask.
    public func read(path: String) throws -> CoverageData {
        do {
            return try parser.parse(file: path)
        } catch {
            throw Crap4SwiftError.unreadableCoverage(path: path, reason: "\(error)")
        }
    }

    /// The analyzed files modified after the export was written.
    ///
    /// This is the one failure mode supplied coverage has that generated
    /// coverage does not: a stale export keeps producing plausible numbers
    /// about code that is no longer there. Saying so is cheaper than being
    /// quietly misled by it.
    public func sourcesNewerThan(_ path: String, among files: [String]) -> [String] {
        guard let exported = modificationDate(of: path) else { return [] }
        return files.filter { (modificationDate(of: $0) ?? .distantPast) > exported }
    }

    func modificationDate(of path: String) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
