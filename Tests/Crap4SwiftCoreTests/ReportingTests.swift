import XCTest

@testable import Crap4SwiftCore

final class CrapAnalyzerTests: XCTestCase {
    /// Lines 2...7 hold `risky`, lines 8...10 hold `safe`.
    private static let source = #"""
    struct Demo {
        func risky(_ value: Int) -> Int {
            if value > 0 {
                return value
            }
            return -value
        }
        func safe() -> Int {
            0
        }
    }
    """#

    private func makeFile() throws -> (TemporaryDirectory, String) {
        let directory = try TemporaryDirectory()
        let path = try directory.write(Self.source, to: "Sources/Demo/Demo.swift")
        return (directory, path)
    }

    private func coverage(for path: String, records: [CoverageRecord]) -> CoverageData {
        CoverageData(recordsByFile: [CoverageData.normalizeKey(path): records])
    }

    func testComplexityAndCoverageAreCombinedIntoScores() throws {
        let (directory, path) = try makeFile()
        _ = directory

        let metrics = try CrapAnalyzer().analyze(
            files: [path],
            coverage: coverage(for: path, records: [
                CoverageRecord(startLine: 2, endLine: 7, coveredRegions: 0, totalRegions: 4),
                CoverageRecord(startLine: 8, endLine: 10, coveredRegions: 1, totalRegions: 1),
            ])
        )

        XCTAssertEqual(metrics.map(\.descriptor.displayName), ["Demo.risky(_:)", "Demo.safe()"])
        XCTAssertEqual(metrics[0].descriptor.complexity, 2)
        XCTAssertEqual(metrics[0].coverage, 0.0)
        // 2^2 * 1^3 + 2
        XCTAssertEqual(metrics[0].crap, .value(6.0))
        XCTAssertEqual(metrics[1].coverage, 1.0)
        XCTAssertEqual(metrics[1].crap, .value(1.0))
    }

    func testMethodsWithoutCoverageScoreNotAvailableAndSortLast() throws {
        let (directory, path) = try makeFile()
        _ = directory

        let metrics = try CrapAnalyzer().analyze(
            files: [path],
            coverage: coverage(for: path, records: [
                CoverageRecord(startLine: 8, endLine: 10, coveredRegions: 0, totalRegions: 2),
            ])
        )

        XCTAssertEqual(metrics.map(\.descriptor.displayName), ["Demo.safe()", "Demo.risky(_:)"])
        XCTAssertEqual(metrics[0].crap, .value(2.0))
        XCTAssertEqual(metrics[1].crap, .notAvailable)
        XCTAssertNil(metrics[1].coverage)
    }

    func testEverythingIsNotAvailableWhenCoverageIsMissing() throws {
        let (directory, path) = try makeFile()
        _ = directory

        let metrics = try CrapAnalyzer().analyze(files: [path], coverage: .unavailable)

        XCTAssertEqual(metrics.count, 2)
        XCTAssertTrue(metrics.allSatisfy { $0.crap == .notAvailable })
        XCTAssertEqual(CrapAnalyzer.maximumCrap(metrics), 0.0)
    }

    func testUnreadableFileIsReported() {
        XCTAssertThrowsError(try CrapAnalyzer().analyze(files: ["/nope/missing.swift"], coverage: .unavailable)) { error in
            guard let analyzeError = error as? Crap4SwiftError,
                  case .unreadableSource(let path, _) = analyzeError
            else {
                return XCTFail("expected an unreadable-source error, got \(error)")
            }
            XCTAssertEqual(path, "/nope/missing.swift")
        }
    }

    func testNestedSpansAreExcludedFromTheirContainer() {
        let outer = descriptor(methodName: "outer()", bodyStartLine: 1, bodyEndLine: 10)
        let inner = descriptor(methodName: "inner()", bodyStartLine: 3, bodyEndLine: 5)
        let sibling = descriptor(methodName: "sibling()", bodyStartLine: 12, bodyEndLine: 14)

        let nested = CrapAnalyzer.nestedSpans(of: outer, among: [outer, inner, sibling])

        XCTAssertEqual(nested, [3 ... 5])
    }

    func testSortingIsStableForEqualScores() {
        let metrics = CrapAnalyzer.sorted([
            MethodMetrics(descriptor: descriptor(methodName: "b()", complexity: 2), coverage: 0.0),
            MethodMetrics(descriptor: descriptor(methodName: "a()", complexity: 2), coverage: 0.0),
            MethodMetrics(descriptor: descriptor(methodName: "c()", complexity: 4), coverage: 0.0),
        ])

        XCTAssertEqual(metrics.map(\.descriptor.methodName), ["c()", "a()", "b()"])
    }
}

final class ReportFormatterTests: XCTestCase {
    private let metrics = CrapAnalyzer.sorted([
        MethodMetrics(
            descriptor: descriptor(
                typeName: "Greeter",
                methodName: "greet(name:)",
                filePath: "/proj/Sources/Demo/Greeter.swift",
                declarationLine: 12,
                complexity: 5
            ),
            coverage: 0.0
        ),
        MethodMetrics(
            descriptor: descriptor(
                typeName: "Greeter",
                methodName: "name{get}",
                filePath: "/proj/Sources/Demo/Greeter.swift",
                declarationLine: 4,
                complexity: 1
            ),
            coverage: 1.0
        ),
        MethodMetrics(
            descriptor: descriptor(
                typeName: "Greeter",
                methodName: "unmeasured()",
                filePath: "/proj/Sources/Demo/Greeter.swift",
                declarationLine: 20,
                complexity: 3
            ),
            coverage: nil
        ),
    ])

    private func report() -> String {
        ReportFormatter().format(metrics, relativeTo: "/proj")
    }

    func testHeaderAndRowsAreRenderedWorstFirst() {
        let lines = report().split(separator: "\n").map(String.init)

        XCTAssertTrue(lines[0].contains("CRAP"))
        XCTAssertTrue(lines[0].contains("COVERAGE"))
        XCTAssertTrue(lines[0].contains("METHOD"))
        XCTAssertTrue(lines[2].contains("Greeter.greet(name:)"))
        XCTAssertTrue(lines[2].contains("30.00"))
        XCTAssertTrue(lines[2].contains("0.00%"))
        XCTAssertTrue(lines[3].contains("Greeter.name{get}"))
        XCTAssertTrue(lines[3].contains("100.00%"))
    }

    func testUnscoredMethodsRenderAsNotAvailableAndComeLast() {
        let lines = report().split(separator: "\n").map(String.init)
        let last = lines[4]

        XCTAssertTrue(last.contains("Greeter.unmeasured()"))
        XCTAssertTrue(last.contains("N/A"))
    }

    func testLocationsAreRelativeToTheProjectRoot() {
        XCTAssertTrue(report().contains("Sources/Demo/Greeter.swift:12"))
        XCTAssertFalse(report().contains("/proj/Sources"))
    }

    func testSummaryCountsMethodsGapsAndThresholdBreaches() {
        let summary = ReportFormatter().summary(metrics)

        XCTAssertTrue(summary.contains("3 methods analyzed"))
        XCTAssertTrue(summary.contains("1 without coverage"))
        XCTAssertTrue(summary.contains("1 over the threshold of 8.00"))
        XCTAssertTrue(summary.contains("worst 30.00 in Greeter.greet(name:)"))
    }

    func testEmptyReport() {
        XCTAssertEqual(ReportFormatter().format([], relativeTo: "/proj"), "No methods to score.")
    }
}
