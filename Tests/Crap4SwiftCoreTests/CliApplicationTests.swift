import XCTest

@testable import Crap4SwiftCore

final class CliApplicationTests: XCTestCase {
    /// `risky` spans lines 2...6 and has cyclomatic complexity 3, so with no
    /// coverage it scores 3^2 + 3 = 12 and breaches the threshold.
    private static let source = #"""
    struct Demo {
        func risky(_ value: Int) -> Int {
            if value > 0 { return 1 }
            if value < 0 { return -1 }
            return 0
        }
    }
    """#

    private struct Harness {
        let directory: TemporaryDirectory
        let executor: FakeCommandExecutor
        let output = OutputRecorder()
        let errors = OutputRecorder()

        var application: CliApplication {
            CliApplication(
                projectRoot: directory.path,
                executor: executor,
                standardOutput: output.write,
                standardError: errors.write
            )
        }
    }

    /// A project whose fake `swift test` writes a coverage export in which
    /// `risky` was executed `executionCount` times.
    private func makeHarness(executionCount: Int) throws -> Harness {
        let directory = try TemporaryDirectory()
        try directory.write("// swift-tools-version:5.9", to: "Package.swift")
        let sourcePath = try directory.write(Self.source, to: "Sources/Demo/Demo.swift")

        let export = """
        {"data": [{"functions": [
          {"name": "risky", "count": \(executionCount), "filenames": ["\(sourcePath)"],
           "regions": [[2, 1, 6, 2, \(executionCount), 0, 0, 0]]}
        ]}]}
        """

        let executor = FakeCommandExecutor()
        let exportPath = directory.path(".build/debug/codecov/Demo.json")
        executor.handler = { invocation in
            if invocation.arguments.contains("--enable-code-coverage") {
                try directory.write(export, to: ".build/debug/codecov/Demo.json")
                return .success()
            }
            return .success(exportPath + "\n")
        }
        return Harness(directory: directory, executor: executor)
    }

    // MARK: - Usage

    func testHelpPrintsUsageAndSucceedsWithoutRunningAnything() {
        let output = OutputRecorder()
        let executor = FakeCommandExecutor()
        let application = CliApplication(
            projectRoot: "/proj",
            executor: executor,
            standardOutput: output.write,
            standardError: { _ in }
        )

        XCTAssertEqual(application.run(arguments: ["--help"]), ExitCode.success)
        XCTAssertTrue(output.contains("usage: crap4swift"))
        XCTAssertTrue(executor.invocations.isEmpty)
    }

    func testUnknownOptionExitsWithUsageError() {
        let output = OutputRecorder()
        let errors = OutputRecorder()
        let application = CliApplication(
            projectRoot: "/proj",
            executor: FakeCommandExecutor(),
            standardOutput: output.write,
            standardError: errors.write
        )

        XCTAssertEqual(application.run(arguments: ["--wat"]), ExitCode.usageError)
        XCTAssertTrue(errors.contains("unknown option: --wat"))
        XCTAssertTrue(output.contains("usage: crap4swift"))
    }

    func testEmptySelectionSucceedsWithoutGeneratingCoverage() throws {
        let directory = try TemporaryDirectory()
        try directory.write("// swift-tools-version:5.9", to: "Package.swift")
        let output = OutputRecorder()
        let executor = FakeCommandExecutor()
        let application = CliApplication(
            projectRoot: directory.path,
            executor: executor,
            standardOutput: output.write,
            standardError: { _ in }
        )

        XCTAssertEqual(application.run(arguments: []), ExitCode.success)
        XCTAssertTrue(output.contains("No Swift files to analyze."))
        XCTAssertTrue(executor.invocations.isEmpty)
    }

    // MARK: - Analysis

    func testUncoveredComplexityBreachesTheThreshold() throws {
        let harness = try makeHarness(executionCount: 0)

        let status = harness.application.run(arguments: [])

        XCTAssertEqual(status, ExitCode.thresholdExceeded)
        XCTAssertTrue(harness.output.contains("Demo.risky(_:)"))
        XCTAssertTrue(harness.output.contains("12.00"))
        XCTAssertTrue(harness.errors.contains("CRAP threshold exceeded: 12.00 > 8.00"))
    }

    func testCoveredComplexityPasses() throws {
        let harness = try makeHarness(executionCount: 7)

        let status = harness.application.run(arguments: [])

        XCTAssertEqual(status, ExitCode.success)
        XCTAssertTrue(harness.output.contains("100.00%"))
        XCTAssertFalse(harness.errors.contains("threshold exceeded"))
    }

    func testCoverageIsGeneratedOncePerPackage() throws {
        let harness = try makeHarness(executionCount: 7)
        try harness.directory.write(Self.source, to: "Sources/Demo/Other.swift")

        _ = harness.application.run(arguments: [])

        let testRuns = harness.executor.invocations.filter { $0.arguments.contains("--enable-code-coverage") }
        XCTAssertEqual(testRuns.count, 1)
        XCTAssertEqual(testRuns.first?.workingDirectory, harness.directory.path)
    }

    func testExplicitPathsLimitWhatIsScored() throws {
        let harness = try makeHarness(executionCount: 0)
        try harness.directory.write("struct Other { func plain() {} }", to: "Sources/Demo/Other.swift")

        _ = harness.application.run(arguments: ["Sources/Demo/Other.swift"])

        XCTAssertTrue(harness.output.contains("Other.plain()"))
        XCTAssertFalse(harness.output.contains("Demo.risky(_:)"))
    }

    func testChangedModeUsesGit() throws {
        let harness = try makeHarness(executionCount: 0)
        harness.executor.handler = { [directory = harness.directory] invocation in
            if invocation.command == "git" {
                return .success(" M Sources/Demo/Demo.swift\n")
            }
            if invocation.arguments.contains("--enable-code-coverage") {
                return .success()
            }
            return .success(directory.path(".build/debug/codecov/Missing.json") + "\n")
        }

        let status = harness.application.run(arguments: ["--changed"])

        XCTAssertEqual(status, ExitCode.success)
        XCTAssertTrue(harness.executor.invocations.contains { $0.command == "git" })
        // No usable export, so the method is reported without a score.
        XCTAssertTrue(harness.output.contains("N/A"))
        XCTAssertTrue(harness.errors.contains("no llvm-cov export found"))
    }

    func testFailingTestSuiteIsReportedAsAnError() throws {
        let harness = try makeHarness(executionCount: 0)
        harness.executor.handler = { _ in .failure(1, "1 test failed") }

        let status = harness.application.run(arguments: [])

        XCTAssertEqual(status, ExitCode.usageError)
        XCTAssertTrue(harness.errors.contains("coverage command failed"))
    }
}
