import Foundation

public protocol DiagnosticsProviding: Sendable {
    func run(snapshot: BatterySnapshot) async -> [DiagnosticCheck]
}

public actor SystemDiagnosticsService: DiagnosticsProviding {
    private let runner: any CommandRunning
    private let battPath: String?
    private let operatingSystemVersion: OperatingSystemVersion
    private let applicationPath: String

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        battPath: String? = SystemChargeController.installedBattPath,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        applicationPath: String = Bundle.main.bundlePath
    ) {
        self.runner = runner
        self.battPath = battPath
        self.operatingSystemVersion = operatingSystemVersion
        self.applicationPath = applicationPath
    }

    public func run(snapshot: BatterySnapshot) async -> [DiagnosticCheck] {
        var checks = [batteryCheck(snapshot), nativeLimitCheck(), installationCheck()]
        guard let battPath else {
            checks.append(DiagnosticCheck(id: "batt", title: "Charge controller",
                detail: "batt was not found. Orca is monitoring only.", level: .failed))
            return checks
        }

        let version = await runner.run(executable: battPath, arguments: ["version"], timeout: 3)
        checks.append(DiagnosticCheck(
            id: "batt-version", title: "batt installation",
            detail: version.succeeded
                ? version.output.trimmingCharacters(in: .whitespacesAndNewlines)
                : "The batt version could not be read.",
            level: version.succeeded ? .passed : .warning
        ))

        let response = await runner.run(executable: battPath, arguments: ["status", "--json"], timeout: 3)
        guard response.succeeded, let status = try? BattStatus.decode(response.output) else {
            checks.append(DiagnosticCheck(id: "daemon", title: "batt daemon",
                detail: response.timedOut ? "The daemon did not respond within 3 seconds." : "The daemon response could not be verified.",
                level: .failed))
            return checks
        }

        checks.append(DiagnosticCheck(
            id: "daemon", title: "batt daemon",
            detail: status.compatibility.chargingControl
                ? "Charging control is supported on this Mac."
                : "The backend reports that charging control is unsupported.",
            level: status.compatibility.chargingControl ? .passed : .failed
        ))
        let configuration = status.configuration
        checks.append(DiagnosticCheck(
            id: "limits", title: "Current charge limits",
            detail: configuration.enabled
                ? "Resume at \(configuration.lowerLimitPercent)%, stop at \(configuration.upperLimitPercent)%."
                : "Charge limiting is disabled.",
            level: configuration.enabled ? .passed : .information
        ))
        if let phase = status.calibration?.phase, phase.lowercased() != "idle" {
            checks.append(DiagnosticCheck(id: "calibration", title: "Calibration",
                detail: "batt calibration is in progress (\(phase)). Orca will not override it.", level: .warning))
        } else {
            checks.append(DiagnosticCheck(id: "calibration", title: "Calibration",
                detail: "No calibration is running.", level: .passed))
        }
        return checks
    }

    private func batteryCheck(_ snapshot: BatterySnapshot) -> DiagnosticCheck {
        let available = snapshot.powerSource != .unknown && (0...100).contains(snapshot.percentage)
        return DiagnosticCheck(id: "battery", title: "Battery data",
            detail: available ? "Battery telemetry is available." : "Reliable battery telemetry is unavailable.",
            level: available ? .passed : .failed)
    }

    private func nativeLimitCheck() -> DiagnosticCheck {
        let available = NativeChargeLimitSupport.isAvailable(on: operatingSystemVersion)
        return DiagnosticCheck(id: "native-limit", title: "macOS Charge Limit",
            detail: available
                ? "Available for limits from 80% to 100%. Avoid running two charge controllers at once."
                : "Not available on this macOS version; Orca can use batt instead.",
            level: available ? .information : .passed)
    }

    private func installationCheck() -> DiagnosticCheck {
        let installed = applicationPath == "/Applications/OrcaBatteryGuardian.app"
        return DiagnosticCheck(id: "installation", title: "Application location",
            detail: installed ? "Installed in Applications." : "Running outside Applications; Launch at Login may not work as expected.",
            level: installed ? .passed : .warning)
    }
}
