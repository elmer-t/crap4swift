import XCTest

@testable import SampleLib

final class FizzTests: XCTestCase {
    // Both branches of `label` are exercised, so its CRAP score collapses to
    // its complexity. `summarize` is left untested on purpose.
    func testLabelSpellsOutFizzBuzz() {
        XCTAssertEqual(Fizz.label(30), "FizzBuzz")
    }

    func testLabelFallsBackToTheNumber() {
        XCTAssertEqual(Fizz.label(7), "7")
    }
}
