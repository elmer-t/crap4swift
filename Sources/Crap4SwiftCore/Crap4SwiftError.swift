import Foundation

public enum Crap4SwiftError: Error, Equatable, LocalizedError {
    case unknownOption(String)
    case conflictingArguments(String)
    case missingOptionValue(String)
    case unreadableSource(path: String, reason: String)
    case unreadableCoverage(path: String, reason: String)
    case coverageCommandFailed(command: String, exitCode: Int32, output: String)
    case commandLaunchFailed(command: String, reason: String)

    /// Two families of failure, kept apart: what the command line got wrong,
    /// and what the filesystem or a subprocess got wrong. One switch over
    /// every case would score its own gate at the threshold, and the next
    /// error added would push it past saving.
    public var errorDescription: String? {
        usageMessage ?? accessMessage
    }

    /// The caller asked for something that does not make sense.
    private var usageMessage: String? {
        switch self {
        case .unknownOption(let option):
            return "unknown option: \(option)"
        case .conflictingArguments(let detail):
            return detail
        case .missingOptionValue(let option):
            return "\(option) needs a value"
        default:
            return nil
        }
    }

    /// The caller asked for something reasonable and the world refused.
    private var accessMessage: String? {
        switch self {
        case .unreadableSource(let path, let reason):
            return "cannot read source file \(path): \(reason)"
        case .unreadableCoverage(let path, let reason):
            return "cannot read coverage export \(path): \(reason)"
        case .coverageCommandFailed(let command, let exitCode, let output):
            return "coverage command failed (exit \(exitCode)): \(command)\(Self.quoted(output))"
        case .commandLaunchFailed(let command, let reason):
            return "cannot run \(command): \(reason)"
        default:
            return nil
        }
    }

    /// Captured command output, appended on its own line, or nothing at all
    /// when the command had nothing to say.
    static func quoted(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\n\(trimmed)"
    }
}

/// Process exit codes, matching the `crap4java` contract.
public enum ExitCode {
    public static let success: Int32 = 0
    public static let usageError: Int32 = 1
    public static let thresholdExceeded: Int32 = 2
}
