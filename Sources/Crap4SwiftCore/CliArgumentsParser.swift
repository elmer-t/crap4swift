import Foundation

public enum CliArgumentsParser {
    public static let coverageOption = "--coverage"

    public static let usage = """
    usage: crap4swift [--changed | <path>...] [--coverage <file>] [--help]

      (no arguments)  Analyze every .swift file under <project-root>/Sources,
                      or under the project root itself when there is no Sources
                      directory. Test directories are never analyzed.
      --changed       Analyze changed .swift files, as reported by
                      `git status --porcelain`.
      <path>...       Analyze each path. A file is analyzed directly; a directory
                      is expanded to the .swift files under <dir>/Sources, or
                      under <dir> itself when it has no Sources directory.
      --coverage <f>  Score against an existing llvm-cov JSON export rather than
                      running the tests. This is how a project SwiftPM does not
                      build — an Xcode scheme, a CI job — gets analyzed:
                      export coverage there, hand the file to crap4swift here.
      --help, -h      Print this message.

    Without --coverage, for every SwiftPM package that owns a selected file,
    crap4swift deletes stale coverage artifacts, runs `swift test
    --enable-code-coverage` and reads the llvm-cov JSON export. Either way it
    reports CRAP = CC^2 * (1 - coverage)^3 + CC per method, worst first.

    Exit codes: 0 success, 1 usage or execution error, 2 CRAP threshold exceeded.
    """

    public static func parse(_ arguments: [String]) throws -> CliArguments {
        guard !arguments.isEmpty else { return CliArguments(mode: .all) }
        let request = try Request(arguments: arguments)
        return CliArguments(mode: try request.mode(), coveragePath: request.coveragePath)
    }

    /// What the argument list said, separated from what it means. Reading and
    /// judging are two jobs, and keeping them apart is what keeps either one
    /// small enough to follow.
    struct Request {
        private(set) var wantsHelp = false
        private(set) var wantsChanged = false
        private(set) var paths: [String] = []
        private(set) var coveragePath: String?
        /// Set by a bare `--coverage`, cleared by the value that follows it.
        private var awaitingCoverageValue = false

        init(arguments: [String]) throws {
            for argument in arguments {
                try absorb(argument)
            }
            guard !awaitingCoverageValue else {
                throw Crap4SwiftError.missingOptionValue(coverageOption)
            }
        }

        private mutating func absorb(_ argument: String) throws {
            if awaitingCoverageValue { return takeCoverageValue(argument) }
            switch argument {
            case "--help", "-h":
                wantsHelp = true
            case "--changed":
                wantsChanged = true
            case coverageOption:
                awaitingCoverageValue = true
            default:
                try absorbOperand(argument)
            }
        }

        private mutating func takeCoverageValue(_ argument: String) {
            coveragePath = argument
            awaitingCoverageValue = false
        }

        /// Anything that is not a recognized flag: an attached `--coverage=path`,
        /// a path to analyze, or a typo worth rejecting.
        private mutating func absorbOperand(_ argument: String) throws {
            if let attached = Self.attachedValue(of: argument, for: coverageOption) {
                return takeCoverageValue(attached)
            }
            guard !argument.hasPrefix("-") else {
                throw Crap4SwiftError.unknownOption(argument)
            }
            paths.append(argument)
        }

        static func attachedValue(of argument: String, for option: String) -> String? {
            let prefix = option + "="
            guard argument.hasPrefix(prefix) else { return nil }
            return String(argument.dropFirst(prefix.count))
        }

        /// Options alone select nothing, so they select everything:
        /// `crap4swift --coverage cov.json` means the same as `crap4swift`.
        func mode() throws -> CliMode {
            if wantsHelp { return .help }
            if wantsChanged && !paths.isEmpty {
                throw Crap4SwiftError.conflictingArguments("--changed cannot be combined with explicit paths")
            }
            if wantsChanged { return .changed }
            return paths.isEmpty ? .all : .paths(paths)
        }
    }
}
