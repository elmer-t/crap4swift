import Foundation

public struct CommandResult: Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { exitCode == 0 }
}

/// Seam for everything crap4swift shells out to (`git`, `swift`), so the rest of
/// the tool stays unit-testable.
public protocol CommandExecutor {
    func execute(_ command: String, arguments: [String], workingDirectory: String) throws -> CommandResult
}
