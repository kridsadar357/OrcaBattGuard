import Foundation
import Testing
@testable import OrcaBatteryGuardian

private actor RecordingController: ChargeControlling {
    private var results: [ChargeControlResult]
    private(set) var calls = 0
    init(_ results: [ChargeControlResult] = [verifiedResult()]) { self.results = results }
    func apply(decision: GuardianDecision, snapshot: BatterySnapshot, thresholds: ChargeThresholds, protectionEnabled: Bool) async -> ChargeControlResult {
        calls += 1
        return results.count > 1 ? results.removeFirst() : results[0]
    }
}

// Intentionally ignores cancellation to prove the engine rejects stale completions.
private actor GatedController: ChargeControlling {
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    private(set) var ranges: [ChargeThresholds] = []
    private(set) var maxConcurrent = 0
    private var active = 0

    func apply(decision: GuardianDecision, snapshot: BatterySnapshot, thresholds: ChargeThresholds, protectionEnabled: Bool) async -> ChargeControlResult {
        calls += 1
        ranges.append(thresholds)
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        if calls == 1 {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()
            }
        }
        active -= 1
        return verifiedResult()
    }

    func waitUntilStarted() async {
        if releaseContinuation != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor InspectingController: ChargeControlling {
    private(set) var ranges: [ChargeThresholds] = []
    private(set) var calls = 0

    func apply(decision: GuardianDecision, snapshot: BatterySnapshot, thresholds: ChargeThresholds, protectionEnabled: Bool) -> ChargeControlResult {
        calls += 1
        ranges.append(thresholds)
        return ChargeControlResult(backendName: "Test", isHardwareControlAvailable: true,
            didAttemptHardwareChange: true, message: "Applied test limits", verifiedAt: Date(),
            isLimitEnabled: thresholds.upper < 100, upperLimit: thresholds.upper,
            lowerLimit: thresholds.lower)
    }
}

@MainActor
private func engine(
    settings: GuardianSettings? = nil,
    provider: BatteryDataProviding = FixedBatteryProvider(value: sampleBattery(65, charging: true)),
    controller: any ChargeControlling,
    history: any StatusHistoryStoring = MemoryHistory(),
    powerSourceMonitor: any PowerSourceEventMonitoring = TestPowerSourceMonitor(),
    diagnosticsProvider: any DiagnosticsProviding = FixedDiagnosticsProvider(checks: []),
    benchmarkStore: any BatteryBenchmarkStoring = MemoryBenchmarkStore(),
    maintenanceService: any MaintenanceServicing = FixedMaintenanceService(),
    updateService: any AppUpdateChecking = FixedUpdateService(result: AppUpdateStatus(state: .upToDate, currentVersion: "0.7.0")),
    nativeChargeLimitAvailable: Bool = false
) -> GuardianEngine {
    GuardianEngine(settings: settings ?? isolatedSettings(),
        realProvider: provider,
        mockProvider: FixedBatteryProvider(value: sampleBattery(42, source: .battery)),
        controller: controller, notifier: SilentNotifier(), historyStore: history,
        powerSourceMonitor: powerSourceMonitor, diagnosticsProvider: diagnosticsProvider,
        benchmarkStore: benchmarkStore,
        maintenanceService: maintenanceService, updateService: updateService, currentVersion: "0.7.0",
        nativeChargeLimitAvailable: nativeChargeLimitAvailable)
}

@MainActor
private func waitUntilIdle(_ subject: GuardianEngine) async {
    while subject.isRefreshing {
        await Task.yield()
    }
}

@Test @MainActor func simulationNeverInvokesRealController() async {
    let settings = isolatedSettings()
    settings.simulationMode = true
    let controller = RecordingController()
    let subject = engine(settings: settings, controller: controller)
    await subject.refreshAndWait()
    #expect(await controller.calls == 0)
    #expect(subject.snapshot.percentage == 42)
    #expect(subject.chargeControlResult.backendName == "Simulation")
    #expect(!subject.chargeControlResult.didAttemptHardwareChange && !subject.isControlVerified)
}

@Test @MainActor func switchingToSimulationRejectsInFlightHardwareResult() async {
    let settings = isolatedSettings()
    let controller = GatedController()
    let subject = engine(settings: settings, controller: controller)
    subject.refresh()
    await controller.waitUntilStarted()
    settings.simulationMode = true
    subject.refresh()
    #expect(!subject.isControlVerified)
    await controller.release()
    await subject.refreshAndWait()
    #expect(subject.chargeControlResult.backendName == "Simulation")
    #expect(subject.snapshot.percentage == 42)
    #expect(await controller.calls == 1)
    #expect(subject.events.count == 1)
    #expect(subject.events[0].detail.contains("Simulation only"))
}

@Test @MainActor func changedProfileIsSerializedAndRepeatedRefreshesCoalesce() async {
    let settings = isolatedSettings()
    let controller = GatedController()
    let subject = engine(settings: settings, controller: controller)
    subject.refresh()
    await controller.waitUntilStarted()
    settings.mode = .maximumLife
    for _ in 0..<10 { subject.refresh() }
    await controller.release()
    await subject.refreshAndWait()
    #expect(await controller.calls == 2)
    #expect(await controller.maxConcurrent == 1)
    #expect(await controller.ranges.map(\.upper) == [80, 70])
    #expect(subject.events.count == 1)
}

@Test @MainActor func controllerFailureAndRecoveryAreLoggedWithoutBatteryStateChange() async {
    let controller = RecordingController([verifiedResult(), .checking, verifiedResult(), verifiedResult()])
    let subject = engine(controller: controller)
    for _ in 0..<4 { await subject.refreshAndWait() }
    #expect(subject.events.count == 3)
    #expect(subject.events[0].title == "Charge controller recovered")
    #expect(subject.events[1].title == "Charge control unverified")
    #expect(subject.isControlVerified)
}

@Test @MainActor func controllerRepairIsLoggedEvenWhenStatusStaysVerified() async {
    var repair = verifiedResult()
    repair.didAttemptHardwareChange = true
    let subject = engine(controller: RecordingController([verifiedResult(), repair]))
    await subject.refreshAndWait()
    await subject.refreshAndWait()
    #expect(subject.events.first?.title == "Charge limits restored")
}

@Test @MainActor func startupRepairIsIdentifiedAsRecovery() async {
    var repair = verifiedResult()
    repair.didAttemptHardwareChange = true
    let subject = engine(controller: RecordingController([repair]))
    await subject.refreshAndWait()
    #expect(subject.events.first?.title == "Startup recovery applied")
}

@Test @MainActor func calibrationCommandIsDelegatedAndRefreshesProtection() async {
    let running = CalibrationStatus(isAvailable: true, phase: "Discharge", canPause: true, canCancel: true)
    let maintenance = FixedMaintenanceService(
        status: CalibrationStatus(isAvailable: true, phase: "Idle"),
        result: MaintenanceResult(succeeded: true, message: "Calibration command verified.", calibration: running)
    )
    let subject = engine(controller: RecordingController(), maintenanceService: maintenance)
    await subject.performCalibration(.start)
    await subject.refreshAndWait()
    #expect(subject.calibrationStatus == running)
    #expect(await maintenance.commands == [.start])
    #expect(subject.events.first?.title == "Calibration updated")
}

@Test @MainActor func automaticUpdateCheckHonorsDailyInterval() async {
    let settings = isolatedSettings()
    settings.checksForUpdates = true
    settings.lastUpdateCheck = Date()
    let available = AppUpdateStatus(
        state: .updateAvailable, currentVersion: "0.7.0", latestVersion: "0.8.0",
        releaseURL: URL(string: "https://example.com/release")
    )
    let subject = engine(
        settings: settings,
        controller: RecordingController(),
        updateService: FixedUpdateService(result: available)
    )
    await subject.checkForUpdates(force: false)
    #expect(subject.updateStatus.state == .notChecked)
    settings.lastUpdateCheck = Date(timeIntervalSinceNow: -(25 * 60 * 60))
    await subject.checkForUpdates(force: false)
    #expect(subject.updateStatus.state == .updateAvailable)
}

@Test @MainActor func engineLoadsEarlierHistoryAndFlushesOnShutdown() async {
    let previous = StatusEvent(date: Date(timeIntervalSince1970: 1), title: "Earlier session", detail: "Retained")
    let history = MemoryHistory(events: [previous])
    let subject = engine(controller: RecordingController(), history: history)
    await subject.refreshAndWait()
    await subject.shutdown()
    #expect(subject.events.contains(previous))
    #expect(await history.events == subject.events)
    #expect(await history.saves == 2)
}

@Test @MainActor func historyLoadFailureIsVisibleAndDoesNotOverwriteFile() async {
    let history = MemoryHistory(failLoad: true)
    let subject = engine(controller: RecordingController(), history: history)
    await subject.refreshAndWait()
    await subject.shutdown()
    #expect(subject.historyError != nil)
    #expect(subject.events.count == 1)
    #expect(await history.saves == 0)
}

@Test @MainActor func historySaveFailureIsVisibleWithoutLosingMemoryEvents() async {
    let subject = engine(controller: RecordingController(), history: MemoryHistory(failSave: true))
    await subject.refreshAndWait()
    #expect(subject.historyError != nil && subject.events.count == 1)
    #expect(subject.isControlVerified)
}

@Test @MainActor func shutdownCancelsQueuedRefreshAndDoesNotPublishLateResult() async {
    let controller = GatedController()
    let subject = engine(controller: controller)
    subject.refresh()
    await controller.waitUntilStarted()
    subject.refresh()
    subject.stop()
    await controller.release()
    await subject.shutdown()
    #expect(await controller.calls == 1)
    #expect(subject.events.isEmpty && !subject.isControlVerified)
    #expect(!subject.isRefreshing)
}

@Test @MainActor func disabledLimitIsNotLabeledProtected() async {
    var result = verifiedResult()
    result.isLimitEnabled = false
    let subject = engine(controller: RecordingController([result]))
    await subject.refreshAndWait()
    #expect(subject.protectionStatusText == "Charge limit disabled")
}

@Test @MainActor func temporaryFullChargeDisablesLimitThenRestoresSavedProfile() async {
    let settings = isolatedSettings()
    settings.mode = .balanced
    let controller = InspectingController()
    let subject = engine(settings: settings, controller: controller)

    subject.beginTemporaryFullCharge(.oneHour)
    await waitUntilIdle(subject)
    #expect(settings.isChargeToFullActive)
    #expect(subject.effectiveThresholds.upper == 100)
    #expect(subject.effectiveModeTitle == "Full Charge")
    #expect(await controller.ranges.map(\.upper) == [100])
    #expect(subject.events.first?.title == "Temporary full charge started")

    subject.cancelTemporaryFullCharge()
    await waitUntilIdle(subject)
    #expect(!settings.isChargeToFullActive)
    #expect(subject.effectiveThresholds == testLimits)
    #expect(await controller.ranges.map(\.upper) == [100, 80])
    #expect(subject.events.first?.title == "Temporary full charge cancelled")
}

@Test @MainActor func temporaryFullChargePreservesConfiguredSafetyLimits() {
    let settings = isolatedSettings()
    settings.customThresholds.hotTemperatureC = 41
    settings.customThresholds.criticalLow = 12
    settings.beginTemporaryFullCharge(duration: .oneHour)
    let subject = engine(settings: settings, controller: InspectingController())
    #expect(subject.effectiveThresholds.upper == 100)
    #expect(subject.effectiveThresholds.hotTemperatureC == 41)
    #expect(subject.effectiveThresholds.criticalLow == 12)
}

@Test @MainActor func temporaryFullChargeRequiresProtectionToBeEnabled() async {
    let settings = isolatedSettings()
    settings.protectionEnabled = false
    let controller = InspectingController()
    let subject = engine(settings: settings, controller: controller)
    subject.beginTemporaryFullCharge(.oneHour)
    await Task.yield()
    #expect(settings.chargeToFullUntil == nil)
    #expect(await controller.calls == 0)
}

@Test @MainActor func disablingProtectionCancelsTemporaryFullCharge() async {
    let settings = isolatedSettings()
    let controller = InspectingController()
    let subject = engine(settings: settings, controller: controller)
    subject.beginTemporaryFullCharge(.oneHour)
    await waitUntilIdle(subject)
    subject.setProtectionEnabled(false)
    await waitUntilIdle(subject)
    #expect(!settings.protectionEnabled)
    #expect(settings.chargeToFullUntil == nil)
    #expect(subject.events.first?.title == "Battery protection disabled")
}

@Test @MainActor func switchingToNativeLimitDisablesOrcaControl() async {
    let settings = isolatedSettings()
    settings.beginTemporaryFullCharge(duration: .oneHour)
    let controller = InspectingController()
    let subject = engine(settings: settings, controller: controller, nativeChargeLimitAvailable: true)
    subject.switchToMacOSChargeLimit()
    await waitUntilIdle(subject)
    #expect(!settings.protectionEnabled)
    #expect(settings.chargeToFullUntil == nil)
    #expect(await controller.ranges.map(\.upper) == [80])
    #expect(subject.events.first?.title == "Switched to macOS Charge Limit")
}

@Test @MainActor func switchingToNativeLimitIsIgnoredOnUnsupportedMacOS() async {
    let settings = isolatedSettings()
    let controller = InspectingController()
    let subject = engine(settings: settings, controller: controller, nativeChargeLimitAvailable: false)
    subject.switchToMacOSChargeLimit()
    await Task.yield()
    #expect(settings.protectionEnabled)
    #expect(await controller.calls == 0)
}

@Test @MainActor func expiredFullChargeRestoresProfileOnNextRefresh() async {
    let settings = isolatedSettings()
    settings.chargeToFullUntil = Date(timeIntervalSinceNow: -1)
    let controller = InspectingController()
    let subject = engine(settings: settings, controller: controller)
    await subject.refreshAndWait()
    #expect(settings.chargeToFullUntil == nil)
    #expect(await controller.ranges.map(\.upper) == [80])
    #expect(subject.events.first?.title == "Temporary full charge ended")
}

@Test @MainActor func reachingFullBatteryRestoresProfileWithoutApplyingFullTargetAgain() async {
    let settings = isolatedSettings()
    let controller = InspectingController()
    let subject = engine(settings: settings,
        provider: FixedBatteryProvider(value: sampleBattery(100, charging: false)),
        controller: controller)
    subject.beginTemporaryFullCharge(.oneHour)
    await waitUntilIdle(subject)
    #expect(settings.chargeToFullUntil == nil)
    #expect(await controller.ranges.map(\.upper) == [80])
    #expect(subject.events.first?.title == "Full charge completed")
}

@Test @MainActor func shutdownRestoresProfileWhenFullChargeIsActive() async {
    let settings = isolatedSettings()
    let controller = InspectingController()
    let subject = engine(settings: settings, controller: controller)
    subject.beginTemporaryFullCharge(.oneHour)
    await waitUntilIdle(subject)
    await subject.shutdown()
    #expect(settings.chargeToFullUntil == nil)
    #expect(await controller.ranges.map(\.upper) == [100, 80])
    #expect(subject.events.first?.title == "Temporary full charge cancelled")
}

@Test @MainActor func powerSourceEventTriggersImmediateRefresh() async {
    let monitor = TestPowerSourceMonitor()
    let controller = RecordingController()
    let subject = engine(controller: controller, powerSourceMonitor: monitor)
    subject.start()
    await subject.refreshAndWait()
    let initialCalls = await controller.calls
    monitor.trigger()
    for _ in 0..<20 where await controller.calls == initialCalls {
        await Task.yield()
    }
    #expect(monitor.startCalls == 1)
    #expect(await controller.calls > initialCalls)
    subject.stop()
    #expect(monitor.stopCalls == 1)
}

@Test @MainActor func diagnosticsResultsArePublishedByEngine() async {
    let expected = DiagnosticCheck(id: "test", title: "Test check", detail: "Passed", level: .passed)
    let diagnostics = FixedDiagnosticsProvider(checks: [expected])
    let subject = engine(controller: RecordingController(), diagnosticsProvider: diagnostics)
    await subject.runDiagnostics()
    #expect(subject.diagnosticChecks == [expected])
    #expect(!subject.isRunningDiagnostics)
    #expect(await diagnostics.calls == 1)
}

@Test @MainActor func liveRefreshRecordsBatteryBenchmark() async {
    let benchmark = MemoryBenchmarkStore()
    let subject = engine(controller: RecordingController(), benchmarkStore: benchmark)
    await subject.refreshAndWait()
    #expect(await benchmark.observations.count == 1)
    #expect(subject.benchmarkReport?.baseline.fullChargeCapacityMah == 8_000)
    #expect(subject.benchmarkError == nil)
}

@Test @MainActor func simulationDoesNotPolluteBatteryBenchmark() async {
    let settings = isolatedSettings()
    settings.simulationMode = true
    let benchmark = MemoryBenchmarkStore()
    let subject = engine(settings: settings, controller: RecordingController(), benchmarkStore: benchmark)
    await subject.refreshAndWait()
    #expect(await benchmark.observations.isEmpty)
    #expect(subject.benchmarkReport == nil)
}

@Test @MainActor func resettingBenchmarkUsesCurrentLiveReading() async {
    let benchmark = MemoryBenchmarkStore()
    let subject = engine(controller: RecordingController(), benchmarkStore: benchmark)
    await subject.refreshAndWait()
    await subject.resetBenchmark()
    #expect(await benchmark.observations.count == 1)
    #expect(subject.benchmarkReport?.baseline.cycleCount == 100)
}
