import Foundation

public enum Crap4SwiftError: Error, Equatable, LocalizedError {
    case unknownOption(String)
    case conflictingArguments(String)
    case unreadableSource(path: String, reason: String)
    case coverageCommandFailed(command: String, exitCode: Int32, output: String)
    case commandLaunchFailed(command: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unknownOption(let option):
            return "unknown option: \(option)"
        case .conflictingArguments(let detail):
            return detail
        case .unreadableSource(let path, let reason):
            return "cannot read source file \(path): \(reason)"
        case .coverageCommandFailed(let command, let exitCode, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = trimmed.isEmpty ? "" : "\n\(trimmed)"
            return "coverage command failed (exit \(exitCode)): \(command)\(tail)"
        case .commandLaunchFailed(let command, let reason):
            return "cannot run \(command): \(reason)"
        }
    }
}

/// Process exit codes, matching the `crap4java` contract.
public enum ExitCode {
    public static let success: Int32 = 0
    public static let usageError: Int32 = 1
    public static let thresholdExceeded: Int32 = 2
}
