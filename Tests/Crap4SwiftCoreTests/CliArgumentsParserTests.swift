import XCTest

@testable import Crap4SwiftCore

final class CliArgumentsParserTests: XCTestCase {
    func testNoArgumentsAnalyzesEverything() throws {
        XCTAssertEqual(try CliArgumentsParser.parse([]).mode, .all)
    }

    func testChangedFlag() throws {
        XCTAssertEqual(try CliArgumentsParser.parse(["--changed"]).mode, .changed)
    }

    func testHelpFlags() throws {
        XCTAssertEqual(try CliArgumentsParser.parse(["--help"]).mode, .help)
        XCTAssertEqual(try CliArgumentsParser.parse(["-h"]).mode, .help)
    }

    func testHelpWinsOverOtherArguments() throws {
        XCTAssertEqual(try CliArgumentsParser.parse(["Sources", "--help"]).mode, .help)
    }

    func testExplicitPathsArePreserved() throws {
        let mode = try CliArgumentsParser.parse(["Sources/A.swift", "Packages/Lib"]).mode
        XCTAssertEqual(mode, .paths(["Sources/A.swift", "Packages/Lib"]))
    }

    func testCoverageOptionTakesTheFollowingArgument() throws {
        let arguments = try CliArgumentsParser.parse(["--coverage", "build/cov.json"])

        XCTAssertEqual(arguments.coveragePath, "build/cov.json")
        XCTAssertEqual(arguments.mode, .all)
    }

    func testCoverageOptionAlsoTakesAnAttachedValue() throws {
        XCTAssertEqual(
            try CliArgumentsParser.parse(["--coverage=build/cov.json"]).coveragePath,
            "build/cov.json"
        )
    }

    func testCoverageCombinesWithPathsAndWithChanged() throws {
        let paths = try CliArgumentsParser.parse(["--coverage", "cov.json", "WadNav"])
        XCTAssertEqual(paths.mode, .paths(["WadNav"]))
        XCTAssertEqual(paths.coveragePath, "cov.json")

        let changed = try CliArgumentsParser.parse(["--changed", "--coverage", "cov.json"])
        XCTAssertEqual(changed.mode, .changed)
        XCTAssertEqual(changed.coveragePath, "cov.json")
    }

    /// The value is taken verbatim: a file may legitimately be named `--odd`,
    /// and the argument after `--coverage` is a value, not a flag.
    func testTheValueAfterCoverageIsNotParsedAsAFlag() throws {
        XCTAssertEqual(try CliArgumentsParser.parse(["--coverage", "--changed"]).coveragePath, "--changed")
    }

    func testCoverageWithoutAValueIsRejected() {
        XCTAssertThrowsError(try CliArgumentsParser.parse(["--coverage"])) { error in
            XCTAssertEqual(error as? Crap4SwiftError, .missingOptionValue("--coverage"))
        }
    }

    func testNoCoverageIsTheDefault() throws {
        XCTAssertNil(try CliArgumentsParser.parse([]).coveragePath)
        XCTAssertNil(try CliArgumentsParser.parse(["--changed"]).coveragePath)
    }

    func testUnknownOptionIsRejected() {
        XCTAssertThrowsError(try CliArgumentsParser.parse(["--nope"])) { error in
            XCTAssertEqual(error as? Crap4SwiftError, .unknownOption("--nope"))
        }
    }

    func testChangedCannotBeCombinedWithPaths() {
        XCTAssertThrowsError(try CliArgumentsParser.parse(["--changed", "Sources/A.swift"])) { error in
            guard let parseError = error as? Crap4SwiftError,
                  case .conflictingArguments(_) = parseError
            else {
                return XCTFail("expected a conflicting-arguments error, got \(error)")
            }
        }
    }

    func testUsageMentionsEveryMode() {
        let usage = CliArgumentsParser.usage
        XCTAssertTrue(usage.contains("--changed"))
        XCTAssertTrue(usage.contains("--help"))
        XCTAssertTrue(usage.contains("Sources"))
    }
}
