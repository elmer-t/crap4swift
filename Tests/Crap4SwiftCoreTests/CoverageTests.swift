import XCTest

@testable import Crap4SwiftCore

final class LlvmCovCoverageParserTests: XCTestCase {
    private let parser = LlvmCovCoverageParser()

    private static let export = #"""
    {
      "version": "2.0.1",
      "type": "llvm.coverage.json.export",
      "data": [
        {
          "files": [],
          "functions": [
            {
              "name": "$s4Demo7GreeterV5greetyS2SF",
              "count": 3,
              "filenames": ["/proj/Sources/Demo/Greeter.swift"],
              "regions": [
                [10, 30, 16, 6, 3, 0, 0, 0],
                [12, 20, 14, 10, 0, 0, 0, 0],
                [15, 1, 15, 20, 0, 0, 0, 2],
                [11, 1, 11, 9, 7, 0, 1, 1]
              ]
            },
            {
              "name": "$s4Demo7GreeterV4nameSSvg",
              "count": 1,
              "filenames": ["/proj/Sources/Demo/Greeter.swift"],
              "regions": [
                [4, 25, 4, 40, 9, 0, 0, 0]
              ]
            }
          ],
          "totals": {}
        }
      ]
    }
    """#

    func testFunctionRecordsAreIndexedByFile() throws {
        let coverage = try parser.parse(jsonData: Data(Self.export.utf8))
        let key = CoverageData.normalizeKey("/proj/Sources/Demo/Greeter.swift")
        XCTAssertEqual(coverage.recordsByFile.count, 1)
        XCTAssertEqual(coverage.recordsByFile[key]?.count, 2)
        XCTAssertTrue(coverage.isAvailable)
    }

    func testOnlyCodeRegionsAreCounted() throws {
        let coverage = try parser.parse(jsonData: Data(Self.export.utf8))
        let key = CoverageData.normalizeKey("/proj/Sources/Demo/Greeter.swift")
        let record = try XCTUnwrap(coverage.recordsByFile[key]?.last)

        // The skipped (kind 2) and expansion (kind 1) regions are ignored, so
        // only the two kind-0 regions count, one of which ran.
        XCTAssertEqual(record.startLine, 10)
        XCTAssertEqual(record.endLine, 16)
        XCTAssertEqual(record.totalRegions, 2)
        XCTAssertEqual(record.coveredRegions, 1)
    }

    func testRecordsAreSortedByPosition() throws {
        let coverage = try parser.parse(jsonData: Data(Self.export.utf8))
        let key = CoverageData.normalizeKey("/proj/Sources/Demo/Greeter.swift")
        XCTAssertEqual(coverage.recordsByFile[key]?.map(\.startLine), [4, 10])
    }

    func testFunctionWithoutCodeRegionsIsDropped() {
        XCTAssertNil(LlvmCovCoverageParser.record(from: [[1, 1, 2, 2, 0, 0, 0, 2]]))
        XCTAssertNil(LlvmCovCoverageParser.record(from: []))
    }

    func testShortRegionArraysAreTreatedAsCodeRegions() throws {
        // Older llvm-cov versions emit fewer trailing fields.
        let record = try XCTUnwrap(LlvmCovCoverageParser.record(from: [[3, 1, 5, 2, 4]]))
        XCTAssertEqual(record.startLine, 3)
        XCTAssertEqual(record.coveredRegions, 1)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try parser.parse(jsonData: Data("not json".utf8)))
    }

    func testUnavailableCoverageHasNoRecords() {
        XCTAssertFalse(CoverageData.unavailable.isAvailable)
        XCTAssertNil(CoverageData.unavailable.coverage(forFile: "/a.swift", span: 1 ... 10))
    }
}

final class CoverageDataTests: XCTestCase {
    private let file = "/proj/Sources/Demo/Greeter.swift"

    private func data(_ records: [CoverageRecord]) -> CoverageData {
        CoverageData(recordsByFile: [CoverageData.normalizeKey(file): records])
    }

    func testRecordsStartingInsideTheBodyAreAttributedToIt() {
        let coverage = data([
            CoverageRecord(startLine: 10, endLine: 20, coveredRegions: 3, totalRegions: 4),
        ])
        XCTAssertEqual(coverage.coverage(forFile: file, span: 10 ... 20), 0.75)
    }

    func testClosureRecordsInsideTheBodyAreFoldedIn() {
        // Matching ComplexityCounter, which counts closure branches as part of
        // the enclosing method.
        let coverage = data([
            CoverageRecord(startLine: 10, endLine: 20, coveredRegions: 2, totalRegions: 2),
            CoverageRecord(startLine: 14, endLine: 16, coveredRegions: 0, totalRegions: 2),
        ])
        XCTAssertEqual(coverage.coverage(forFile: file, span: 10 ... 20), 0.5)
    }

    func testRecordsBelongingToNestedUnitsAreExcluded() {
        let coverage = data([
            CoverageRecord(startLine: 10, endLine: 20, coveredRegions: 2, totalRegions: 2),
            CoverageRecord(startLine: 14, endLine: 16, coveredRegions: 0, totalRegions: 2),
        ])
        XCTAssertEqual(coverage.coverage(forFile: file, span: 10 ... 20, excluding: [14 ... 16]), 1.0)
    }

    func testRecordsOutsideTheBodyAreIgnored() {
        let coverage = data([
            CoverageRecord(startLine: 30, endLine: 40, coveredRegions: 0, totalRegions: 4),
        ])
        XCTAssertNil(coverage.coverage(forFile: file, span: 10 ... 20))
    }

    func testUnknownFileHasNoCoverage() {
        let coverage = data([CoverageRecord(startLine: 1, endLine: 2, coveredRegions: 1, totalRegions: 1)])
        XCTAssertNil(coverage.coverage(forFile: "/other.swift", span: 1 ... 2))
    }
}

final class CoverageRunnerTests: XCTestCase {
    private static let minimalExport = #"""
    {
      "data": [
        {
          "functions": [
            {"name": "f", "count": 1, "filenames": ["/proj/A.swift"], "regions": [[1, 1, 3, 2, 1, 0, 0, 0]]}
          ]
        }
      ]
    }
    """#

    func testStaleCoverageDirectoriesAreDeletedBeforeTesting() throws {
        let directory = try TemporaryDirectory()
        try directory.write("stale", to: ".build/arm64-apple-macosx/debug/codecov/Old.json")
        let stale = directory.path(".build/arm64-apple-macosx/debug/codecov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale))

        CoverageRunner(executor: FakeCommandExecutor()).removeStaleArtifacts(packageRoot: directory.path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale))
    }

    func testCoverageIsGeneratedThenRead() throws {
        let directory = try TemporaryDirectory()
        let exportPath = directory.path(".build/debug/codecov/Demo.json")
        let executor = FakeCommandExecutor()
        executor.handler = { invocation in
            if invocation.arguments.contains("--enable-code-coverage") {
                // Stand in for SwiftPM writing the export.
                try directory.write(Self.minimalExport, to: ".build/debug/codecov/Demo.json")
                return .success()
            }
            return .success(exportPath + "\n")
        }

        let coverage = try CoverageRunner(executor: executor).generateCoverage(packageRoot: directory.path)

        XCTAssertTrue(coverage.isAvailable)
        XCTAssertEqual(coverage.coverage(forFile: "/proj/A.swift", span: 1 ... 3), 1.0)
        XCTAssertEqual(executor.invocations.first?.command, "swift")
        XCTAssertEqual(executor.invocations.first?.arguments, ["test", "--enable-code-coverage"])
        XCTAssertEqual(executor.invocations.first?.workingDirectory, directory.path)
    }

    func testExportIsFoundByScanningWhenSwiftPMCannotReportIt() throws {
        let directory = try TemporaryDirectory()
        let executor = FakeCommandExecutor()
        executor.handler = { invocation in
            if invocation.arguments.contains("--enable-code-coverage") {
                try directory.write(Self.minimalExport, to: ".build/x86_64-unknown-linux-gnu/debug/codecov/Demo.json")
                return .success()
            }
            return .failure(1, "unsupported flag")
        }

        let coverage = try CoverageRunner(executor: executor).generateCoverage(packageRoot: directory.path)

        XCTAssertTrue(coverage.isAvailable)
    }

    func testMissingExportWarnsAndReportsNoCoverage() throws {
        let directory = try TemporaryDirectory()
        let warnings = OutputRecorder()
        let executor = FakeCommandExecutor { _ in .success() }

        let coverage = try CoverageRunner(executor: executor, warn: warnings.write)
            .generateCoverage(packageRoot: directory.path)

        XCTAssertFalse(coverage.isAvailable)
        XCTAssertTrue(warnings.contains("no llvm-cov export found"))
    }

    func testFailingTestCommandIsFatal() throws {
        let directory = try TemporaryDirectory()
        let executor = FakeCommandExecutor { _ in .failure(1, "2 tests failed") }

        XCTAssertThrowsError(
            try CoverageRunner(executor: executor).generateCoverage(packageRoot: directory.path)
        ) { error in
            guard let runError = error as? Crap4SwiftError,
                  case .coverageCommandFailed(_, let exitCode, let output) = runError
            else {
                return XCTFail("expected a coverage failure, got \(error)")
            }
            XCTAssertEqual(exitCode, 1)
            XCTAssertTrue(output.contains("2 tests failed"))
        }
    }
}
