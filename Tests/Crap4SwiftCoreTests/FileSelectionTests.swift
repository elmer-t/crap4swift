import XCTest

@testable import Crap4SwiftCore

final class SourceFileFinderTests: XCTestCase {
    private func makeProject() throws -> TemporaryDirectory {
        let directory = try TemporaryDirectory()
        try directory.write("// swift-tools-version:5.9", to: "Package.swift")
        try directory.write("struct A {}", to: "Sources/Lib/A.swift")
        try directory.write("struct B {}", to: "Sources/Lib/Nested/B.swift")
        try directory.write("struct T {}", to: "Tests/LibTests/ATests.swift")
        try directory.write("# readme", to: "Sources/Lib/README.md")
        return directory
    }

    func testOnlySwiftFilesUnderSourcesAreFound() throws {
        let directory = try makeProject()

        let found = SourceFileFinder().allSourceFiles(projectRoot: directory.path)

        XCTAssertEqual(found, [
            directory.path("Sources/Lib/A.swift"),
            directory.path("Sources/Lib/Nested/B.swift"),
        ])
    }

    func testVendoredDirectoriesAreNotDescendedInto() throws {
        let directory = try makeProject()
        try directory.write("struct Vendored {}", to: "Sources/Lib/Pods/Vendored.swift")

        let found = SourceFileFinder().allSourceFiles(projectRoot: directory.path)

        XCTAssertEqual(found, [
            directory.path("Sources/Lib/A.swift"),
            directory.path("Sources/Lib/Nested/B.swift"),
        ])
    }

    func testMissingSourcesDirectoryYieldsNothing() throws {
        let directory = try TemporaryDirectory()
        XCTAssertEqual(SourceFileFinder().allSourceFiles(projectRoot: directory.path), [])
    }

    func testExplicitFileIsAnalyzedDirectly() throws {
        let directory = try makeProject()

        let found = SourceFileFinder().expand(paths: ["Sources/Lib/A.swift"], projectRoot: directory.path)

        XCTAssertEqual(found, [directory.path("Sources/Lib/A.swift")])
    }

    func testExplicitDirectoryExpandsToItsSourcesSubtree() throws {
        let directory = try makeProject()

        let found = SourceFileFinder().expand(paths: [directory.path], projectRoot: directory.path)

        XCTAssertEqual(found, [
            directory.path("Sources/Lib/A.swift"),
            directory.path("Sources/Lib/Nested/B.swift"),
        ])
    }

    func testResultsAreDeduplicatedSortedAndFilteredForExistence() throws {
        let directory = try makeProject()

        let found = SourceFileFinder().expand(
            paths: [
                "Sources/Lib/Nested/B.swift",
                "Sources/Lib/A.swift",
                "Sources/Lib/A.swift",
                "Sources/Lib/README.md",
                "Sources/Lib/Missing.swift",
            ],
            projectRoot: directory.path
        )

        XCTAssertEqual(found, [
            directory.path("Sources/Lib/A.swift"),
            directory.path("Sources/Lib/Nested/B.swift"),
        ])
    }

    func testDisplayPathIsRelativeToTheProjectRoot() {
        XCTAssertEqual(
            SourceFileFinder.displayPath("/proj/Sources/Lib/A.swift", relativeTo: "/proj"),
            "Sources/Lib/A.swift"
        )
        XCTAssertEqual(
            SourceFileFinder.displayPath("/elsewhere/A.swift", relativeTo: "/proj"),
            "/elsewhere/A.swift"
        )
    }
}

final class PackageRootFinderTests: XCTestCase {
    private func makeWorkspace() throws -> TemporaryDirectory {
        let directory = try TemporaryDirectory()
        try directory.write("// root", to: "Package.swift")
        try directory.write("struct A {}", to: "Sources/App/A.swift")
        try directory.write("// nested", to: "Packages/Lib/Package.swift")
        try directory.write("struct B {}", to: "Packages/Lib/Sources/Lib/B.swift")
        return directory
    }

    func testNearestManifestWins() throws {
        let directory = try makeWorkspace()
        let finder = PackageRootFinder()

        XCTAssertEqual(
            finder.packageRoot(for: directory.path("Sources/App/A.swift"), projectRoot: directory.path),
            directory.path
        )
        XCTAssertEqual(
            finder.packageRoot(for: directory.path("Packages/Lib/Sources/Lib/B.swift"), projectRoot: directory.path),
            directory.path("Packages/Lib")
        )
    }

    func testProjectRootIsUsedWhenNoManifestIsFound() throws {
        let directory = try TemporaryDirectory()
        try directory.write("struct A {}", to: "Sources/App/A.swift")

        let root = PackageRootFinder().packageRoot(
            for: directory.path("Sources/App/A.swift"),
            projectRoot: directory.path
        )

        XCTAssertEqual(root, directory.path)
    }

    func testFilesAreGroupedByOwningPackage() throws {
        let directory = try makeWorkspace()

        let groups = PackageRootFinder().group(
            files: [
                directory.path("Packages/Lib/Sources/Lib/B.swift"),
                directory.path("Sources/App/A.swift"),
            ],
            projectRoot: directory.path
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.packageRoot), [directory.path, directory.path("Packages/Lib")].sorted())
    }
}

final class ChangedFileDetectorTests: XCTestCase {
    func testPorcelainLinesAreReducedToPaths() {
        XCTAssertEqual(ChangedFileDetector.path(fromPorcelainLine: " M Sources/A.swift"), "Sources/A.swift")
        XCTAssertEqual(ChangedFileDetector.path(fromPorcelainLine: "A  Sources/B.swift"), "Sources/B.swift")
        XCTAssertEqual(ChangedFileDetector.path(fromPorcelainLine: "?? Sources/C.swift"), "Sources/C.swift")
        XCTAssertEqual(ChangedFileDetector.path(fromPorcelainLine: "MM Sources/D.swift"), "Sources/D.swift")
    }

    func testRenamesResolveToTheNewPath() {
        XCTAssertEqual(
            ChangedFileDetector.path(fromPorcelainLine: "R  Sources/Old.swift -> Sources/New.swift"),
            "Sources/New.swift"
        )
    }

    func testDeletionsAreDropped() {
        XCTAssertNil(ChangedFileDetector.path(fromPorcelainLine: " D Sources/Gone.swift"))
        XCTAssertNil(ChangedFileDetector.path(fromPorcelainLine: "D  Sources/Gone.swift"))
    }

    func testQuotedPathsAreUnquoted() {
        XCTAssertEqual(
            ChangedFileDetector.path(fromPorcelainLine: " M \"Sources/With Space.swift\""),
            "Sources/With Space.swift"
        )
    }

    func testOnlyExistingSwiftFilesUnderSourcesSurvive() throws {
        let directory = try TemporaryDirectory()
        try directory.write("struct A {}", to: "Sources/Lib/A.swift")
        try directory.write("struct T {}", to: "Tests/LibTests/ATests.swift")
        try directory.write("# doc", to: "Sources/Lib/README.md")

        let porcelain = """
         M Sources/Lib/A.swift
         M Sources/Lib/README.md
         M Tests/LibTests/ATests.swift
         M Sources/Lib/Deleted.swift
        ?? Package.swift
        """

        let detected = ChangedFileDetector(executor: FakeCommandExecutor())
            .filter(porcelain: porcelain, projectRoot: directory.path)

        XCTAssertEqual(detected, [directory.path("Sources/Lib/A.swift")])
    }

    func testGitIsInvokedInTheProjectRoot() throws {
        let directory = try TemporaryDirectory()
        let executor = FakeCommandExecutor { _ in .success("") }

        _ = try ChangedFileDetector(executor: executor).changedSourceFiles(projectRoot: directory.path)

        XCTAssertEqual(executor.invocations, [
            FakeCommandExecutor.Invocation(
                command: "git",
                arguments: ["status", "--porcelain"],
                workingDirectory: directory.path
            ),
        ])
    }

    func testFailingGitIsReported() throws {
        let directory = try TemporaryDirectory()
        let executor = FakeCommandExecutor { _ in .failure(128, "not a git repository") }

        XCTAssertThrowsError(
            try ChangedFileDetector(executor: executor).changedSourceFiles(projectRoot: directory.path)
        )
    }
}
