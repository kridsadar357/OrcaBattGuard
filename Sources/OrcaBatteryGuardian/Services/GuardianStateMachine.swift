import Foundation

public struct GuardianStateMachine: Sendable {
    public init() {}

    public func decide(
        snapshot: BatterySnapshot, thresholds: ChargeThresholds,
        protectionEnabled: Bool, coolingPauseActive: Bool = false
    ) -> GuardianDecision {
        let limits = thresholds.normalized

        guard snapshot.powerSource != .unknown, (0...100).contains(snapshot.percentage) else {
            return GuardianDecision(state: .unknown, desiredAction: .noChange,
                statusText: "Battery Unavailable", reason: "Waiting for reliable battery data.")
        }

        if snapshot.powerSource == .battery {
            return GuardianDecision(state: .discharging, desiredAction: .noChange,
                statusText: "On Battery",
                reason: snapshot.percentage <= limits.criticalLow
                    ? "Battery is low. Connect a power adapter."
                    : "Using battery power. No forced discharge is requested.")
        }

        guard protectionEnabled else {
            return GuardianDecision(
                state: snapshot.isCharging ? .charging : .holding,
                desiredAction: .allowCharging,
                statusText: "On AC Power",
                reason: "Battery protection is disabled."
            )
        }

        if snapshot.percentage <= limits.criticalLow {
            return GuardianDecision(
                state: .safetyCharge,
                desiredAction: .allowCharging,
                statusText: "Safety Charge",
                reason: "Battery is below the critical low threshold."
            )
        }

        if coolingPauseActive || (snapshot.temperatureC.map { $0 >= limits.hotTemperatureC } ?? false) {
            return GuardianDecision(
                state: .coolingPause,
                desiredAction: .pauseCharging,
                statusText: "Cooling Pause",
                reason: coolingPauseActive
                    ? "Waiting for the battery to cool and the minimum pause to finish."
                    : "Battery temperature is high."
            )
        }

        if snapshot.percentage >= limits.upper {
            return GuardianDecision(
                state: .holding,
                desiredAction: .pauseCharging,
                statusText: snapshot.isCharging ? "Stopping Charge" : "Holding at \(snapshot.percentage)%",
                reason: snapshot.isCharging ? "Charge limit reached; waiting for charging to stop." : "Upper charge threshold reached."
            )
        }

        if snapshot.percentage <= limits.lower {
            return GuardianDecision(
                state: .charging,
                desiredAction: .allowCharging,
                statusText: snapshot.isCharging ? "Charging to \(limits.upper)%" : "Starting Charge",
                reason: "Battery is at or below the lower threshold."
            )
        }

        if snapshot.isCharging {
            return GuardianDecision(state: .charging, desiredAction: .noChange,
                statusText: "Charging to \(limits.upper)%",
                reason: "Charging continues inside the target range until the upper limit.")
        }
        return GuardianDecision(
            state: .holding,
            desiredAction: .noChange,
            statusText: "Holding at \(snapshot.percentage)%",
            reason: "On adapter power without charging. No forced discharge."
        )
    }
}
