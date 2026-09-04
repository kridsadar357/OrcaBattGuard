import Foundation

public protocol DiagnosticsProviding: Sendable {
    func run(snapshot: BatterySnapshot, language: AppLanguage) async -> [DiagnosticCheck]
}

public extension DiagnosticsProviding {
    func run(snapshot: BatterySnapshot) async -> [DiagnosticCheck] {
        await run(snapshot: snapshot, language: .english)
    }
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

    public func run(snapshot: BatterySnapshot, language: AppLanguage) async -> [DiagnosticCheck] {
        func text(_ key: String, _ arguments: CVarArg...) -> String {
            L10n.string(key, language: language, arguments: arguments)
        }
        var checks = [batteryCheck(snapshot, language: language), nativeLimitCheck(language: language), installationCheck(language: language)]
        guard let battPath else {
            checks.append(DiagnosticCheck(id: "batt", title: text("Charge controller"),
                detail: text("batt was not found. Orca is monitoring only."), level: .failed))
            return checks
        }

        let version = await runner.run(executable: battPath, arguments: ["version"], timeout: 3)
        checks.append(DiagnosticCheck(
            id: "batt-version", title: text("batt installation"),
            detail: version.succeeded
                ? version.output.trimmingCharacters(in: .whitespacesAndNewlines)
                : text("The batt version could not be read."),
            level: version.succeeded ? .passed : .warning
        ))

        let response = await runner.run(executable: battPath, arguments: ["status", "--json"], timeout: 3)
        guard response.succeeded, let status = try? BattStatus.decode(response.output) else {
            checks.append(DiagnosticCheck(id: "daemon", title: text("batt daemon"),
                detail: response.timedOut ? text("The daemon did not respond within 3 seconds.") : text("The daemon response could not be verified."),
                level: .failed))
            return checks
        }

        checks.append(DiagnosticCheck(
            id: "daemon", title: text("batt daemon"),
            detail: status.compatibility.chargingControl
                ? text("Charging control is supported on this Mac.")
                : text("The backend reports that charging control is unsupported."),
            level: status.compatibility.chargingControl ? .passed : .failed
        ))
        let configuration = status.configuration
        checks.append(DiagnosticCheck(
            id: "limits", title: text("Current charge limits"),
            detail: configuration.enabled
                ? text("Resume at %d%%, stop at %d%%.", configuration.lowerLimitPercent, configuration.upperLimitPercent)
                : text("Charge limiting is disabled."),
            level: configuration.enabled ? .passed : .information
        ))
        if let phase = status.calibration?.phase, phase.lowercased() != "idle" {
            checks.append(DiagnosticCheck(id: "calibration", title: text("Calibration"),
                detail: text("batt calibration is in progress (%@). Orca will not override it.", phase), level: .warning))
        } else {
            checks.append(DiagnosticCheck(id: "calibration", title: text("Calibration"),
                detail: text("No calibration is running."), level: .passed))
        }
        return checks
    }

    private func batteryCheck(_ snapshot: BatterySnapshot, language: AppLanguage) -> DiagnosticCheck {
        let available = snapshot.powerSource != .unknown && (0...100).contains(snapshot.percentage)
        return DiagnosticCheck(id: "battery", title: L10n.string("Battery data", language: language),
            detail: available ? L10n.string("Battery telemetry is available.", language: language) : L10n.string("Reliable battery telemetry is unavailable.", language: language),
            level: available ? .passed : .failed)
    }

    private func nativeLimitCheck(language: AppLanguage) -> DiagnosticCheck {
        let available = NativeChargeLimitSupport.isAvailable(on: operatingSystemVersion)
        return DiagnosticCheck(id: "native-limit", title: L10n.string("macOS Charge Limit", language: language),
            detail: available
                ? L10n.string("Available for limits from 80% to 100%. Avoid running two charge controllers at once.", language: language)
                : L10n.string("Not available on this macOS version; Orca can use batt instead.", language: language),
            level: available ? .information : .passed)
    }

    private func installationCheck(language: AppLanguage) -> DiagnosticCheck {
        let installed = applicationPath == "/Applications/OrcaBatteryGuardian.app"
        return DiagnosticCheck(id: "installation", title: L10n.string("Application location", language: language),
            detail: installed ? L10n.string("Installed in Applications.", language: language) : L10n.string("Running outside Applications; Launch at Login may not work as expected.", language: language),
            level: installed ? .passed : .warning)
    }
}
