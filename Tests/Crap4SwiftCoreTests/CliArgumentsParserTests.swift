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
