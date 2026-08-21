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
    public init(mode: CliMode) {
        self.mode = mode
    }
}
