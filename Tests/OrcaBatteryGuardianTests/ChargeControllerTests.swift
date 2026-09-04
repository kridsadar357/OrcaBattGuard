import Foundation
import Testing
@testable import OrcaBatteryGuardian

private func apply(_ controller: SystemChargeController, battery: BatterySnapshot = sampleBattery(), limits: ChargeThresholds = testLimits, enabled: Bool = true) async -> ChargeControlResult {
    let decision = GuardianStateMachine().decide(snapshot: battery, thresholds: limits, protectionEnabled: enabled)
    return await controller.apply(decision: decision, snapshot: battery, thresholds: limits, protectionEnabled: enabled)
}

@Test func matchingLimitsAreReadEveryTimeWithoutWrites() async {
    let runner = ScriptedRunner([battJSON(), battJSON()])
    let controller = SystemChargeController(runner: runner, battPath: "/test/batt")
    let first = await apply(controller)
    let second = await apply(controller)
    #expect(first.verifiedAt != nil && second.verifiedAt != nil)
    #expect(!first.didAttemptHardwareChange && !second.didAttemptHardwareChange)
    #expect(await runner.calls.map(\.arguments) == [["status", "--json"], ["status", "--json"]])
}

@Test func failedWriteIsNeverCachedAndNextRefreshRetries() async {
    let runner = ScriptedRunner([
        battJSON(upper: 90), CommandResult(exitCode: 1),
        battJSON(upper: 90), CommandResult(exitCode: 0), CommandResult(exitCode: 0), battJSON()
    ])
    let controller = SystemChargeController(runner: runner, battPath: "/test/batt")
    let failed = await apply(controller)
    #expect(!failed.isHardwareControlAvailable && failed.verifiedAt == nil)
    #expect(failed.didAttemptHardwareChange)
    let retried = await apply(controller)
    #expect(retried.verifiedAt != nil && retried.didAttemptHardwareChange)
    #expect(await runner.calls.map(\.arguments) == [
        ["status", "--json"], ["lower-limit-delta", "30"],
        ["status", "--json"], ["lower-limit-delta", "30"], ["limit", "80"], ["status", "--json"]
    ])
}

@Test func secondWriteFailureDoesNotConfirmPartialConfiguration() async {
    let runner = ScriptedRunner([battJSON(upper: 90), CommandResult(exitCode: 0), CommandResult(exitCode: 2)])
    let result = await apply(SystemChargeController(runner: runner, battPath: "/test/batt"))
    #expect(result.verifiedAt == nil && result.didAttemptHardwareChange)
    #expect(await runner.calls.count == 3)
}

@Test func stoppedDaemonInvalidatesPreviouslyVerifiedStatus() async {
    let runner = ScriptedRunner([battJSON(), CommandResult(exitCode: 1)])
    let controller = SystemChargeController(runner: runner, battPath: "/test/batt")
    #expect(await apply(controller).isHardwareControlAvailable)
    let result = await apply(controller)
    #expect(!result.isHardwareControlAvailable && result.verifiedAt == nil)
    #expect(!result.didAttemptHardwareChange)
}

@Test func externalConfigurationDriftIsRepairedAndReadBack() async {
    let runner = ScriptedRunner([battJSON(), battJSON(lower: 60, upper: 90), CommandResult(exitCode: 0), CommandResult(exitCode: 0), battJSON()])
    let controller = SystemChargeController(runner: runner, battPath: "/test/batt")
    _ = await apply(controller)
    let result = await apply(controller)
    #expect(result.didAttemptHardwareChange && result.verifiedAt != nil)
    #expect(result.lowerLimit == 50 && result.upperLimit == 80)
}

@Test func successfulCommandWithoutMatchingReadbackIsUnverified() async {
    let runner = ScriptedRunner([battJSON(upper: 90), CommandResult(exitCode: 0), CommandResult(exitCode: 0), battJSON(upper: 90)])
    let result = await apply(SystemChargeController(runner: runner, battPath: "/test/batt"))
    #expect(result.verifiedAt == nil && !result.isHardwareControlAvailable)
}

@Test(arguments: [
    CommandResult(exitCode: 0, output: "not json"),
    CommandResult(exitCode: 0, output: "{}"),
    CommandResult(exitCode: 124, timedOut: true),
    CommandResult(exitCode: 0, outputTruncated: true),
    battJSON(lower: 90, upper: 80), battJSON(compatible: false), battJSON(phase: "Charging")
]) func invalidOrUnavailableBackendNeverWrites(response: CommandResult) async {
    let runner = ScriptedRunner([response])
    let result = await apply(SystemChargeController(runner: runner, battPath: "/test/batt", commandTimeout: 0.5))
    #expect(result.verifiedAt == nil && !result.didAttemptHardwareChange)
    #expect(await runner.calls.count == 1)
    #expect(await runner.calls.first?.timeout == 0.5)
}

@Test func postWriteDaemonFailureIsUnverified() async {
    let runner = ScriptedRunner([battJSON(upper: 90), CommandResult(exitCode: 0), CommandResult(exitCode: 0), CommandResult(exitCode: 124, timedOut: true)])
    let result = await apply(SystemChargeController(runner: runner, battPath: "/test/batt"))
    #expect(result.verifiedAt == nil && result.didAttemptHardwareChange)
}

@Test(arguments: [true, false]) func travelAndProtectionOffVerifyDisabledLimit(travel: Bool) async {
    let runner = ScriptedRunner([battJSON(), CommandResult(exitCode: 0), battJSON(enabled: false)])
    let result = await apply(SystemChargeController(runner: runner, battPath: "/test/batt"), limits: travel ? GuardianMode.travel.thresholds : testLimits, enabled: travel)
    #expect(result.verifiedAt != nil && result.isLimitEnabled == false)
    #expect(await runner.calls.map(\.arguments) == [["status", "--json"], ["disable"], ["status", "--json"]])
}

@Test func coolingLimitIsVerifiedThenNormalRangeRestored() async {
    let runner = ScriptedRunner([
        battJSON(), CommandResult(exitCode: 0), CommandResult(exitCode: 0), battJSON(upper: 65),
        battJSON(upper: 65), CommandResult(exitCode: 0), CommandResult(exitCode: 0), battJSON()
    ])
    let controller = SystemChargeController(runner: runner, battPath: "/test/batt")
    let hot = await apply(controller, battery: sampleBattery(65, temperature: 40))
    #expect(hot.upperLimit == 65 && hot.verifiedAt != nil)
    let cooled = await apply(controller)
    #expect(cooled.upperLimit == 80 && cooled.verifiedAt != nil)
    let arguments = await runner.calls.map(\.arguments)
    #expect(arguments.contains(["lower-limit-delta", "15"]))
    #expect(arguments.contains(["lower-limit-delta", "30"]))
    #expect(!arguments.contains(where: { $0.contains("adapter") || $0.contains("discharge") }))
}

@Test func unknownBatteryDoesNotEvenInvokeBackend() async {
    let runner = ScriptedRunner([])
    let result = await apply(SystemChargeController(runner: runner, battPath: "/test/batt"), battery: sampleBattery(0, source: .unknown))
    #expect(!result.isHardwareControlAvailable)
    #expect(await runner.calls.isEmpty)
}

@Test func missingBackendUsesReadOnlyFallback() async {
    let runner = ScriptedRunner([CommandResult(exitCode: 0)])
    let result = await apply(SystemChargeController(runner: runner, battPath: nil))
    #expect(result.backendName == "Monitor Only" && result.verifiedAt == nil)
    #expect(await runner.calls.first?.executable == "/usr/bin/pmset")
    #expect(await runner.calls.first?.arguments == ["-g", "battlimit"])
}

private actor GatedCommandRunner: CommandRunning {
    let blockedCall: Int
    private(set) var calls = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(blockedCall: Int) { self.blockedCall = blockedCall }

    func run(executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        calls += 1
        let index = calls
        if index == blockedCall {
            await withCheckedContinuation { continuation in
                gate = continuation
                waiters.forEach { $0.resume() }
                waiters.removeAll()
            }
        }
        if index > blockedCall { Issue.record("A cancelled update issued another command") }
        return index == 1 ? battJSON(upper: 90) : CommandResult(exitCode: 0)
    }

    func waitUntilBlocked() async {
        if gate != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() { gate?.resume(); gate = nil }
}

@Test(arguments: [1, 2]) func cancellingControllerPreventsSubsequentWrites(blockedCall: Int) async {
    let runner = GatedCommandRunner(blockedCall: blockedCall)
    let controller = SystemChargeController(runner: runner, battPath: "/test/batt")
    let task = Task { await apply(controller) }
    await runner.waitUntilBlocked()
    let concurrent = await apply(controller)
    #expect(concurrent.verifiedAt == nil && !concurrent.didAttemptHardwareChange)
    task.cancel()
    await runner.release()
    let cancelled = await task.value
    #expect(cancelled.verifiedAt == nil && !cancelled.isHardwareControlAvailable)
    #expect(await runner.calls == blockedCall)
}
