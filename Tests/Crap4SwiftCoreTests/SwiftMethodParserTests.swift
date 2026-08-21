import XCTest

@testable import Crap4SwiftCore

final class SwiftMethodParserTests: XCTestCase {
    private let parser = SwiftMethodParser()

    private func parse(_ source: String) -> [MethodDescriptor] {
        parser.parse(source: source, filePath: "/tmp/Fixture.swift")
    }

    private func complexity(of source: String, named name: String) throws -> Int {
        let methods = parse(source)
        let match = try XCTUnwrap(
            methods.first { $0.displayName == name || $0.methodName == name },
            "no method named \(name) in \(methods.map(\.displayName))"
        )
        return match.complexity
    }

    // MARK: - What gets reported

    func testMethodsAreNamedWithTheirTypeAndArgumentLabels() {
        let methods = parse(#"""
        struct Greeter {
            func greet(name: String, loudly: Bool) -> String { name }
            func silent() {}
        }
        """#)

        XCTAssertEqual(methods.map(\.displayName), [
            "Greeter.greet(name:loudly:)",
            "Greeter.silent()",
        ])
    }

    func testUnlabeledParametersKeepTheirUnderscore() {
        let methods = parse(#"""
        enum Math {
            static func double(_ value: Int) -> Int { value * 2 }
        }
        """#)

        XCTAssertEqual(methods.map(\.displayName), ["Math.double(_:)"])
    }

    func testExtensionsAreNamedAfterTheExtendedType() {
        let methods = parse(#"""
        extension String {
            func shout() -> String { uppercased() }
        }
        """#)

        XCTAssertEqual(methods.map(\.displayName), ["String.shout()"])
    }

    func testNestedTypesProduceADottedPath() {
        let methods = parse(#"""
        struct Outer {
            struct Inner {
                func work() {}
            }
        }
        """#)

        XCTAssertEqual(methods.map(\.displayName), ["Outer.Inner.work()"])
    }

    func testNestedFunctionsAreReportedSeparatelyFromTheirContainer() throws {
        let methods = parse(#"""
        func outer(values: [Int]) -> Int {
            func inner(_ x: Int) -> Int {
                x > 0 ? 1 : 0
            }
            return values.map(inner).reduce(0, +)
        }
        """#)

        XCTAssertEqual(methods.map(\.displayName), ["outer(values:)", "outer(values:).inner(_:)"])
        // The nested function's branch belongs to the nested function only.
        XCTAssertEqual(try complexity(of: methods, named: "outer(values:)"), 1)
        XCTAssertEqual(try complexity(of: methods, named: "outer(values:).inner(_:)"), 2)
    }

    func testInitializersDeinitializersAndBodylessDeclarationsAreExcluded() {
        let methods = parse(#"""
        protocol Runnable {
            func run()
            var isReady: Bool { get }
        }

        class Worker: Runnable {
            init(retries: Int) {
                if retries > 0 { self.retries = retries }
            }
            deinit { cleanup() }
            var retries = 0
            var isReady: Bool { retries > 0 }
            func run() {}
        }
        """#)

        XCTAssertEqual(methods.map(\.displayName), [
            "Worker.isReady{get}",
            "Worker.run()",
        ])
    }

    func testAccessorsAreReportedPerAccessor() {
        let methods = parse(#"""
        struct Box {
            private var storage = 0
            var value: Int {
                get { storage }
                set { storage = newValue }
            }
            var doubled: Int { storage * 2 }
            subscript(index: Int) -> Int {
                get { index }
            }
            var watched: Int = 0 {
                didSet { storage = watched }
            }
        }
        """#)

        XCTAssertEqual(methods.map(\.displayName), [
            "Box.value{get}",
            "Box.value{set}",
            "Box.doubled{get}",
            "Box.subscript{get}",
            "Box.watched{didSet}",
        ])
    }

    func testLocationsPointAtTheDeclarationAndSpanTheBody() throws {
        let methods = parse(#"""
        struct Sample {
            func work() {
                print("a")
            }
        }
        """#)

        let work = try XCTUnwrap(methods.first)
        XCTAssertEqual(work.declarationLine, 2)
        XCTAssertEqual(work.bodyStartLine, 2)
        XCTAssertEqual(work.bodyEndLine, 4)
        XCTAssertEqual(work.bodySpan, 2 ... 4)
    }

    func testMalformedSourceStillYieldsWhatCouldBeParsed() {
        // SwiftSyntax recovers from errors rather than throwing, so a broken
        // file degrades to partial results instead of failing the run.
        let methods = parse(#"""
        struct Broken {
            func good() {}
            func bad( {
        }
        """#)

        XCTAssertTrue(methods.contains { $0.methodName == "good()" })
    }

    // MARK: - Complexity

    func testASimpleMethodHasComplexityOne() throws {
        XCTAssertEqual(try complexity(of: #"""
        func plain() -> Int { 1 }
        """#, named: "plain()"), 1)
    }

    func testBranchingStatementsEachAddOne() throws {
        let source = #"""
        func branchy(items: [Int]) throws {
            guard !items.isEmpty else { return }
            for item in items where item > 0 {
                print(item)
            }
            var index = 0
            while index < 3 { index += 1 }
            repeat { index -= 1 } while index > 0
            do {
                try run()
            } catch is CocoaError {
                print("a")
            } catch {
                print("b")
            }
        }
        """#
        // 1 + guard + for + while + repeat + 2 catch clauses
        XCTAssertEqual(try complexity(of: source, named: "branchy(items:)"), 7)
    }

    func testElseIfCountsButBareElseDoesNot() throws {
        let source = #"""
        func classify(_ value: Int) -> String {
            if value < 0 {
                return "negative"
            } else if value == 0 {
                return "zero"
            } else {
                return "positive"
            }
        }
        """#
        XCTAssertEqual(try complexity(of: source, named: "classify(_:)"), 3)
    }

    func testEachCaseItemCountsAndDefaultDoesNot() throws {
        let source = #"""
        func describe(_ value: Int) -> String {
            switch value {
            case 0: return "zero"
            case 1, 2: return "small"
            default: return "large"
            }
        }
        """#
        // 1 + case 0 + two items of `case 1, 2`
        XCTAssertEqual(try complexity(of: source, named: "describe(_:)"), 4)
    }

    func testShortCircuitOperatorsAndTernariesCount() throws {
        let source = #"""
        func decide(a: Bool, b: Bool, c: Int?) -> Int {
            let flag = a && b || !a
            return flag ? (c ?? 0) : -1
        }
        """#
        // 1 + && + || + ?: + ??
        XCTAssertEqual(try complexity(of: source, named: "decide(a:b:c:)"), 5)
    }

    func testOptionalChainingAndTryOptionalAreNotCounted() throws {
        let source = #"""
        func lookup(_ text: String?) -> Int {
            let length = text?.count
            _ = try? Int("1")
            return length ?? 0
        }
        """#
        // 1 + ?? only; `?.` and `try?` are noise, not branching worth scoring.
        XCTAssertEqual(try complexity(of: source, named: "lookup(_:)"), 2)
    }

    func testClosureBranchesCountTowardTheEnclosingMethod() throws {
        let source = #"""
        func normalize(values: [Int]) -> [Int] {
            values.map { $0 > 0 ? $0 : -$0 }
        }
        """#
        XCTAssertEqual(try complexity(of: source, named: "normalize(values:)"), 2)
    }

    func testAccessorComplexityIsMeasuredPerAccessor() throws {
        let source = #"""
        struct Box {
            var storage = 0
            var label: String {
                get { storage > 0 ? "many" : "none" }
                set { storage = newValue.count }
            }
        }
        """#
        XCTAssertEqual(try complexity(of: source, named: "Box.label{get}"), 2)
        XCTAssertEqual(try complexity(of: source, named: "Box.label{set}"), 1)
    }

    func testLocalTypesDoNotLeakComplexityIntoTheirContainer() throws {
        let source = #"""
        func container() {
            struct Local {
                func branch(_ x: Int) -> Int { x > 0 ? 1 : 0 }
            }
            _ = Local()
        }
        """#
        XCTAssertEqual(try complexity(of: source, named: "container()"), 1)
        XCTAssertEqual(try complexity(of: source, named: "container().Local.branch(_:)"), 2)
    }

    // MARK: - Helper

    private func complexity(of methods: [MethodDescriptor], named name: String) throws -> Int {
        try XCTUnwrap(methods.first { $0.displayName == name }).complexity
    }
}
