import Foundation

public protocol ChargeControlling: Sendable {
    func apply(
        decision: GuardianDecision, snapshot: BatterySnapshot,
        thresholds: ChargeThresholds, protectionEnabled: Bool
    ) async -> ChargeControlResult
}

public struct SafeNoOpChargeController: ChargeControlling {
    public init() {}

    public func apply(
        decision: GuardianDecision, snapshot: BatterySnapshot,
        thresholds: ChargeThresholds, protectionEnabled: Bool
    ) async -> ChargeControlResult {
        ChargeControlResult(
            backendName: "Simulation", isHardwareControlAvailable: false,
            didAttemptHardwareChange: false,
            message: "Simulation only. Existing hardware limits are unchanged."
        )
    }
}

public actor SystemChargeController: ChargeControlling {
    private let runner: any CommandRunning
    private let battPath: String?
    private let commandTimeout: TimeInterval
    private let architecture: MacArchitecture
    private var isApplying = false

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        battPath: String? = SystemChargeController.installedBattPath,
        commandTimeout: TimeInterval = 3,
        architecture: MacArchitecture = .current
    ) {
        self.runner = runner
        self.battPath = battPath
        self.commandTimeout = commandTimeout
        self.architecture = architecture
    }

    public static var installedBattPath: String? {
        guard MacArchitecture.current.supportsBattChargeControl else { return nil }
        return ["/opt/homebrew/bin/batt", "/usr/local/bin/batt", "/usr/bin/batt"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func apply(
        decision: GuardianDecision, snapshot: BatterySnapshot,
        thresholds: ChargeThresholds, protectionEnabled: Bool
    ) async -> ChargeControlResult {
        guard !isApplying else { return failure("A controller update is already in progress.") }
        isApplying = true
        defer { isApplying = false }

        guard !Task.isCancelled else { return failure("Controller update cancelled.") }
        guard snapshot.powerSource != .unknown, (0...100).contains(snapshot.percentage) else {
            return failure("Battery data is unavailable. Hardware settings were not changed.")
        }
        guard let battPath else {
            let readout = await runner.run(executable: "/usr/bin/pmset", arguments: ["-g", "battlimit"], timeout: commandTimeout)
            let message = architecture == .intel
                ? "Intel monitoring mode. Battery data, history, benchmark, and CLI remain available; hardware charge control is disabled."
                : "No batt backend found. Monitoring only. " + (readout.succeeded ? "System battery information is available." : "System charge-limit readout is unavailable.")
            return ChargeControlResult(
                backendName: "Monitor Only", isHardwareControlAvailable: false,
                didAttemptHardwareChange: false,
                message: message
            )
        }

        let target = Target(decision: decision, snapshot: snapshot, thresholds: thresholds.normalized, protectionEnabled: protectionEnabled)
        var attempted = false
        do {
            // Read the daemon on every refresh. Only a matching read-back confirms
            // control, so neither failed writes nor external changes poison a cache.
            let before = try await readStatus(path: battPath)
            try checkCompatibility(before)
            if target.matches(before) { return verified(before, changed: false) }

            try Task.checkCancellation()
            if target.enabled {
                attempted = true
                try await command(path: battPath, arguments: ["lower-limit-delta", String(target.upper - target.lower)])
            }
            try Task.checkCancellation()
            attempted = true
            try await command(path: battPath, arguments: target.enabled ? ["limit", String(target.upper)] : ["disable"])

            let after = try await readStatus(path: battPath)
            try checkCompatibility(after)
            guard target.matches(after) else {
                return failure("The daemon has not confirmed the requested limits. Protection is unverified; the next refresh will retry.", attempted: attempted)
            }
            return verified(after, changed: true)
        } catch is CancellationError {
            return failure("Controller update cancelled.", attempted: attempted)
        } catch {
            return failure("\(error.localizedDescription) The next refresh will retry.", attempted: attempted)
        }
    }

    private func command(path: String, arguments: [String]) async throws {
        _ = try await execute(path: path, arguments: arguments)
    }

    private func execute(path: String, arguments: [String]) async throws -> CommandResult {
        try Task.checkCancellation()
        let result = await runner.run(executable: path, arguments: arguments, timeout: commandTimeout)
        try Task.checkCancellation()
        if result.cancelled { throw CancellationError() }
        guard !result.timedOut else { throw ControllerError("The charge controller timed out.") }
        guard !result.outputTruncated else { throw ControllerError("The charge controller response exceeded the output limit.") }
        guard result.exitCode == 0 else {
            throw ControllerError("The charge controller could not complete \(arguments[0]) (exit \(result.exitCode)). Check that batt is running and accessible.")
        }
        return result
    }

    private func readStatus(path: String) async throws -> BattStatus {
        let result = try await execute(path: path, arguments: ["status", "--json"])
        do {
            return try BattStatus.decode(result.output)
        } catch {
            throw ControllerError("Cannot verify the daemon response. A compatible batt version with JSON status is required.")
        }
    }

    private func checkCompatibility(_ status: BattStatus) throws {
        guard status.compatibility.chargingControl else {
            throw ControllerError("The backend does not support charging control on this Mac.")
        }
        if let phase = status.calibration?.phase, phase.lowercased() != "idle" {
            throw ControllerError("Battery calibration is in progress. Orca will not override it.")
        }
    }

    private func verified(_ status: BattStatus, changed: Bool) -> ChargeControlResult {
        let config = status.configuration
        return ChargeControlResult(
            backendName: "batt", isHardwareControlAvailable: true,
            didAttemptHardwareChange: changed,
            message: config.enabled
                ? "Verified charge limits: \(config.lowerLimitPercent)-\(config.upperLimitPercent)%. Hardware charging may take time to reflect the policy."
                : "Verified: the charge limit is disabled. macOS manages charging.",
            verifiedAt: Date(), isLimitEnabled: config.enabled,
            upperLimit: config.upperLimitPercent, lowerLimit: config.lowerLimitPercent
        )
    }

    private func failure(_ message: String, attempted: Bool = false) -> ChargeControlResult {
        ChargeControlResult(backendName: "batt", isHardwareControlAvailable: false, didAttemptHardwareChange: attempted, message: message)
    }

    private struct Target {
        let enabled: Bool
        let upper: Int
        let lower: Int

        init(decision: GuardianDecision, snapshot: BatterySnapshot, thresholds: ChargeThresholds, protectionEnabled: Bool) {
            if !protectionEnabled {
                upper = 100
                lower = 100
            } else if decision.state == .coolingPause {
                upper = min(max(snapshot.percentage, 10), 99)
                lower = min(thresholds.lower, max(5, upper - 1))
            } else {
                upper = thresholds.upper
                lower = thresholds.lower
            }
            enabled = upper < 100
        }

        func matches(_ status: BattStatus) -> Bool {
            let config = status.configuration
            return enabled == config.enabled && (!enabled || (upper == config.upperLimitPercent && lower == config.lowerLimitPercent))
        }
    }
}

private struct ControllerError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
