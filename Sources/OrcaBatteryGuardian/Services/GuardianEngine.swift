import AppKit
import Foundation

@MainActor
public final class GuardianEngine: ObservableObject {
    @Published public private(set) var snapshot: BatterySnapshot
    @Published public private(set) var decision: GuardianDecision
    @Published public private(set) var chargeControlResult = ChargeControlResult.checking
    @Published public private(set) var events: [StatusEvent] = []
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var historyError: String?
    @Published public private(set) var diagnosticChecks: [DiagnosticCheck] = []
    @Published public private(set) var isRunningDiagnostics = false
    @Published public private(set) var benchmarkReport: BatteryBenchmarkReport?
    @Published public private(set) var benchmarkError: String?
    @Published public private(set) var calibrationStatus = CalibrationStatus.unavailable
    @Published public private(set) var maintenanceMessage: String?
    @Published public private(set) var isPerformingMaintenance = false
    @Published public private(set) var updateStatus: AppUpdateStatus

    public let settings: GuardianSettings
    private let realProvider: BatteryDataProviding
    private let mockProvider: BatteryDataProviding
    private let controller: any ChargeControlling
    private let simulationController: any ChargeControlling
    private let notifier: GuardianNotifying
    private let historyStore: any StatusHistoryStoring
    private let powerSourceMonitor: any PowerSourceEventMonitoring
    private let diagnosticsProvider: any DiagnosticsProviding
    private let benchmarkStore: any BatteryBenchmarkStoring
    private let maintenanceService: any MaintenanceServicing
    private let updateService: any AppUpdateChecking
    private let currentVersion: String
    private let nativeChargeLimitAvailable: Bool
    private let stateMachine = GuardianStateMachine()
    private let coolingPolicy: CoolingPolicy
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private var runningInput: ControlInput?
    private var pendingRefresh = false
    private var historyLoaded = false
    private var historyCanWrite = true
    private var lastEvent: EventSignature?
    private var displayedInput: ControlInput?
    private var coolingPauseStartedAt: Date?
    private var pendingEventOverride: (title: String, detail: String)?

    public init(
        settings: GuardianSettings = GuardianSettings(),
        realProvider: BatteryDataProviding = IOKitBatteryDataProvider(),
        mockProvider: BatteryDataProviding = MockBatteryDataProvider(),
        controller: any ChargeControlling = SystemChargeController(),
        simulationController: any ChargeControlling = SafeNoOpChargeController(),
        notifier: GuardianNotifying = UserNotificationService(),
        historyStore: any StatusHistoryStoring = StatusHistoryStore(),
        powerSourceMonitor: any PowerSourceEventMonitoring = IOPowerSourceEventMonitor(),
        diagnosticsProvider: any DiagnosticsProviding = SystemDiagnosticsService(),
        benchmarkStore: any BatteryBenchmarkStoring = BatteryBenchmarkStore(),
        maintenanceService: any MaintenanceServicing = BattMaintenanceService(),
        updateService: any AppUpdateChecking = GitHubUpdateService(),
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.0",
        coolingPolicy: CoolingPolicy = CoolingPolicy(),
        nativeChargeLimitAvailable: Bool = NativeChargeLimitSupport.isAvailable
    ) {
        self.settings = settings
        self.realProvider = realProvider
        self.mockProvider = mockProvider
        self.controller = controller
        self.simulationController = simulationController
        self.notifier = notifier
        self.historyStore = historyStore
        self.powerSourceMonitor = powerSourceMonitor
        self.diagnosticsProvider = diagnosticsProvider
        self.benchmarkStore = benchmarkStore
        self.maintenanceService = maintenanceService
        self.updateService = updateService
        self.currentVersion = currentVersion
        self.coolingPolicy = coolingPolicy
        self.nativeChargeLimitAvailable = nativeChargeLimitAvailable
        updateStatus = AppUpdateStatus(state: .notChecked, currentVersion: currentVersion)
        chargeControlResult = .checking(language: settings.language)
        snapshot = BatterySnapshot(percentage: 0, powerSource: .unknown, isCharging: false,
            isFullyCharged: false, temperatureC: nil, cycleCount: nil, health: nil)
        decision = GuardianDecision(state: .unknown, desiredAction: .noChange,
            statusText: L10n.string("Starting", language: settings.language),
            reason: L10n.string("Waiting for battery data.", language: settings.language))
    }

    public var isControlVerified: Bool {
        chargeControlResult.isHardwareControlAvailable && chargeControlResult.verifiedAt != nil
    }

    public var protectionStatusText: String {
        if settings.simulationMode { return text("Simulation - no hardware writes") }
        if settings.isChargeToFullActive {
            return isControlVerified ? text("Temporary full charge active") : text("Preparing full charge")
        }
        guard isControlVerified else {
            return chargeControlResult.backendName == text("Checking") ? text("Checking charge controller") : text("Protection unverified")
        }
        return chargeControlResult.isLimitEnabled == true ? text("Charge limits verified") : text("Charge limit disabled")
    }

    public func start() {
        guard timer == nil else { return }
        if settings.notificationsEnabled { notifier.requestAuthorization() }
        powerSourceMonitor.start { [weak self] in self?.refresh() }
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        powerSourceMonitor.stop()
        pendingRefresh = false
        refreshTask?.cancel()
    }

    public func shutdown() async {
        let shouldRestoreProfile = settings.isChargeToFullActive
        stop()
        await refreshTask?.value
        if shouldRestoreProfile {
            settings.endTemporaryFullCharge()
            pendingEventOverride = (text("Temporary full charge cancelled"), text("The saved charge profile was restored before Orca quit."))
            await refreshAndWait()
        }
        if historyLoaded, historyCanWrite { await persistHistory() }
        do {
            try await benchmarkStore.flush(at: Date())
        } catch {
            benchmarkError = text("Benchmark could not be saved: %@", error.localizedDescription)
        }
    }

    public func refresh() {
        expireTemporaryFullChargeIfNeeded()
        let input = currentInput
        pendingRefresh = true
        if displayedInput != input { chargeControlResult = .checking(language: settings.language) }
        if let runningInput, runningInput != input {
            refreshTask?.cancel()
        }
        if refreshTask == nil { beginRefresh() }
    }

    public func refreshAndWait() async {
        refresh()
        while let task = refreshTask { await task.value }
    }

    public var effectiveThresholds: ChargeThresholds {
        let configured = settings.activeThresholds
        guard settings.isChargeToFullActive else { return configured }
        return ChargeThresholds(lower: 20, upper: 100,
            criticalLow: configured.criticalLow,
            hotTemperatureC: configured.hotTemperatureC)
    }

    public var effectiveModeTitle: String {
        settings.isChargeToFullActive ? text("Full Charge") : settings.mode.title(language: settings.language)
    }

    public var isNativeChargeLimitAvailable: Bool { nativeChargeLimitAvailable }

    public func beginTemporaryFullCharge(_ duration: FullChargeDuration) {
        guard settings.protectionEnabled else { return }
        settings.beginTemporaryFullCharge(duration: duration)
        pendingEventOverride = (
            text("Temporary full charge started"),
            text("Charging is allowed for %@, then %@ will be restored.", duration.title(language: settings.language), settings.mode.title(language: settings.language))
        )
        refresh()
    }

    public func setProtectionEnabled(_ enabled: Bool) {
        if !enabled, settings.chargeToFullUntil != nil {
            settings.endTemporaryFullCharge()
            pendingEventOverride = (text("Battery protection disabled"), text("Temporary full charge was cancelled and Orca charge control was disabled."))
        }
        settings.protectionEnabled = enabled
        refresh()
    }

    public func cancelTemporaryFullCharge() {
        guard settings.chargeToFullUntil != nil else { return }
        settings.endTemporaryFullCharge()
        pendingEventOverride = (text("Temporary full charge cancelled"), text("The %@ profile was restored.", settings.mode.title(language: settings.language)))
        refresh()
    }

    public func switchToMacOSChargeLimit() {
        guard nativeChargeLimitAvailable else { return }
        settings.endTemporaryFullCharge()
        settings.protectionEnabled = false
        pendingEventOverride = (text("Switched to macOS Charge Limit"), text("Orca charge control was disabled before opening Battery Settings."))
        refresh()
    }

    public func runDiagnostics() async {
        guard !isRunningDiagnostics else { return }
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }
        diagnosticChecks = await diagnosticsProvider.run(snapshot: snapshot, language: settings.language)
    }

    public func refreshCalibrationStatus() async {
        guard !settings.simulationMode else {
            calibrationStatus = .unavailable
            maintenanceMessage = text("Calibration is unavailable in Simulation Mode.")
            return
        }
        calibrationStatus = await maintenanceService.calibrationStatus()
    }

    public func performCalibration(_ command: CalibrationCommand) async {
        guard !settings.simulationMode, !isPerformingMaintenance else { return }
        isPerformingMaintenance = true
        defer { isPerformingMaintenance = false }
        let result = await maintenanceService.performCalibration(command)
        calibrationStatus = result.calibration
        maintenanceMessage = text(result.message)
        pendingEventOverride = (
            text(result.succeeded ? "Calibration updated" : "Calibration command failed"),
            maintenanceMessage ?? result.message
        )
        refresh()
    }

    public func checkForUpdates(force: Bool = true) async {
        guard updateStatus.state != .checking else { return }
        if !force {
            guard settings.checksForUpdates else { return }
            if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        }
        updateStatus = AppUpdateStatus(state: .checking, currentVersion: currentVersion)
        let result = await updateService.check(currentVersion: currentVersion)
        updateStatus = result
        settings.lastUpdateCheck = Date()
    }

    public func resetBenchmark() async {
        guard !settings.simulationMode, snapshot.powerSource != .unknown else { return }
        do {
            benchmarkReport = try await benchmarkStore.reset(with: benchmarkObservation)
            benchmarkError = nil
        } catch {
            benchmarkError = text("Benchmark could not be reset: %@", error.localizedDescription)
        }
    }

    private var currentInput: ControlInput {
        ControlInput(mode: settings.mode, thresholds: effectiveThresholds,
            protectionEnabled: settings.protectionEnabled, simulation: settings.simulationMode,
            temporaryFullChargeUntil: settings.isChargeToFullActive ? settings.chargeToFullUntil : nil)
    }

    private func beginRefresh() {
        guard pendingRefresh else { return }
        pendingRefresh = false
        let input = currentInput
        runningInput = input
        isRefreshing = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(input)
            self.refreshTask = nil
            self.runningInput = nil
            self.isRefreshing = false
            if self.pendingRefresh { self.beginRefresh() }
        }
    }

    private func performRefresh(_ input: ControlInput) async {
        if !historyLoaded {
            do {
                events = try await historyStore.load()
            } catch {
                historyError = error.localizedDescription
                historyCanWrite = false
            }
            historyLoaded = true
        }
        guard !Task.isCancelled, input == currentInput else { return }
        let provider = input.simulation ? mockProvider : realProvider
        let measured = provider.currentSnapshot()
        if input.temporaryFullChargeUntil != nil,
           measured.percentage >= 100 || measured.isFullyCharged {
            snapshot = measured
            settings.endTemporaryFullCharge()
            pendingEventOverride = (text("Full charge completed"), text("The battery reached 100%. The %@ profile is being restored.", settings.mode.title(language: settings.language)))
            pendingRefresh = true
            return
        }
        let cooling = coolingPolicy.evaluate(
            temperatureC: measured.temperatureC,
            pauseAtC: input.thresholds.hotTemperatureC,
            startedAt: coolingPauseStartedAt
        )
        coolingPauseStartedAt = cooling.startedAt
        let requested = stateMachine.decide(snapshot: measured, thresholds: input.thresholds,
            protectionEnabled: input.protectionEnabled, coolingPauseActive: cooling.isActive,
            language: settings.language)
        snapshot = measured
        decision = requested

        let activeController = input.simulation ? simulationController : controller
        let result = await activeController.apply(decision: requested, snapshot: measured,
            thresholds: input.thresholds, protectionEnabled: input.protectionEnabled)
            .localized(language: settings.language)

        // A changed profile or Simulation must never publish an old command result.
        // The next refresh starts only after the cancelled operation has unwound.
        guard !Task.isCancelled, input == currentInput else { return }
        chargeControlResult = result
        displayedInput = input
        if !input.simulation { await recordBenchmark() }
        if recordEventIfNeeded(input: input) { await persistHistory() }
    }

    private var benchmarkObservation: BatteryBenchmarkObservation {
        BatteryBenchmarkObservation(
            snapshot: snapshot,
            state: decision.state,
            protectionEnabled: settings.protectionEnabled,
            controlVerified: isControlVerified
        )
    }

    private func recordBenchmark() async {
        guard snapshot.powerSource != .unknown else { return }
        do {
            benchmarkReport = try await benchmarkStore.record(benchmarkObservation)
            benchmarkError = nil
        } catch {
            benchmarkError = text("Benchmark could not be saved: %@", error.localizedDescription)
        }
    }

    private func recordEventIfNeeded(input: ControlInput) -> Bool {
        let signature = EventSignature(input: input, state: decision.state,
            source: snapshot.powerSource, actualCharging: snapshot.isCharging,
            verified: isControlVerified, limitEnabled: chargeControlResult.isLimitEnabled)
        let changedHardware = chargeControlResult.didAttemptHardwareChange && isControlVerified
        guard signature != lastEvent || changedHardware || pendingEventOverride != nil else { return false }

        let title: String
        let detail: String
        if let override = pendingEventOverride {
            title = override.title
            detail = "\(override.detail) \(chargeControlResult.message)"
            pendingEventOverride = nil
        } else if let previous = lastEvent, previous.input.simulation != input.simulation {
            title = input.simulation ? text("Simulation enabled") : text("Live monitoring resumed")
            detail = "\(decision.reason) \(chargeControlResult.message)"
        } else if let previous = lastEvent, previous.verified != signature.verified, !input.simulation {
            title = signature.verified ? text("Charge controller recovered") : text("Charge control unverified")
            detail = "\(decision.reason) \(chargeControlResult.message)"
        } else if let previous = lastEvent, previous.input != input {
            title = text("Charge profile updated")
            detail = "\(decision.reason) \(chargeControlResult.message)"
        } else if changedHardware, lastEvent != nil {
            title = text("Charge limits restored")
            detail = "\(decision.reason) \(chargeControlResult.message)"
        } else if changedHardware, lastEvent == nil {
            title = text("Startup recovery applied")
            detail = "\(text("The saved charge profile was verified and restored after launch.")) \(chargeControlResult.message)"
        } else {
            title = decision.statusText
            detail = "\(decision.reason) \(chargeControlResult.message)"
        }
        lastEvent = signature
        events.insert(StatusEvent(title: title, detail: detail), at: 0)
        events = Array(events.prefix(StatusHistoryStore.maximumEvents))
        if settings.notificationsEnabled { notifier.notify(title: title, body: detail) }
        return true
    }

    private func persistHistory() async {
        guard historyCanWrite else { return }
        do {
            events = try await historyStore.save(events)
            historyError = nil
        } catch {
            historyError = text("History could not be saved: %@", error.localizedDescription)
        }
    }

    private func expireTemporaryFullChargeIfNeeded(now: Date = Date()) {
        guard let until = settings.chargeToFullUntil, until <= now else { return }
        settings.endTemporaryFullCharge()
        pendingEventOverride = (text("Temporary full charge ended"), text("The time limit expired. The %@ profile is being restored.", settings.mode.title(language: settings.language)))
    }

    private func text(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, language: settings.language, arguments: arguments)
    }

    private struct ControlInput: Equatable {
        let mode: GuardianMode
        let thresholds: ChargeThresholds
        let protectionEnabled: Bool
        let simulation: Bool
        let temporaryFullChargeUntil: Date?
    }

    private struct EventSignature: Equatable {
        let input: ControlInput
        let state: ChargingState
        let source: PowerSource
        let actualCharging: Bool
        let verified: Bool
        let limitEnabled: Bool?
    }
}
