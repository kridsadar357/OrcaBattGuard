import Foundation
import Testing
@testable import OrcaBatteryGuardian

@Test func runnerCapturesOutputAndExitCodes() async {
    let runner = ProcessCommandRunner()
    let success = await runner.run(executable: "/bin/echo", arguments: ["orca test"], timeout: 2)
    #expect(success.succeeded && success.output == "orca test\n")
    let failure = await runner.run(executable: "/usr/bin/false", arguments: [], timeout: 2)
    #expect(failure.exitCode != 0 && !failure.succeeded)
    let missing = await runner.run(executable: "/nonexistent/orca-test", arguments: [], timeout: 2)
    #expect(missing.exitCode == 127)
}

@Test func unresponsiveProcessTimesOut() async {
    let start = ContinuousClock.now
    let result = await ProcessCommandRunner().run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.15)
    #expect(result.timedOut && !result.succeeded)
    #expect(start.duration(to: .now) < .seconds(3))
}

@Test func cancellationTerminatesProcessPromptly() async throws {
    let task = Task { await ProcessCommandRunner().run(executable: "/bin/sleep", arguments: ["10"], timeout: 20) }
    try await Task.sleep(for: .milliseconds(100))
    let start = ContinuousClock.now
    task.cancel()
    let result = await task.value
    #expect(result.cancelled && !result.succeeded)
    #expect(start.duration(to: .now) < .seconds(3))
}

@Test func processIgnoringTerminationIsKilled() async {
    let start = ContinuousClock.now
    let result = await ProcessCommandRunner().run(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.1)
    #expect(result.timedOut)
    #expect(start.duration(to: .now) < .seconds(3))
}

@Test func continuousOutputIsBoundedAndStillTimesOut() async {
    let result = await ProcessCommandRunner().run(executable: "/usr/bin/yes", arguments: ["bounded output"], timeout: 0.2)
    #expect(result.timedOut && result.outputTruncated)
    #expect(result.output.utf8.count <= 65_536)
}

@Test @MainActor func waitingForCommandDoesNotBlockMainActor() async throws {
    var heartbeat = false
    let task = Task { await ProcessCommandRunner().run(executable: "/bin/sleep", arguments: ["10"], timeout: 1) }
    let start = ContinuousClock.now
    try await Task.sleep(for: .milliseconds(50))
    heartbeat = true
    #expect(heartbeat && start.duration(to: .now) < .milliseconds(800))
    task.cancel()
    #expect(await task.value.cancelled)
}
