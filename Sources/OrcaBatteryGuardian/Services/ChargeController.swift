import Foundation

public protocol ChargeControlling {
    func apply(
        decision: GuardianDecision,
        snapshot: BatterySnapshot,
        thresholds: ChargeThresholds,
        protectionEnabled: Bool
    ) -> ChargeControlResult
}

public final class SafeNoOpChargeController: ChargeControlling {
    public init() {}

    public func apply(
        decision: GuardianDecision,
        snapshot: BatterySnapshot,
        thresholds: ChargeThresholds,
        protectionEnabled: Bool
    ) -> ChargeControlResult {
        ChargeControlResult(
            backendName: "Safe Monitor",
            isHardwareControlAvailable: false,
            didAttemptHardwareChange: false,
            message: "Monitoring only. No hardware charge-control backend is active."
        )
    }
}

public final class SystemChargeController: ChargeControlling {
    private let battPath: String?
    private let pmsetPath = "/usr/bin/pmset"
    private var lastAppliedLimit: Int?
    private var lastAppliedLowerLimit: Int?
    private var lastProtectionEnabled: Bool?

    public init() {
        battPath = ["/opt/homebrew/bin/batt", "/usr/local/bin/batt", "/usr/bin/batt"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func apply(
        decision: GuardianDecision,
        snapshot: BatterySnapshot,
        thresholds: ChargeThresholds,
        protectionEnabled: Bool
    ) -> ChargeControlResult {
        if let battPath {
            return applyWithBatt(
                path: battPath,
                decision: decision,
                snapshot: snapshot,
                thresholds: thresholds.normalized,
                protectionEnabled: protectionEnabled
            )
        }

        let pmsetReadout = run(pmsetPath, ["-g", "battlimit"])
        let pmsetMessage = pmsetReadout.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChargeControlResult(
            backendName: "Apple pmset",
            isHardwareControlAvailable: false,
            didAttemptHardwareChange: false,
            message: "No writable charge-limit backend found. pmset readout: \(pmsetMessage.isEmpty ? "unavailable" : pmsetMessage)"
        )
    }

    private func applyWithBatt(
        path: String,
        decision: GuardianDecision,
        snapshot: BatterySnapshot,
        thresholds: ChargeThresholds,
        protectionEnabled: Bool
    ) -> ChargeControlResult {
        let isCoolingPause = protectionEnabled && decision.state == .coolingPause
        let targetLimit: Int
        let targetLowerLimit: Int

        if !protectionEnabled {
            targetLimit = 100
            targetLowerLimit = 100
        } else if isCoolingPause {
            targetLimit = min(max(snapshot.percentage, 10), 99)
            targetLowerLimit = min(thresholds.lower, max(5, targetLimit - 1))
        } else {
            targetLimit = thresholds.upper
            targetLowerLimit = thresholds.lower
        }
        let shouldApply = lastAppliedLimit != targetLimit
            || lastAppliedLowerLimit != targetLowerLimit
            || lastProtectionEnabled != protectionEnabled
        lastAppliedLimit = targetLimit
        lastAppliedLowerLimit = targetLowerLimit
        lastProtectionEnabled = protectionEnabled

        guard shouldApply else {
            return ChargeControlResult(
                backendName: "batt",
                isHardwareControlAvailable: true,
                didAttemptHardwareChange: false,
                message: "Hardware limits already set to \(targetLowerLimit)-\(targetLimit)%."
            )
        }

        if targetLimit < 100 {
            let delta = max(1, targetLimit - targetLowerLimit)
            let deltaResult = run(path, ["lower-limit-delta", "\(delta)"])
            let deltaOutput = deltaResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard deltaResult.exitCode == 0 else {
                return ChargeControlResult(
                    backendName: "batt",
                    isHardwareControlAvailable: false,
                    didAttemptHardwareChange: true,
                    message: "batt lower-limit command failed. Run `sudo brew services start batt`, then reopen Orca. \(deltaOutput)"
                )
            }
        }

        let args = targetLimit >= 100 ? ["disable"] : ["limit", "\(targetLimit)"]
        let result = run(path, args)
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.exitCode == 0 else {
            return ChargeControlResult(
                backendName: "batt",
                isHardwareControlAvailable: false,
                didAttemptHardwareChange: true,
                message: "batt command failed. Run `sudo batt install --allow-non-root-access` once, then reopen Orca. \(output)"
            )
        }

        let action: String
        if targetLimit >= 100 {
            action = "disabled hardware charge limit"
        } else if isCoolingPause {
            action = "paused charging at \(targetLimit)% while the battery cools"
        } else {
            action = "set hardware charge limits to \(targetLowerLimit)-\(targetLimit)%"
        }
        return ChargeControlResult(
            backendName: "batt",
            isHardwareControlAvailable: true,
            didAttemptHardwareChange: true,
            message: "Applied: \(action). \(output)"
        )
    }

    private func run(_ launchPath: String, _ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (127, error.localizedDescription)
        }
    }
}
