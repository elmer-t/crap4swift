import XCTest

@testable import Crap4SwiftCore

final class Crap4SwiftErrorTests: XCTestCase {
    private func description(of error: Crap4SwiftError) throws -> String {
        try XCTUnwrap(error.errorDescription)
    }

    func testUnknownOptionNamesTheOption() throws {
        XCTAssertEqual(try description(of: .unknownOption("--wat")), "unknown option: --wat")
    }

    func testConflictingArgumentsIsPassedThrough() throws {
        XCTAssertEqual(try description(of: .conflictingArguments("pick one")), "pick one")
    }

    func testUnreadableSourceNamesThePathAndReason() throws {
        let text = try description(of: .unreadableSource(path: "/a/B.swift", reason: "no such file"))
        XCTAssertEqual(text, "cannot read source file /a/B.swift: no such file")
    }

    func testCommandLaunchFailureNamesTheCommand() throws {
        XCTAssertEqual(try description(of: .commandLaunchFailed(command: "git", reason: "not found")),
                       "cannot run git: not found")
    }

    func testCoverageFailureQuotesTheCommandOutput() throws {
        let text = try description(of: .coverageCommandFailed(
            command: "swift test",
            exitCode: 2,
            output: "  1 test failed\n"
        ))
        XCTAssertEqual(text, "coverage command failed (exit 2): swift test\n1 test failed")
    }

    func testCoverageFailureOmitsEmptyOutput() throws {
        let text = try description(of: .coverageCommandFailed(command: "swift test", exitCode: 1, output: "  \n "))
        XCTAssertEqual(text, "coverage command failed (exit 1): swift test")
    }

    func testQuotedOutputIsTrimmedOrDropped() {
        XCTAssertEqual(Crap4SwiftError.quoted(""), "")
        XCTAssertEqual(Crap4SwiftError.quoted("\n  \n"), "")
        XCTAssertEqual(Crap4SwiftError.quoted(" boom \n"), "\nboom")
    }

    func testErrorsAreSurfacedThroughTheCliMessageHelper() {
        XCTAssertEqual(CliApplication.message(for: Crap4SwiftError.unknownOption("-x")), "unknown option: -x")

        struct Plain: Error {}
        XCTAssertFalse(CliApplication.message(for: Plain()).isEmpty)
    }
}
