import Foundation

public struct GuardianStateMachine: Sendable {
    public init() {}

    public func decide(
        snapshot: BatterySnapshot, thresholds: ChargeThresholds,
        protectionEnabled: Bool, coolingPauseActive: Bool = false,
        language: AppLanguage = .english
    ) -> GuardianDecision {
        let limits = thresholds.normalized
        func text(_ key: String, _ arguments: CVarArg...) -> String {
            L10n.string(key, language: language, arguments: arguments)
        }

        guard snapshot.powerSource != .unknown, (0...100).contains(snapshot.percentage) else {
            return GuardianDecision(state: .unknown, desiredAction: .noChange,
                statusText: text("Battery Unavailable"), reason: text("Waiting for reliable battery data."))
        }

        if snapshot.powerSource == .battery {
            return GuardianDecision(state: .discharging, desiredAction: .noChange,
                statusText: text("On Battery"),
                reason: snapshot.percentage <= limits.criticalLow
                    ? text("Battery is low. Connect a power adapter.")
                    : text("Using battery power. No forced discharge is requested."))
        }

        guard protectionEnabled else {
            return GuardianDecision(
                state: snapshot.isCharging ? .charging : .holding,
                desiredAction: .allowCharging,
                statusText: text("On AC Power"),
                reason: text("Battery protection is disabled.")
            )
        }

        if snapshot.percentage <= limits.criticalLow {
            return GuardianDecision(
                state: .safetyCharge,
                desiredAction: .allowCharging,
                statusText: text("Safety Charge"),
                reason: text("Battery is below the critical low threshold.")
            )
        }

        if coolingPauseActive || (snapshot.temperatureC.map { $0 >= limits.hotTemperatureC } ?? false) {
            return GuardianDecision(
                state: .coolingPause,
                desiredAction: .pauseCharging,
                statusText: text("Cooling Pause"),
                reason: coolingPauseActive
                    ? text("Waiting for the battery to cool and the minimum pause to finish.")
                    : text("Battery temperature is high.")
            )
        }

        if snapshot.percentage >= limits.upper {
            return GuardianDecision(
                state: .holding,
                desiredAction: .pauseCharging,
                statusText: snapshot.isCharging ? text("Stopping Charge") : text("Holding at %d%%", snapshot.percentage),
                reason: snapshot.isCharging ? text("Charge limit reached; waiting for charging to stop.") : text("Upper charge threshold reached.")
            )
        }

        if snapshot.percentage <= limits.lower {
            return GuardianDecision(
                state: .charging,
                desiredAction: .allowCharging,
                statusText: snapshot.isCharging ? text("Charging to %d%%", limits.upper) : text("Starting Charge"),
                reason: text("Battery is at or below the lower threshold.")
            )
        }

        if snapshot.isCharging {
            return GuardianDecision(state: .charging, desiredAction: .noChange,
                statusText: text("Charging to %d%%", limits.upper),
                reason: text("Charging continues inside the target range until the upper limit."))
        }
        return GuardianDecision(
            state: .holding,
            desiredAction: .noChange,
            statusText: text("Holding at %d%%", snapshot.percentage),
            reason: text("On adapter power without charging. No forced discharge.")
        )
    }
}
