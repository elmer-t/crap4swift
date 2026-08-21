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
        if arguments.isEmpty { return CliArguments(mode: .all) }

        var changed = false
        var paths: [String] = []

        for argument in arguments {
            switch argument {
            case "--help", "-h":
                return CliArguments(mode: .help)
            case "--changed":
                changed = true
            default:
                if argument.hasPrefix("-") {
                    throw Crap4SwiftError.unknownOption(argument)
                }
                paths.append(argument)
            }
        }

        if changed && !paths.isEmpty {
            throw Crap4SwiftError.conflictingArguments("--changed cannot be combined with explicit paths")
        }
        if changed { return CliArguments(mode: .changed) }
        return CliArguments(mode: .paths(paths))
    }
}
