import XCTest

@testable import Crap4SwiftCore

final class CrapScoreTests: XCTestCase {
    func testFullyCoveredMethodScoresItsComplexity() {
        XCTAssertEqual(CrapScore.compute(complexity: 5, coverage: 1.0), .value(5.0))
        XCTAssertEqual(CrapScore.compute(complexity: 1, coverage: 1.0), .value(1.0))
    }

    func testUncoveredMethodScoresComplexitySquaredPlusComplexity() {
        XCTAssertEqual(CrapScore.compute(complexity: 5, coverage: 0.0), .value(30.0))
        XCTAssertEqual(CrapScore.compute(complexity: 1, coverage: 0.0), .value(2.0))
    }

    func testHalfCoveredMethodUsesTheCubedUncoveredFraction() {
        // 4^2 * 0.5^3 + 4 = 2 + 4
        XCTAssertEqual(CrapScore.compute(complexity: 4, coverage: 0.5), .value(6.0))
    }

    func testThreeBranchesWithNoTestsIsAlreadyOverTheThreshold() throws {
        let three = try XCTUnwrap(CrapScore.compute(complexity: 3, coverage: 0.0).numericValue)
        XCTAssertEqual(three, 12.0)
        XCTAssertGreaterThan(three, Crap4Swift.threshold)

        // Two branches without tests still passes, which is where the 8.0
        // threshold gets its bite.
        let two = try XCTUnwrap(CrapScore.compute(complexity: 2, coverage: 0.0).numericValue)
        XCTAssertEqual(two, 6.0)
        XCTAssertLessThan(two, Crap4Swift.threshold)
    }

    func testMissingCoverageHasNoScore() {
        XCTAssertEqual(CrapScore.compute(complexity: 9, coverage: nil), .notAvailable)
        XCTAssertNil(CrapScore.compute(complexity: 9, coverage: nil).numericValue)
    }

    func testCoverageIsClampedToTheUnitInterval() {
        XCTAssertEqual(CrapScore.compute(complexity: 3, coverage: 1.5), .value(3.0))
        XCTAssertEqual(CrapScore.compute(complexity: 3, coverage: -0.5), .value(12.0))
    }

    func testMaximumCrapIgnoresUnscoredMethodsAndDefaultsToZero() {
        XCTAssertEqual(CrapAnalyzer.maximumCrap([]), 0.0)

        let metrics = [
            MethodMetrics(descriptor: descriptor(complexity: 3), coverage: nil),
            MethodMetrics(descriptor: descriptor(complexity: 2), coverage: 0.0),
        ]
        XCTAssertEqual(CrapAnalyzer.maximumCrap(metrics), 6.0)
    }
}
