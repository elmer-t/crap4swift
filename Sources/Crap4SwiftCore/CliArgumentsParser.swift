import Foundation

public enum CliArgumentsParser {
    public static let usage = """
    usage: crap4swift [--changed | <path>...] [--help]

      (no arguments)  Analyze every .swift file under <project-root>/Sources.
      --changed       Analyze changed .swift files under <project-root>/Sources,
                      as reported by `git status --porcelain`.
      <path>...       Analyze each path. A file is analyzed directly; a directory
                      is expanded to the .swift files under <dir>/Sources.
      --help, -h      Print this message.

    For every SwiftPM package that owns a selected file, crap4swift deletes stale
    coverage artifacts, runs `swift test --enable-code-coverage`, reads the
    llvm-cov JSON export, and reports CRAP = CC^2 * (1 - coverage)^3 + CC per
    method, worst first.

    Exit codes: 0 success, 1 usage or execution error, 2 CRAP threshold exceeded.
    """

    public static func parse(_ arguments: [String]) throws -> CliArguments {
        guard !arguments.isEmpty else { return CliArguments(mode: .all) }
        return CliArguments(mode: try Request(arguments: arguments).mode())
    }

    /// What the argument list said, separated from what it means. Reading and
    /// judging are two jobs, and keeping them apart is what keeps either one
    /// small enough to follow.
    struct Request {
        private(set) var wantsHelp = false
        private(set) var wantsChanged = false
        private(set) var paths: [String] = []

        init(arguments: [String]) throws {
            for argument in arguments {
                try absorb(argument)
            }
        }

        private mutating func absorb(_ argument: String) throws {
            switch argument {
            case "--help", "-h":
                wantsHelp = true
            case "--changed":
                wantsChanged = true
            default:
                try absorbOperand(argument)
            }
        }

        private mutating func absorbOperand(_ argument: String) throws {
            guard !argument.hasPrefix("-") else {
                throw Crap4SwiftError.unknownOption(argument)
            }
            paths.append(argument)
        }

        func mode() throws -> CliMode {
            if wantsHelp { return .help }
            if wantsChanged && !paths.isEmpty {
                throw Crap4SwiftError.conflictingArguments("--changed cannot be combined with explicit paths")
            }
            return wantsChanged ? .changed : .paths(paths)
        }
    }
}
