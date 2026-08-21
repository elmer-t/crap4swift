import XCTest

@testable import Crap4SwiftCore

final class SuppliedCoverageTests: XCTestCase {
    private func makeExport(_ directory: TemporaryDirectory, sourcePath: String) throws -> String {
        try directory.write(
            """
            {"data": [{"functions": [
              {"name": "f", "count": 1, "filenames": ["\(sourcePath)"],
               "regions": [[2, 1, 6, 2, 1, 0, 0, 0]]}
            ]}]}
            """,
            to: "coverage.json"
        )
    }

    func testAnExportIsReadIntoCoverage() throws {
        let directory = try TemporaryDirectory()
        let source = try directory.write("struct A {}", to: "A.swift")
        let export = try makeExport(directory, sourcePath: source)

        let coverage = try SuppliedCoverage().read(path: export)

        XCTAssertEqual(coverage.coverage(forFile: source, span: 1 ... 10), 1.0)
    }

    func testAMissingExportIsAnErrorRatherThanAnEmptyReport() throws {
        let directory = try TemporaryDirectory()

        XCTAssertThrowsError(try SuppliedCoverage().read(path: directory.path("nope.json"))) { error in
            guard let failure = error as? Crap4SwiftError,
                  case .unreadableCoverage(let path, _) = failure
            else {
                return XCTFail("expected an unreadable-coverage error, got \(error)")
            }
            XCTAssertTrue(path.hasSuffix("nope.json"))
        }
    }

    func testMalformedJsonIsAnError() throws {
        let directory = try TemporaryDirectory()
        let export = try directory.write("{ not json", to: "coverage.json")

        XCTAssertThrowsError(try SuppliedCoverage().read(path: export))
    }

    func testSourcesWrittenAfterTheExportAreReportedStale() throws {
        let directory = try TemporaryDirectory()
        let old = try directory.write("struct Old {}", to: "Old.swift")
        let export = try makeExport(directory, sourcePath: old)
        let fresh = try directory.write("struct Fresh {}", to: "Fresh.swift")
        try touch(fresh, secondsAfterNow: 60)

        let stale = SuppliedCoverage().sourcesNewerThan(export, among: [old, fresh])

        XCTAssertEqual(stale, [fresh])
    }

    func testNothingIsStaleWhenTheExportIsTheYoungestFile() throws {
        let directory = try TemporaryDirectory()
        let source = try directory.write("struct A {}", to: "A.swift")
        let export = try makeExport(directory, sourcePath: source)
        try touch(export, secondsAfterNow: 60)

        XCTAssertEqual(SuppliedCoverage().sourcesNewerThan(export, among: [source]), [])
    }

    /// An unreadable export cannot be younger than anything, so a staleness
    /// check on it stays quiet and lets `read` do the complaining.
    func testAMissingExportIsNeverStale() throws {
        let directory = try TemporaryDirectory()
        let source = try directory.write("struct A {}", to: "A.swift")

        XCTAssertEqual(SuppliedCoverage().sourcesNewerThan(directory.path("nope.json"), among: [source]), [])
    }

    private func touch(_ path: String, secondsAfterNow seconds: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(seconds)],
            ofItemAtPath: path
        )
    }
}
