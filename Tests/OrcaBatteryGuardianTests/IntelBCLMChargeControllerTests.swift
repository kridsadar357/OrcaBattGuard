import Foundation
import Testing
@testable import OrcaBatteryGuardian

private func applyIntel(
    _ controller: IntelBCLMChargeController,
    limits: ChargeThresholds = testLimits,
    enabled: Bool = true
) async -> ChargeControlResult {
    let battery = sampleBattery()
    let decision = GuardianStateMachine().decide(
        snapshot: battery,
        thresholds: limits,
        protectionEnabled: enabled
    )
    return await controller.apply(
        decision: decision,
        snapshot: battery,
        thresholds: limits,
        protectionEnabled: enabled
    )
}

private func intelController(
    runner: any CommandRunning,
    version: OperatingSystemVersion = OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0)
) -> IntelBCLMChargeController {
    IntelBCLMChargeController(
        runner: runner,
        helperPath: "/bin/echo",
        operatingSystemVersion: version,
        architecture: .intel
    )
}

private actor NamedChargeController: ChargeControlling {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    func apply(
        decision: GuardianDecision,
        snapshot: BatterySnapshot,
        thresholds: ChargeThresholds,
        protectionEnabled: Bool
    ) async -> ChargeControlResult {
        ChargeControlResult(
            backendName: name,
            isHardwareControlAvailable: true,
            didAttemptHardwareChange: false,
            message: name
        )
    }
}

private func applyPlatform(_ architecture: MacArchitecture) async -> ChargeControlResult {
    let battery = sampleBattery()
    let decision = GuardianStateMachine().decide(
        snapshot: battery,
        thresholds: testLimits,
        protectionEnabled: true
    )
    let controller = PlatformChargeController(
        architecture: architecture,
        appleSiliconController: NamedChargeController("batt-route"),
        intelController: NamedChargeController("bclm-route")
    )
    return await controller.apply(
        decision: decision,
        snapshot: battery,
        thresholds: testLimits,
        protectionEnabled: true
    )
}

@Test func platformControllerRoutesAppleSiliconToBatt() async {
    #expect(await applyPlatform(.appleSilicon).backendName == "batt-route")
}

@Test func platformControllerRoutesIntelToBCLM() async {
    #expect(await applyPlatform(.intel).backendName == "bclm-route")
}

@Test func matchingIntelLimitIsVerifiedWithoutWrite() async {
    let runner = ScriptedRunner([CommandResult(exitCode: 0, output: "80\n")])
    let result = await applyIntel(intelController(runner: runner))

    #expect(result.backendName == "BCLM")
    #expect(result.verifiedAt != nil)
    #expect(result.upperLimit == 80 && result.lowerLimit == nil)
    #expect(!result.didAttemptHardwareChange)
    #expect(await runner.calls.map(\.arguments) == [["read"]])
}

@Test func intelLimitWriteRequiresMatchingReadback() async {
    let runner = ScriptedRunner([
        CommandResult(exitCode: 0, output: "90"),
        CommandResult(exitCode: 0),
        CommandResult(exitCode: 0, output: "80")
    ])
    let result = await applyIntel(intelController(runner: runner))
    let calls = await runner.calls

    #expect(result.verifiedAt != nil && result.didAttemptHardwareChange)
    #expect(calls.map(\.executable) == ["/bin/echo", "/usr/bin/sudo", "/bin/echo"])
    #expect(calls[1].arguments == ["-n", "/bin/echo", "write", "80"])
}

@Test func intelMismatchedReadbackIsUnverified() async {
    let runner = ScriptedRunner([
        CommandResult(exitCode: 0, output: "90"),
        CommandResult(exitCode: 0),
        CommandResult(exitCode: 0, output: "90")
    ])
    let result = await applyIntel(intelController(runner: runner))

    #expect(result.verifiedAt == nil)
    #expect(result.didAttemptHardwareChange)
    #expect(!result.isHardwareControlAvailable)
}

@Test func invalidIntelReadbackNeverWrites() async {
    let runner = ScriptedRunner([CommandResult(exitCode: 0, output: "not-a-limit")])
    let result = await applyIntel(intelController(runner: runner))

    #expect(result.verifiedAt == nil && !result.didAttemptHardwareChange)
    #expect(await runner.calls.count == 1)
}

@Test func intelControlIsBlockedOnMacOS15AndNewer() async {
    let runner = ScriptedRunner([])
    let controller = intelController(
        runner: runner,
        version: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
    )
    let result = await applyIntel(controller)

    #expect(result.verifiedAt == nil)
    #expect(result.message.contains("SIP"))
    #expect(await runner.calls.isEmpty)
}

@Test func disablingIntelProtectionRestoresBCLMTo100() async {
    let runner = ScriptedRunner([
        CommandResult(exitCode: 0, output: "80"),
        CommandResult(exitCode: 0),
        CommandResult(exitCode: 0, output: "100")
    ])
    let result = await applyIntel(intelController(runner: runner), enabled: false)

    #expect(result.verifiedAt != nil)
    #expect(result.isLimitEnabled == false)
    #expect(result.upperLimit == 100)
}
