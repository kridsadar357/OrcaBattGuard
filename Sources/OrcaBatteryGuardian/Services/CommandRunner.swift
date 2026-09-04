import Darwin
import Foundation

public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String
    public var timedOut: Bool
    public var cancelled: Bool
    public var outputTruncated: Bool

    public init(
        exitCode: Int32, output: String = "", timedOut: Bool = false,
        cancelled: Bool = false, outputTruncated: Bool = false
    ) {
        self.exitCode = exitCode
        self.output = output
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.outputTruncated = outputTruncated
    }

    public var succeeded: Bool {
        exitCode == 0 && !timedOut && !cancelled && !outputTruncated
    }
}

public protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        let cancellation = CommandCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Self.execute(
                        executable: executable, arguments: arguments,
                        timeout: timeout, cancellation: cancellation
                    ))
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func execute(
        executable: String, arguments: [String], timeout: TimeInterval,
        cancellation: CommandCancellation
    ) -> CommandResult {
        guard !cancellation.isCancelled else {
            return CommandResult(exitCode: 130, cancelled: true)
        }
        guard timeout.isFinite, timeout > 0 else {
            return CommandResult(exitCode: 124, timedOut: true)
        }

        let process = Process()
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        let writer = pipe.fileHandleForWriting
        defer {
            try? reader.close()
            try? writer.close()
        }
        let descriptor = reader.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            return CommandResult(exitCode: 127, output: "Cannot configure command output capture.")
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = writer
        process.standardError = writer
        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: 127, output: error.localizedDescription)
        }
        try? writer.close()

        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data()
        var truncated = false
        var timedOut = false
        var cancelled = false
        var terminationDeadline: TimeInterval?

        // Drain a nonblocking pipe even after the capture limit, so a verbose child
        // cannot deadlock. A child inheriting stdout cannot keep the reader waiting.
        while process.isRunning {
            drain(descriptor, into: &output, truncated: &truncated)
            let now = ProcessInfo.processInfo.systemUptime
            if terminationDeadline == nil, cancellation.isCancelled || now >= deadline {
                cancelled = cancellation.isCancelled
                timedOut = !cancelled
                process.terminate()
                terminationDeadline = now + 0.15
            }
            if let terminationDeadline, now >= terminationDeadline, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        drain(descriptor, into: &output, truncated: &truncated)

        return CommandResult(
            exitCode: cancelled ? 130 : (timedOut ? 124 : process.terminationStatus),
            output: String(decoding: output, as: UTF8.self),
            timedOut: timedOut, cancelled: cancelled, outputTruncated: truncated
        )
    }

    private static func drain(_ descriptor: Int32, into output: inout Data, truncated: inout Bool) {
        let captureLimit = 65_536
        var buffer = [UInt8](repeating: 0, count: 8_192)
        // Bound each drain pass so continuously writing processes still time out.
        for _ in 0..<32 {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            let retained = min(count, max(0, captureLimit - output.count))
            output.append(contentsOf: buffer.prefix(retained))
            if retained < count { truncated = true }
        }
    }
}

// Only the cancellation bit crosses between Swift tasks and the process worker.
private final class CommandCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
