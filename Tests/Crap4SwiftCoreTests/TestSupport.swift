import Foundation
import XCTest

@testable import Crap4SwiftCore

/// Records what the tool would have shelled out to, and replays canned results.
final class FakeCommandExecutor: CommandExecutor {
    struct Invocation: Equatable {
        let command: String
        let arguments: [String]
        let workingDirectory: String
    }

    private(set) var invocations: [Invocation] = []
    var handler: (Invocation) throws -> CommandResult

    init(handler: @escaping (Invocation) throws -> CommandResult = { _ in .empty }) {
        self.handler = handler
    }

    func execute(_ command: String, arguments: [String], workingDirectory: String) throws -> CommandResult {
        let invocation = Invocation(command: command, arguments: arguments, workingDirectory: workingDirectory)
        invocations.append(invocation)
        return try handler(invocation)
    }
}

extension CommandResult {
    static let empty = CommandResult(exitCode: 0, standardOutput: "", standardError: "")

    static func success(_ standardOutput: String = "") -> CommandResult {
        CommandResult(exitCode: 0, standardOutput: standardOutput, standardError: "")
    }

    static func failure(_ exitCode: Int32 = 1, _ standardError: String = "boom") -> CommandResult {
        CommandResult(exitCode: exitCode, standardOutput: "", standardError: standardError)
    }
}

/// A scratch directory removed when the test finishes.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        let candidate = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("crap4swift-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        // Normalized the same way the tool normalizes discovered paths, so
        // expected and actual paths are directly comparable.
        url = URL(fileURLWithPath: SourceFileFinder.normalized(candidate.path))
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var path: String { url.path }

    @discardableResult
    func write(_ contents: String, to relativePath: String) throws -> String {
        let destination = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: destination)
        return destination.path
    }

    @discardableResult
    func makeDirectory(_ relativePath: String) throws -> String {
        let destination = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return destination.path
    }

    func path(_ relativePath: String) -> String {
        url.appendingPathComponent(relativePath).path
    }
}

/// Collects everything the CLI writes, so assertions can look at output.
final class OutputRecorder {
    private(set) var lines: [String] = []

    func write(_ line: String) {
        lines.append(line)
    }

    var text: String { lines.joined(separator: "\n") }

    func contains(_ needle: String) -> Bool { text.contains(needle) }
}

func descriptor(
    typeName: String = "T",
    methodName: String = "m()",
    filePath: String = "/tmp/T.swift",
    declarationLine: Int = 1,
    bodyStartLine: Int = 1,
    bodyEndLine: Int = 5,
    complexity: Int = 1
) -> MethodDescriptor {
    MethodDescriptor(
        typeName: typeName,
        methodName: methodName,
        filePath: filePath,
        declarationLine: declarationLine,
        bodyStartLine: bodyStartLine,
        bodyEndLine: bodyEndLine,
        complexity: complexity
    )
}
