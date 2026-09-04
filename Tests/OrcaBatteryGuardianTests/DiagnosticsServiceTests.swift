import Foundation
import Testing
@testable import OrcaBatteryGuardian

@Test func diagnosticsReportsVersionDaemonLimitsAndNativeSupport() async {
    let runner = ScriptedRunner([
        CommandResult(exitCode: 0, output: "Client: v0.8.0\nDaemon: v0.8.0\n"),
        battJSON(lower: 50, upper: 80)
    ])
    let service = SystemDiagnosticsService(runner: runner, battPath: "/test/batt",
        operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0),
        applicationPath: "/Applications/OrcaBatteryGuardian.app")
    let checks = await service.run(snapshot: sampleBattery())
    #expect(checks.first(where: { $0.id == "native-limit" })?.level == .information)
    #expect(checks.first(where: { $0.id == "installation" })?.level == .passed)
    #expect(checks.first(where: { $0.id == "batt-version" })?.detail.contains("v0.8.0") == true)
    #expect(checks.first(where: { $0.id == "daemon" })?.level == .passed)
    #expect(checks.first(where: { $0.id == "limits" })?.detail.contains("50%") == true)
    #expect(await runner.calls.map(\.arguments) == [["version"], ["status", "--json"]])
}

@Test func diagnosticsMissingBackendNeverRunsACommand() async {
    let runner = ScriptedRunner([])
    let checks = await SystemDiagnosticsService(runner: runner, battPath: nil,
        applicationPath: "/tmp/OrcaBatteryGuardian").run(snapshot: sampleBattery(source: .unknown))
    #expect(checks.first(where: { $0.id == "battery" })?.level == .failed)
    #expect(checks.first(where: { $0.id == "batt" })?.level == .failed)
    #expect(checks.first(where: { $0.id == "installation" })?.level == .warning)
    #expect(await runner.calls.isEmpty)
}

@Test func intelDiagnosticsBlocksUnsupportedOSWithoutCommands() async {
    let runner = ScriptedRunner([])
    let checks = await SystemDiagnosticsService(
        runner: runner,
        battPath: nil,
        operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0),
        applicationPath: "/Applications/OrcaBatteryGuardian.app",
        architecture: .intel
    ).run(snapshot: sampleBattery())

    #expect(checks.first(where: { $0.id == "architecture" })?.level == .information)
    #expect(checks.first(where: { $0.id == "native-limit" })?.level == .passed)
    #expect(checks.first(where: { $0.id == "intel-controller" })?.level == .failed)
    #expect(await runner.calls.isEmpty)
}

@Test func intelDiagnosticsRequiresHelperOnSupportedOS() async {
    let runner = ScriptedRunner([])
    let checks = await SystemDiagnosticsService(
        runner: runner,
        battPath: nil,
        operatingSystemVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0),
        architecture: .intel,
        intelHelperPath: nil
    ).run(snapshot: sampleBattery())

    #expect(checks.first(where: { $0.id == "intel-controller" })?.level == .warning)
    #expect(await runner.calls.isEmpty)
}

@Test func intelDiagnosticsVerifiesBCLMReadback() async {
    let runner = ScriptedRunner([CommandResult(exitCode: 0, output: "77\n")])
    let checks = await SystemDiagnosticsService(
        runner: runner,
        battPath: nil,
        operatingSystemVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 7, patchVersion: 0),
        architecture: .intel,
        intelHelperPath: "/test/intel-helper"
    ).run(snapshot: sampleBattery())

    #expect(checks.first(where: { $0.id == "architecture" })?.level == .passed)
    #expect(checks.first(where: { $0.id == "intel-controller" })?.level == .passed)
    #expect(await runner.calls.first?.arguments == ["read"])
}

@Test(arguments: [
    CommandResult(exitCode: 124, timedOut: true),
    CommandResult(exitCode: 0, output: "invalid json"),
    battJSON(compatible: false),
    battJSON(phase: "ChargeToFull")
]) func diagnosticsSurfacesDaemonProblems(status: CommandResult) async {
    let runner = ScriptedRunner([CommandResult(exitCode: 0, output: "Client: test"), status])
    let checks = await SystemDiagnosticsService(runner: runner, battPath: "/test/batt").run(snapshot: sampleBattery())
    if status == battJSON(compatible: false) {
        #expect(checks.first(where: { $0.id == "daemon" })?.level == .failed)
    } else if status == battJSON(phase: "ChargeToFull") {
        #expect(checks.first(where: { $0.id == "calibration" })?.level == .warning)
    } else {
        #expect(checks.first(where: { $0.id == "daemon" })?.level == .failed)
    }
}

@Test @MainActor func temporaryFullChargeSettingPersistsAcrossRelaunch() throws {
    let suite = "OrcaFullChargeTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let now = Date(timeIntervalSince1970: 10_000)
    let first = GuardianSettings(defaults: defaults)
    first.beginTemporaryFullCharge(duration: .twoHours, now: now)
    let second = GuardianSettings(defaults: defaults)
    #expect(second.chargeToFullUntil == now.addingTimeInterval(7_200))
    second.endTemporaryFullCharge()
    #expect(defaults.object(forKey: "guardian.chargeToFullUntil") == nil)
}
