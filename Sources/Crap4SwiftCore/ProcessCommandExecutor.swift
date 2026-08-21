import Dispatch
import Foundation

public struct ProcessCommandExecutor: CommandExecutor {
    public init() {}

    public func execute(
        _ command: String,
        arguments: [String],
        workingDirectory: String
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw Crap4SwiftError.commandLaunchFailed(command: command, reason: "\(error)")
        }

        // Both pipes have to be drained concurrently: reading one to the end
        // first deadlocks as soon as the child fills the other pipe's buffer.
        let errorData = DataBox()
        let queue = DispatchQueue(label: "crap4swift.process.stderr")
        let group = DispatchGroup()
        queue.async(group: group) { errorData.value = errorPipe.fileHandleForReading.readDataToEndOfFile() }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData.value, as: UTF8.self)
        )
    }
}

/// Somewhere for the background reader to put its result that is safe to hand
/// across threads.
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
