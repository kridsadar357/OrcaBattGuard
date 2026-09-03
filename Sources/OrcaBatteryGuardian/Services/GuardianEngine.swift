import Foundation

@MainActor
public final class GuardianEngine: ObservableObject {
    @Published public private(set) var snapshot: BatterySnapshot
    @Published public private(set) var decision: GuardianDecision
    @Published public private(set) var chargeControlResult: ChargeControlResult
    @Published public private(set) var events: [StatusEvent] = []

    private let realProvider: BatteryDataProviding
    private let mockProvider: BatteryDataProviding
    private let controller: ChargeControlling
    private let simulationController: ChargeControlling
    private let notifier: GuardianNotifying
    private let stateMachine = GuardianStateMachine()
    private var timer: Timer?
    private var lastState: ChargingState?

    public let settings: GuardianSettings

    public init(
        settings: GuardianSettings = GuardianSettings(),
        realProvider: BatteryDataProviding = IOKitBatteryDataProvider(),
        mockProvider: BatteryDataProviding = MockBatteryDataProvider(),
        controller: ChargeControlling = SystemChargeController(),
        simulationController: ChargeControlling = SafeNoOpChargeController(),
        notifier: GuardianNotifying = UserNotificationService()
    ) {
        self.settings = settings
        self.realProvider = realProvider
        self.mockProvider = mockProvider
        self.controller = controller
        self.simulationController = simulationController
        self.notifier = notifier
        snapshot = BatterySnapshot(
            percentage: 0,
            powerSource: .unknown,
            isCharging: false,
            isFullyCharged: false,
            temperatureC: nil,
            cycleCount: nil,
            health: nil
        )
        decision = GuardianDecision(
            state: .unknown,
            desiredAction: .noChange,
            statusText: "Starting",
            reason: "Guardian is starting."
        )
        chargeControlResult = ChargeControlResult(
            backendName: "Starting",
            isHardwareControlAvailable: false,
            didAttemptHardwareChange: false,
            message: "Checking hardware charge-control backend."
        )
    }

    public func start() {
        guard timer == nil else { return }
        notifier.requestAuthorization()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        let provider = settings.simulationMode ? mockProvider : realProvider
        snapshot = provider.currentSnapshot()
        decision = stateMachine.decide(
            snapshot: snapshot,
            thresholds: settings.activeThresholds,
            protectionEnabled: settings.protectionEnabled
        )

        let activeController = settings.simulationMode ? simulationController : controller
        chargeControlResult = activeController.apply(
            decision: decision,
            snapshot: snapshot,
            thresholds: settings.activeThresholds,
            protectionEnabled: settings.protectionEnabled
        )
        recordEventIfNeeded()
    }

    private func recordEventIfNeeded() {
        guard lastState != decision.state || events.isEmpty else { return }
        lastState = decision.state
        let event = StatusEvent(title: decision.statusText, detail: "\(decision.reason) \(eventControlSummary)")
        events.insert(event, at: 0)
        events = Array(events.prefix(60))

        if settings.notificationsEnabled {
            notifier.notify(title: decision.statusText, body: decision.reason)
        }
    }

    private var eventControlSummary: String {
        if settings.simulationMode {
            return "Simulation did not change hardware settings."
        }
        if chargeControlResult.isHardwareControlAvailable {
            return chargeControlResult.didAttemptHardwareChange
                ? "Hardware charge limits were updated."
                : "Hardware charge limits are active."
        }
        return "Hardware charge control is unavailable."
    }
}
