import Foundation
import Testing
@testable import OrcaBatteryGuardian

@Test func calibrationStatusRequiresVerifiedCapability() async {
    let runner = ScriptedRunner([calibrationJSON(phase: "Idle")])
    let status = await BattMaintenanceService(runner: runner, battPath: "/test/batt").calibrationStatus()

    #expect(status.isAvailable)
    #expect(!status.isRunning)
    #expect(await runner.calls.map(\.arguments) == [["status", "--json"]])
}

@Test func startingCalibrationReadsBackResultingState() async {
    let runner = ScriptedRunner([
        calibrationJSON(phase: "Idle"),
        CommandResult(exitCode: 0, output: "Calibration started"),
        calibrationJSON(phase: "Discharge", canPause: true, canCancel: true)
    ])
    let service = BattMaintenanceService(runner: runner, battPath: "/test/batt")
    let result = await service.performCalibration(.start)

    #expect(result.succeeded)
    #expect(result.calibration.phase == "Discharge")
    #expect(result.calibration.canCancel)
    #expect(await runner.calls.map(\.arguments) == [
        ["status", "--json"], ["calibration", "start"], ["status", "--json"]
    ])
}

@Test func invalidCalibrationTransitionDoesNotRunWriteCommand() async {
    let runner = ScriptedRunner([calibrationJSON(phase: "Idle")])
    let result = await BattMaintenanceService(runner: runner, battPath: "/test/batt")
        .performCalibration(.cancel)

    #expect(!result.succeeded)
    #expect(await runner.calls.count == 1)
}

@Test func calibrationCommandRequiresMatchingReadback() async {
    let runner = ScriptedRunner([
        calibrationJSON(phase: "Idle"),
        CommandResult(exitCode: 0),
        calibrationJSON(phase: "Idle")
    ])
    let result = await BattMaintenanceService(runner: runner, battPath: "/test/batt")
        .performCalibration(.start)

    #expect(!result.succeeded)
    #expect(result.message.contains("did not confirm"))
}

private func calibrationJSON(
    phase: String, paused: Bool = false, canPause: Bool = false, canCancel: Bool = false
) -> CommandResult {
    CommandResult(exitCode: 0, output: """
    {"configuration":{"enabled":true,"upperLimitPercent":80,"lowerLimitPercent":50},
     "compatibility":{"chargingControl":true,"calibration":true},
     "calibration":{"phase":"\(phase)","paused":\(paused),"canPause":\(canPause),"canCancel":\(canCancel),"message":""}}
    """)
}
