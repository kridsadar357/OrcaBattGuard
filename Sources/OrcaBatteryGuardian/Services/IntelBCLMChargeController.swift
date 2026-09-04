import Foundation

public enum IntelBCLMSupport {
    public static let helperPath = "/Library/PrivilegedHelperTools/dev.orca.batteryguardian.bclm-control"

    public static func supports(_ architecture: MacArchitecture, osVersion: OperatingSystemVersion) -> Bool {
        architecture == .intel && (13...14).contains(osVersion.majorVersion)
    }

    public static var isConfigured: Bool {
        supports(.current, osVersion: ProcessInfo.processInfo.operatingSystemVersion) &&
            FileManager.default.isExecutableFile(atPath: helperPath)
    }
}

public actor IntelBCLMChargeController: ChargeControlling {
    private let runner: any CommandRunning
    private let helperPath: String
    private let operatingSystemVersion: OperatingSystemVersion
    private let architecture: MacArchitecture
    private let commandTimeout: TimeInterval
    private var isApplying = false

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        helperPath: String = IntelBCLMSupport.helperPath,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        architecture: MacArchitecture = .current,
        commandTimeout: TimeInterval = 3
    ) {
        self.runner = runner
        self.helperPath = helperPath
        self.operatingSystemVersion = operatingSystemVersion
        self.architecture = architecture
        self.commandTimeout = commandTimeout
    }

    public func apply(
        decision: GuardianDecision,
        snapshot: BatterySnapshot,
        thresholds: ChargeThresholds,
        protectionEnabled: Bool
    ) async -> ChargeControlResult {
        guard !isApplying else { return failure("A controller update is already in progress.") }
        isApplying = true
        defer { isApplying = false }

        guard IntelBCLMSupport.supports(architecture, osVersion: operatingSystemVersion) else {
            return failure("Intel charge control is supported only on macOS 13 and 14. macOS 15 or newer blocks BCLM writes unless SIP is disabled.")
        }
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            return failure("Intel charge control is not configured. Install the Orca BCLM helper first.")
        }
        guard snapshot.powerSource != .unknown, (0...100).contains(snapshot.percentage) else {
            return failure("Battery data is unavailable. Hardware settings were not changed.")
        }

        let target = targetLimit(
            decision: decision,
            snapshot: snapshot,
            thresholds: thresholds.normalized,
            protectionEnabled: protectionEnabled
        )

        var attempted = false
        do {
            let before = try await readLimit()
            if before == target { return verified(target, changed: false) }

            try Task.checkCancellation()
            attempted = true
            let write = await runner.run(
                executable: "/usr/bin/sudo",
                arguments: ["-n", helperPath, "write", String(target)],
                timeout: commandTimeout
            )
            try validate(write, operation: "write")

            let after = try await readLimit()
            guard after == target else {
                return failure("The Intel controller did not confirm the requested BCLM limit. Protection is unverified.", attempted: true)
            }
            return verified(target, changed: true)
        } catch is CancellationError {
            return failure("Controller update cancelled.", attempted: attempted)
        } catch {
            return failure(error.localizedDescription, attempted: attempted)
        }
    }

    private func targetLimit(
        decision: GuardianDecision,
        snapshot: BatterySnapshot,
        thresholds: ChargeThresholds,
        protectionEnabled: Bool
    ) -> Int {
        guard protectionEnabled else { return 100 }
        if decision.state == .coolingPause {
            return min(max(snapshot.percentage, 50), 99)
        }
        return min(max(thresholds.upper, 50), 100)
    }

    private func readLimit() async throws -> Int {
        let result = await runner.run(executable: helperPath, arguments: ["read"], timeout: commandTimeout)
        try validate(result, operation: "read")
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let limit = Int(value), (50...100).contains(limit) else {
            throw IntelControllerError("The Intel controller returned an invalid BCLM value.")
        }
        return limit
    }

    private func validate(_ result: CommandResult, operation: String) throws {
        try Task.checkCancellation()
        if result.cancelled { throw CancellationError() }
        guard !result.timedOut else { throw IntelControllerError("The Intel charge controller timed out.") }
        guard !result.outputTruncated else { throw IntelControllerError("The Intel charge controller response exceeded the output limit.") }
        guard result.exitCode == 0 else {
            let suffix = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw IntelControllerError(
                suffix.isEmpty
                    ? "The Intel charge controller could not complete \(operation) (exit \(result.exitCode))."
                    : "The Intel charge controller could not complete \(operation): \(suffix)"
            )
        }
    }

    private func verified(_ limit: Int, changed: Bool) -> ChargeControlResult {
        ChargeControlResult(
            backendName: "BCLM",
            isHardwareControlAvailable: true,
            didAttemptHardwareChange: changed,
            message: limit < 100
                ? "Verified Intel BCLM upper limit: \(limit)%. Intel hardware does not provide a separate lower threshold."
                : "Verified Intel BCLM limit: 100%. macOS manages charging normally.",
            verifiedAt: Date(),
            isLimitEnabled: limit < 100,
            upperLimit: limit,
            lowerLimit: nil
        )
    }

    private func failure(_ message: String, attempted: Bool = false) -> ChargeControlResult {
        ChargeControlResult(
            backendName: "BCLM",
            isHardwareControlAvailable: false,
            didAttemptHardwareChange: attempted,
            message: message
        )
    }
}

public actor PlatformChargeController: ChargeControlling {
    private let architecture: MacArchitecture
    private let appleSiliconController: any ChargeControlling
    private let intelController: any ChargeControlling

    public init(
        architecture: MacArchitecture = .current,
        appleSiliconController: any ChargeControlling = SystemChargeController(),
        intelController: any ChargeControlling = IntelBCLMChargeController()
    ) {
        self.architecture = architecture
        self.appleSiliconController = appleSiliconController
        self.intelController = intelController
    }

    public func apply(
        decision: GuardianDecision,
        snapshot: BatterySnapshot,
        thresholds: ChargeThresholds,
        protectionEnabled: Bool
    ) async -> ChargeControlResult {
        let controller = architecture == .intel ? intelController : appleSiliconController
        return await controller.apply(
            decision: decision,
            snapshot: snapshot,
            thresholds: thresholds,
            protectionEnabled: protectionEnabled
        )
    }
}

private struct IntelControllerError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
