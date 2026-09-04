import Foundation
import Testing
@testable import OrcaBatteryGuardian

let testLimits = ChargeThresholds(lower: 50, upper: 80)

func sampleBattery(_ percent: Int = 65, source: PowerSource = .acPower, charging: Bool = false, temperature: Double = 30) -> BatterySnapshot {
    BatterySnapshot(percentage: percent, powerSource: source, isCharging: charging,
        isFullyCharged: percent == 100, temperatureC: temperature, cycleCount: 100, health: "Good",
        fullChargeCapacityMah: 8_000, designCapacityMah: 8_500)
}

func battJSON(lower: Int = 50, upper: Int = 80, enabled: Bool = true, compatible: Bool = true, phase: String = "Idle") -> CommandResult {
    CommandResult(exitCode: 0, output: """
    {"configuration":{"enabled":\(enabled),"upperLimitPercent":\(upper),"lowerLimitPercent":\(lower)},
     "compatibility":{"chargingControl":\(compatible)},"calibration":{"phase":"\(phase)"}}
    """)
}

actor ScriptedRunner: CommandRunning {
    struct Call: Equatable, Sendable {
        let executable: String
        let arguments: [String]
        let timeout: TimeInterval
    }
    private var results: [CommandResult]
    private(set) var calls: [Call] = []

    init(_ results: [CommandResult]) { self.results = results }

    func run(executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments, timeout: timeout))
        guard !results.isEmpty else {
            Issue.record("Unexpected command: \(arguments)")
            return CommandResult(exitCode: 99)
        }
        return results.removeFirst()
    }
}

struct FixedBatteryProvider: BatteryDataProviding {
    let value: BatterySnapshot
    func currentSnapshot() -> BatterySnapshot { value }
}

final class SilentNotifier: GuardianNotifying {
    func requestAuthorization() {}
    func notify(title: String, body: String) {}
}

actor MemoryHistory: StatusHistoryStoring {
    var events: [StatusEvent]
    let failLoad: Bool
    let failSave: Bool
    private(set) var saves = 0
    init(events: [StatusEvent] = [], failLoad: Bool = false, failSave: Bool = false) {
        self.events = events
        self.failLoad = failLoad
        self.failSave = failSave
    }
    func load() throws -> [StatusEvent] {
        if failLoad { throw CocoaError(.fileReadCorruptFile) }
        return events
    }
    func save(_ events: [StatusEvent]) throws -> [StatusEvent] {
        saves += 1
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        self.events = events
        return events
    }
}

@MainActor
final class TestPowerSourceMonitor: PowerSourceEventMonitoring {
    private var handler: (@MainActor @Sendable () -> Void)?
    private(set) var startCalls = 0
    private(set) var stopCalls = 0

    func start(handler: @escaping @MainActor @Sendable () -> Void) {
        startCalls += 1
        self.handler = handler
    }

    func stop() {
        stopCalls += 1
        handler = nil
    }

    func trigger() { handler?() }
}

actor FixedDiagnosticsProvider: DiagnosticsProviding {
    let checks: [DiagnosticCheck]
    private(set) var calls = 0
    init(checks: [DiagnosticCheck]) { self.checks = checks }
    func run(snapshot: BatterySnapshot, language: AppLanguage) -> [DiagnosticCheck] {
        calls += 1
        return checks
    }
}

actor MemoryBenchmarkStore: BatteryBenchmarkStoring {
    private(set) var observations: [BatteryBenchmarkObservation] = []
    private(set) var flushes = 0
    private var currentReport: BatteryBenchmarkReport?

    func record(_ observation: BatteryBenchmarkObservation) -> BatteryBenchmarkReport {
        observations.append(observation)
        let report = makeReport(observation)
        currentReport = report
        return report
    }

    func reset(with observation: BatteryBenchmarkObservation) -> BatteryBenchmarkReport {
        observations = [observation]
        let report = makeReport(observation)
        currentReport = report
        return report
    }

    func flush(at date: Date) {
        flushes += 1
    }

    private func makeReport(_ observation: BatteryBenchmarkObservation) -> BatteryBenchmarkReport {
        let baseline = currentReport?.baseline ?? BatteryBenchmarkBaseline(
            date: observation.timestamp,
            cycleCount: observation.cycleCount,
            fullChargeCapacityMah: observation.fullChargeCapacityMah,
            designCapacityMah: observation.designCapacityMah,
            temperatureC: observation.temperatureC
        )
        var day = BatteryBenchmarkDay(date: Calendar.autoupdatingCurrent.startOfDay(for: observation.timestamp))
        day.observe(observation)
        return BatteryBenchmarkReport(baseline: baseline, days: [day])
    }
}

actor FixedMaintenanceService: MaintenanceServicing {
    var status: CalibrationStatus
    var result: MaintenanceResult
    private(set) var commands: [CalibrationCommand] = []

    init(status: CalibrationStatus = .unavailable, result: MaintenanceResult? = nil) {
        self.status = status
        self.result = result ?? MaintenanceResult(succeeded: false, message: status.message, calibration: status)
    }

    func calibrationStatus() -> CalibrationStatus { status }

    func performCalibration(_ command: CalibrationCommand) -> MaintenanceResult {
        commands.append(command)
        status = result.calibration
        return result
    }
}

struct FixedUpdateService: AppUpdateChecking {
    let result: AppUpdateStatus
    func check(currentVersion: String) async -> AppUpdateStatus { result }
}

func verifiedResult() -> ChargeControlResult {
    ChargeControlResult(backendName: "Test", isHardwareControlAvailable: true,
        didAttemptHardwareChange: false, message: "Verified test limits", verifiedAt: Date(),
        isLimitEnabled: true, upperLimit: 80, lowerLimit: 50)
}

@MainActor
func isolatedSettings() -> GuardianSettings {
    let settings = GuardianSettings(defaults: UserDefaults(suiteName: "OrcaTests.\(UUID().uuidString)")!)
    settings.language = .english
    settings.notificationsEnabled = false
    settings.checksForUpdates = false
    return settings
}
