import Foundation

public enum CliMode: Equatable {
    /// Analyze every Swift file under `<project-root>/Sources`.
    case all
    /// Analyze changed Swift files under `<project-root>/Sources`.
    case changed
    /// Analyze the given files, and the `Sources` subtree of the given directories.
    case paths([String])
    /// Print usage and exit successfully.
    case help
}

public struct CliArguments: Equatable {
    public let mode: CliMode
    /// An llvm-cov export to score against, instead of generating one.
    /// Orthogonal to the mode: what to measure and how it was measured are
    /// two questions.
    public let coveragePath: String?

    public init(mode: CliMode, coveragePath: String? = nil) {
        self.mode = mode
        self.coveragePath = coveragePath
    }
}
