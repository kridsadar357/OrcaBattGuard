import Foundation

public struct GuardianStateMachine: Sendable {
    public init() {}

    public func decide(snapshot: BatterySnapshot, thresholds: ChargeThresholds, protectionEnabled: Bool) -> GuardianDecision {
        let limits = thresholds.normalized

        guard protectionEnabled else {
            return GuardianDecision(
                state: snapshot.isCharging ? .charging : .unknown,
                desiredAction: .allowCharging,
                statusText: snapshot.powerSource == .acPower ? "On AC Power" : "On Battery",
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

        if let temperature = snapshot.temperatureC, temperature >= limits.hotTemperatureC {
            return GuardianDecision(
                state: .coolingPause,
                desiredAction: .pauseCharging,
                statusText: "Cooling Pause",
                reason: "Battery temperature is high."
            )
        }

        if snapshot.percentage >= limits.upper {
            return GuardianDecision(
                state: .holding,
                desiredAction: .pauseCharging,
                statusText: "Holding at \(snapshot.percentage)%",
                reason: "Upper charge threshold reached."
            )
        }

        if snapshot.percentage <= limits.lower {
            return GuardianDecision(
                state: .charging,
                desiredAction: .allowCharging,
                statusText: "Charging to \(limits.upper)%",
                reason: "Battery is at or below the lower threshold."
            )
        }

        if snapshot.powerSource == .acPower {
            return GuardianDecision(
                state: .holding,
                desiredAction: .noChange,
                statusText: "Battery Protection Active",
                reason: "Battery is inside the target range; no forced discharge."
            )
        }

        return GuardianDecision(
            state: .discharging,
            desiredAction: .noChange,
            statusText: "On Battery",
            reason: "Running on battery within target range."
        )
    }
}
