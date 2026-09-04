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
    private let architecture: MacArchitecture
    private let intelHelperPath: String?

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        battPath: String? = SystemChargeController.installedBattPath,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        applicationPath: String = Bundle.main.bundlePath,
        architecture: MacArchitecture = .current,
        intelHelperPath: String? = IntelBCLMSupport.isConfigured ? IntelBCLMSupport.helperPath : nil
    ) {
        self.runner = runner
        self.battPath = battPath
        self.operatingSystemVersion = operatingSystemVersion
        self.applicationPath = applicationPath
        self.architecture = architecture
        self.intelHelperPath = intelHelperPath
    }

    public func run(snapshot: BatterySnapshot, language: AppLanguage) async -> [DiagnosticCheck] {
        func text(_ key: String, _ arguments: CVarArg...) -> String {
            L10n.string(key, language: language, arguments: arguments)
        }
        var checks = [
            batteryCheck(snapshot, language: language),
            architectureCheck(language: language),
            nativeLimitCheck(language: language),
            installationCheck(language: language)
        ]
        if architecture == .intel {
            checks.append(await intelControllerCheck(language: language))
            return checks
        }
        guard let battPath else {
            checks.append(DiagnosticCheck(id: "batt", title: text("Charge controller"),
                detail: architecture == .intel
                    ? text("Intel monitoring mode. Battery data, history, benchmark, and CLI remain available; hardware charge control is disabled.")
                    : text("batt was not found. Orca is monitoring only."),
                level: architecture == .intel ? .information : .failed))
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

    private func intelControllerCheck(language: AppLanguage) async -> DiagnosticCheck {
        guard IntelBCLMSupport.supports(architecture, osVersion: operatingSystemVersion) else {
            return DiagnosticCheck(
                id: "intel-controller",
                title: L10n.string("Intel charge controller", language: language),
                detail: L10n.string("BCLM writes are blocked on this macOS version. Orca will not ask you to disable SIP.", language: language),
                level: .failed
            )
        }
        guard let intelHelperPath else {
            return DiagnosticCheck(
                id: "intel-controller",
                title: L10n.string("Intel charge controller", language: language),
                detail: L10n.string("The Orca BCLM helper is not installed. Hardware charge control is unavailable.", language: language),
                level: .warning
            )
        }
        let response = await runner.run(executable: intelHelperPath, arguments: ["read"], timeout: 3)
        let value = Int(response.output.trimmingCharacters(in: .whitespacesAndNewlines))
        guard response.succeeded, let value, (50...100).contains(value) else {
            return DiagnosticCheck(
                id: "intel-controller",
                title: L10n.string("Intel charge controller", language: language),
                detail: L10n.string("The Orca BCLM helper did not return a valid charge limit.", language: language),
                level: .failed
            )
        }
        return DiagnosticCheck(
            id: "intel-controller",
            title: L10n.string("Intel charge controller", language: language),
            detail: L10n.string("Verified Intel BCLM upper limit: %d%%.", language: language, value),
            level: .passed
        )
    }

    private func batteryCheck(_ snapshot: BatterySnapshot, language: AppLanguage) -> DiagnosticCheck {
        let available = snapshot.powerSource != .unknown && (0...100).contains(snapshot.percentage)
        return DiagnosticCheck(id: "battery", title: L10n.string("Battery data", language: language),
            detail: available ? L10n.string("Battery telemetry is available.", language: language) : L10n.string("Reliable battery telemetry is unavailable.", language: language),
            level: available ? .passed : .failed)
    }

    private func nativeLimitCheck(language: AppLanguage) -> DiagnosticCheck {
        let available = NativeChargeLimitSupport.isAvailable(on: operatingSystemVersion, architecture: architecture)
        return DiagnosticCheck(id: "native-limit", title: L10n.string("macOS Charge Limit", language: language),
            detail: available
                ? L10n.string("Available for limits from 80% to 100%. Avoid running two charge controllers at once.", language: language)
                : architecture == .intel
                    ? L10n.string("Apple's native charge limit is unavailable on Intel Macs.", language: language)
                    : L10n.string("Not available on this macOS version; Orca can use batt instead.", language: language),
            level: available ? .information : .passed)
    }

    private func architectureCheck(language: AppLanguage) -> DiagnosticCheck {
        let detail: String
        let level: DiagnosticLevel
        switch architecture {
        case .appleSilicon:
            detail = L10n.string("Apple Silicon detected. Monitoring and verified batt charge control are available.", language: language)
            level = .passed
        case .intel:
            if IntelBCLMSupport.supports(architecture, osVersion: operatingSystemVersion), intelHelperPath != nil {
                detail = L10n.string("Intel x86_64 detected. The BCLM charge controller is configured.", language: language)
                level = .passed
            } else {
                detail = L10n.string("Intel x86_64 detected. Monitoring is available; BCLM setup is required for hardware charge control.", language: language)
                level = .information
            }
        case .unknown:
            detail = L10n.string("Unknown Mac architecture. Hardware charge control is disabled.", language: language)
            level = .warning
        }
        return DiagnosticCheck(id: "architecture", title: L10n.string("Architecture", language: language), detail: detail, level: level)
    }

    private func installationCheck(language: AppLanguage) -> DiagnosticCheck {
        let installed = applicationPath == "/Applications/OrcaBatteryGuardian.app"
        return DiagnosticCheck(id: "installation", title: L10n.string("Application location", language: language),
            detail: installed ? L10n.string("Installed in Applications.", language: language) : L10n.string("Running outside Applications; Launch at Login may not work as expected.", language: language),
            level: installed ? .passed : .warning)
    }
}
