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

    public let settings: GuardianSettings
    private let realProvider: BatteryDataProviding
    private let mockProvider: BatteryDataProviding
    private let controller: any ChargeControlling
    private let simulationController: any ChargeControlling
    private let notifier: GuardianNotifying
    private let historyStore: any StatusHistoryStoring
    private let powerSourceMonitor: any PowerSourceEventMonitoring
    private let diagnosticsProvider: any DiagnosticsProviding
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
        self.coolingPolicy = coolingPolicy
        self.nativeChargeLimitAvailable = nativeChargeLimitAvailable
        snapshot = BatterySnapshot(percentage: 0, powerSource: .unknown, isCharging: false,
            isFullyCharged: false, temperatureC: nil, cycleCount: nil, health: nil)
        decision = GuardianDecision(state: .unknown, desiredAction: .noChange,
            statusText: "Starting", reason: "Waiting for battery data.")
    }

    public var isControlVerified: Bool {
        chargeControlResult.isHardwareControlAvailable && chargeControlResult.verifiedAt != nil
    }

    public var protectionStatusText: String {
        if settings.simulationMode { return "Simulation - no hardware writes" }
        if settings.isChargeToFullActive {
            return isControlVerified ? "Temporary full charge active" : "Preparing full charge"
        }
        guard isControlVerified else {
            return chargeControlResult.backendName == "Checking" ? "Checking charge controller" : "Protection unverified"
        }
        return chargeControlResult.isLimitEnabled == true ? "Charge limits verified" : "Charge limit disabled"
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
            pendingEventOverride = ("Temporary full charge cancelled", "The saved charge profile was restored before Orca quit.")
            await refreshAndWait()
        }
        if historyLoaded, historyCanWrite { await persistHistory() }
    }

    public func refresh() {
        expireTemporaryFullChargeIfNeeded()
        let input = currentInput
        pendingRefresh = true
        if displayedInput != input { chargeControlResult = .checking }
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
        settings.isChargeToFullActive ? "Full Charge" : settings.mode.title
    }

    public var isNativeChargeLimitAvailable: Bool { nativeChargeLimitAvailable }

    public func beginTemporaryFullCharge(_ duration: FullChargeDuration) {
        guard settings.protectionEnabled else { return }
        settings.beginTemporaryFullCharge(duration: duration)
        pendingEventOverride = ("Temporary full charge started", "Charging is allowed for \(duration.title), then \(settings.mode.title) will be restored.")
        refresh()
    }

    public func setProtectionEnabled(_ enabled: Bool) {
        if !enabled, settings.chargeToFullUntil != nil {
            settings.endTemporaryFullCharge()
            pendingEventOverride = ("Battery protection disabled", "Temporary full charge was cancelled and Orca charge control was disabled.")
        }
        settings.protectionEnabled = enabled
        refresh()
    }

    public func cancelTemporaryFullCharge() {
        guard settings.chargeToFullUntil != nil else { return }
        settings.endTemporaryFullCharge()
        pendingEventOverride = ("Temporary full charge cancelled", "The \(settings.mode.title) profile was restored.")
        refresh()
    }

    public func switchToMacOSChargeLimit() {
        guard nativeChargeLimitAvailable else { return }
        settings.endTemporaryFullCharge()
        settings.protectionEnabled = false
        pendingEventOverride = ("Switched to macOS Charge Limit", "Orca charge control was disabled before opening Battery Settings.")
        refresh()
    }

    public func runDiagnostics() async {
        guard !isRunningDiagnostics else { return }
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }
        diagnosticChecks = await diagnosticsProvider.run(snapshot: snapshot)
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
            pendingEventOverride = ("Full charge completed", "The battery reached 100%. The \(settings.mode.title) profile is being restored.")
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
            protectionEnabled: input.protectionEnabled, coolingPauseActive: cooling.isActive)
        snapshot = measured
        decision = requested

        let activeController = input.simulation ? simulationController : controller
        let result = await activeController.apply(decision: requested, snapshot: measured,
            thresholds: input.thresholds, protectionEnabled: input.protectionEnabled)

        // A changed profile or Simulation must never publish an old command result.
        // The next refresh starts only after the cancelled operation has unwound.
        guard !Task.isCancelled, input == currentInput else { return }
        chargeControlResult = result
        displayedInput = input
        if recordEventIfNeeded(input: input) { await persistHistory() }
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
            title = input.simulation ? "Simulation enabled" : "Live monitoring resumed"
            detail = "\(decision.reason) \(chargeControlResult.message)"
        } else if let previous = lastEvent, previous.verified != signature.verified, !input.simulation {
            title = signature.verified ? "Charge controller recovered" : "Charge control unverified"
            detail = "\(decision.reason) \(chargeControlResult.message)"
        } else if let previous = lastEvent, previous.input != input {
            title = "Charge profile updated"
            detail = "\(decision.reason) \(chargeControlResult.message)"
        } else if changedHardware, lastEvent != nil {
            title = "Charge limits restored"
            detail = "\(decision.reason) \(chargeControlResult.message)"
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
            historyError = "History could not be saved: \(error.localizedDescription)"
        }
    }

    private func expireTemporaryFullChargeIfNeeded(now: Date = Date()) {
        guard let until = settings.chargeToFullUntil, until <= now else { return }
        settings.endTemporaryFullCharge()
        pendingEventOverride = ("Temporary full charge ended", "The time limit expired. The \(settings.mode.title) profile is being restored.")
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
