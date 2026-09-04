import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

private enum GuardianPalette {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.066)
    static let surface = Color(red: 0.095, green: 0.102, blue: 0.112)
    static let raised = Color(red: 0.125, green: 0.132, blue: 0.143)
    static let stroke = Color.white.opacity(0.09)
    static let accent = Color(red: 0.26, green: 0.84, blue: 0.68)
    static let cyan = Color(red: 0.25, green: 0.72, blue: 0.88)
    static let warning = Color(red: 0.96, green: 0.64, blue: 0.22)
}

private enum GuardianFontWeight {
    case regular
    case medium
    case semibold
    case bold

    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var sarabunName: String {
        switch self {
        case .regular: "Sarabun-Regular"
        case .medium: "Sarabun-Medium"
        case .semibold: "Sarabun-SemiBold"
        case .bold: "Sarabun-Bold"
        }
    }
}

private extension AppLanguage {
    func uiFont(_ style: Font.TextStyle, weight: GuardianFontWeight = .regular) -> Font {
        guard self == .thai else { return .system(style, weight: weight.swiftUIWeight) }
        return .custom(weight.sarabunName, size: baseSize(for: style), relativeTo: style)
    }

    func uiFont(size: CGFloat, weight: GuardianFontWeight = .regular) -> Font {
        guard self == .thai else { return .system(size: size, weight: weight.swiftUIWeight) }
        return .custom(weight.sarabunName, size: size)
    }

    private func baseSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

private struct GuardianLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.english
}

private extension EnvironmentValues {
    var guardianLanguage: AppLanguage {
        get { self[GuardianLanguageKey.self] }
        set { self[GuardianLanguageKey.self] = newValue }
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case benchmark = "Benchmark"
    case activity = "Activity"
    case settings = "Settings"

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        L10n.string(rawValue, language: language)
    }
}

public struct ContentView: View {
    @ObservedObject private var engine: GuardianEngine
    @ObservedObject private var settings: GuardianSettings
    @State private var section: DashboardSection = .overview
    @State private var benchmarkPeriod: BenchmarkPeriod = .thirtyDays
    @State private var benchmarkMessage: String?
    @State private var activityMessage: String?
    @State private var activityExportFailed = false
    @State private var showsBenchmarkReset = false
    @State private var showsCalibrationStart = false

    public init(engine: GuardianEngine) {
        self.engine = engine
        settings = engine.settings
    }

    public var body: some View {
        VStack(spacing: 0) {
            appHeader
            sectionPicker
            Divider().overlay(GuardianPalette.stroke)

            Group {
                switch section {
                case .overview:
                    overview
                case .benchmark:
                    benchmark
                case .activity:
                    activity
                case .settings:
                    settingsView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        .frame(width: 440, height: 620)
        .background(GuardianPalette.background)
        .preferredColorScheme(.dark)
        .environment(\.locale, language.locale)
        .environment(\.guardianLanguage, language)
        .font(language.uiFont(.body))
        .confirmationDialog(
            t("Start a new benchmark?"),
            isPresented: $showsBenchmarkReset,
            titleVisibility: .visible
        ) {
            Button(t("Reset Baseline"), role: .destructive) {
                Task {
                    await engine.resetBenchmark()
                    benchmarkMessage = t("New baseline saved")
                }
            }
        } message: {
            Text(t("Existing daily benchmark history will be replaced with the current battery reading."))
        }
        .confirmationDialog(
            t("Start battery calibration?"),
            isPresented: $showsCalibrationStart,
            titleVisibility: .visible
        ) {
            Button(t("Start Calibration"), role: .destructive) {
                Task { await engine.performCalibration(.start) }
            }
        } message: {
            Text(t("Calibration intentionally discharges and fully charges the battery. Keep the Mac awake, plugged in, and the lid open until it finishes."))
        }
        .task {
            await engine.refreshCalibrationStatus()
            await engine.checkForUpdates(force: false)
        }
    }

    private var appHeader: some View {
        HStack(spacing: 13) {
            OrcaMascotView(size: 72)

            VStack(alignment: .leading, spacing: 2) {
                Text("Orca")
                    .font(language.uiFont(.title2, weight: .bold))
                Text(t("Battery Guardian"))
                    .font(language.uiFont(.callout, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(t(protectionControlsEnabled ? "Protection" : "Monitoring"))
                    .font(language.uiFont(.caption))
                    .foregroundStyle(.secondary)
                Toggle(t("Battery protection"), isOn: protectionBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(GuardianPalette.accent)
                    .disabled(!protectionControlsEnabled)
                    .help(t("Turn battery protection on or off"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var sectionPicker: some View {
        Picker(t("Section"), selection: $section) {
            ForEach(DashboardSection.allCases) { item in
                Text(item.title(language: language)).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    private var overview: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                statusPanel
                modeSelector
                temporaryFullChargeControl
                ThresholdRangeView(thresholds: engine.effectiveThresholds, language: language)
                metricGrid
                controlStatus
            }
            .padding(18)
        }
    }

    private var statusPanel: some View {
        HStack(spacing: 18) {
            BatteryRingView(
                percentage: engine.snapshot.percentage,
                color: statusColor(for: engine.decision.state),
                language: language
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor(for: engine.decision.state))
                        .frame(width: 8, height: 8)
                    Text(engine.decision.statusText)
                        .font(language.uiFont(.title3, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(engine.decision.reason)
                    .font(language.uiFont(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Label(engine.snapshot.powerSource.title(language: language), systemImage: powerIcon)
                    Label(temperatureText, systemImage: "thermometer.medium")
                }
                .font(language.uiFont(.caption, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GuardianPalette.stroke, lineWidth: 1)
        }
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(t("Charge profile"))
                    .font(language.uiFont(.headline, weight: .semibold))
                Spacer()
                Text(engine.effectiveThresholds.rangeText)
                    .font(language.uiFont(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(GuardianPalette.accent)
            }

            Picker(t("Charge profile"), selection: modeBinding) {
                ForEach(GuardianMode.allCases) { mode in
                    Text(shortTitle(for: mode))
                        .tag(mode)
                        .help("\(mode.title(language: language)), \(mode.subtitle(language: language))")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var temporaryFullChargeControl: some View {
        HStack(spacing: 10) {
            Image(systemName: settings.isChargeToFullActive ? "bolt.badge.clock.fill" : "bolt.badge.clock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(settings.isChargeToFullActive ? GuardianPalette.accent : GuardianPalette.cyan)
                .frame(width: 22)

            if let until = settings.chargeToFullUntil, settings.isChargeToFullActive {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Charging to 100%"))
                        .font(language.uiFont(.caption, weight: .semibold))
                    Text(timerInterval: Date()...until, countsDown: true)
                        .font(language.uiFont(.caption2).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: engine.cancelTemporaryFullCharge) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(t("Cancel temporary full charge"))
            } else {
                Text(t("Temporary full charge"))
                    .font(language.uiFont(.caption, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(FullChargeDuration.allCases) { duration in
                        Button(duration.title(language: language)) { engine.beginTemporaryFullCharge(duration) }
                    }
                } label: {
                    Label(t("Charge to 100%"), systemImage: "battery.100percent")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!settings.protectionEnabled || !protectionControlsEnabled)
                .help(settings.protectionEnabled ? t("Temporarily allow charging to 100%") : t("Turn on Battery Protection first"))
            }
        }
        .padding(11)
        .background(GuardianPalette.raised.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            MetricTile(title: t("Power"), value: engine.snapshot.powerSource.title(language: language), icon: powerIcon, color: GuardianPalette.cyan)
            MetricTile(title: t("State"), value: engine.snapshot.chargingDescription(language: language), icon: "bolt.fill", color: statusColor(for: engine.decision.state))
            MetricTile(title: t("Temperature"), value: temperatureText, icon: "thermometer.medium", color: temperatureColor)
            MetricTile(title: t("Health"), value: localizedHealth, icon: "heart.fill", color: GuardianPalette.accent)
            MetricTile(title: t("Cycles"), value: engine.snapshot.cycleCount.map(String.init) ?? t("Unavailable"), icon: "arrow.triangle.2.circlepath", color: GuardianPalette.cyan)
            MetricTile(title: t("Control"), value: controlValue, icon: "shield.lefthalf.filled", color: controlColor)
        }
    }

    private var controlStatus: some View {
        HStack(spacing: 10) {
            Image(systemName: controlIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(controlColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(controlTitle)
                    .font(language.uiFont(.caption, weight: .semibold))
                Text(controlDetail)
                    .font(language.uiFont(.caption2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(11)
        .background(GuardianPalette.raised.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Status history"))
                        .font(language.uiFont(.headline, weight: .semibold))
                    Text(t("Recent activity saved on this Mac"))
                        .font(language.uiFont(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("\(engine.events.count)")
                        .font(language.uiFont(.title3, weight: .semibold).monospacedDigit())
                        .foregroundStyle(GuardianPalette.cyan)
                    Menu {
                        Button { exportActivity(format: "csv") } label: {
                            Label(t("Export CSV"), systemImage: "tablecells")
                        }
                        Button { exportActivity(format: "json") } label: {
                            Label(t("Export JSON"), systemImage: "curlybraces")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(engine.events.isEmpty)
                    .help(t("Export activity history"))
                }
            }

            if let activityMessage {
                Label(activityMessage, systemImage: activityExportFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(language.uiFont(.caption))
                    .foregroundStyle(activityExportFailed ? GuardianPalette.warning : GuardianPalette.accent)
            }

            if let error = engine.historyError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(language.uiFont(.caption))
                    .foregroundStyle(GuardianPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if engine.events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(t("No state changes yet"))
                        .font(language.uiFont(.callout, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(engine.events) { event in
                            EventRow(event: event, language: language)
                            Divider().overlay(GuardianPalette.stroke)
                        }
                    }
                }
                .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(GuardianPalette.stroke, lineWidth: 1)
                }
            }
        }
        .padding(18)
    }

    private var benchmark: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t("Battery benchmark"))
                            .font(language.uiFont(.headline, weight: .semibold))
                        if let report = engine.benchmarkReport {
                            Text(t("Tracking since %@", localizedDate(report.baseline.date)))
                                .font(language.uiFont(.caption))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(t("Preparing the first daily summary"))
                                .font(language.uiFont(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let report = engine.benchmarkReport {
                        Menu {
                            Button {
                                exportBenchmark(report)
                            } label: {
                                Label(t("Export CSV"), systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) {
                                showsBenchmarkReset = true
                            } label: {
                                Label(t("Reset Baseline"), systemImage: "arrow.counterclockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help(t("Benchmark actions"))
                    }
                }

                Picker(t("Benchmark period"), selection: $benchmarkPeriod) {
                    ForEach(BenchmarkPeriod.allCases) { period in
                        Text(t(period.title)).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let error = engine.benchmarkError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(language.uiFont(.caption))
                        .foregroundStyle(GuardianPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message = benchmarkMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(language.uiFont(.caption))
                        .foregroundStyle(GuardianPalette.accent)
                }

                if let report = engine.benchmarkReport {
                    let summary = report.summary(for: benchmarkPeriod)
                    benchmarkMetrics(summary)
                    BatteryCapacityChart(days: report.days, period: benchmarkPeriod, language: language)
                    BenchmarkComparisonTable(
                        title: t(benchmarkPeriod.title),
                        rows: benchmarkRows(report: report, summary: summary),
                        language: language
                    )
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                        Text(t("Daily summaries stay on this Mac. Capacity and health are estimates reported by the battery controller."))
                    }
                    .font(language.uiFont(.caption2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(t("Collecting baseline"))
                            .font(language.uiFont(.callout, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(18)
        }
    }

    private func benchmarkMetrics(_ summary: BatteryBenchmarkSummary) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            BenchmarkMetricTile(
                title: t("Health estimate"),
                value: formattedPercent(summary.currentHealthPercentage),
                detail: capacityChangeText(summary),
                icon: "heart.fill",
                color: GuardianPalette.accent
            )
            BenchmarkMetricTile(
                title: t("Full capacity"),
                value: formattedCapacity(summary.currentFullChargeCapacityMah),
                detail: t("Current reading"),
                icon: "battery.75percent",
                color: GuardianPalette.cyan
            )
            BenchmarkMetricTile(
                title: t("Protected time"),
                value: formattedPercent(summary.protectedPercentage),
                detail: t(summary.daysCollected == 1 ? "%d day collected" : "%d days collected", summary.daysCollected),
                icon: "checkmark.shield.fill",
                color: GuardianPalette.accent
            )
            BenchmarkMetricTile(
                title: t("Above 80%"),
                value: formattedDuration(summary.above80Seconds),
                detail: t("Within %@", t(benchmarkPeriod.title)),
                icon: "gauge.with.dots.needle.67percent",
                color: summary.above80Seconds > 0 ? GuardianPalette.warning : GuardianPalette.cyan
            )
        }
    }

    private func benchmarkRows(
        report: BatteryBenchmarkReport,
        summary: BatteryBenchmarkSummary
    ) -> [BenchmarkComparisonRow] {
        let baseline = report.baseline
        return [
            BenchmarkComparisonRow(
                metric: t("Full capacity"),
                baseline: formattedCapacity(baseline.fullChargeCapacityMah),
                result: formattedCapacity(summary.currentFullChargeCapacityMah),
                change: signedDifference(summary.currentFullChargeCapacityMah, baseline.fullChargeCapacityMah, suffix: " mAh")
            ),
            BenchmarkComparisonRow(
                metric: t("Health estimate"),
                baseline: formattedPercent(baseline.healthPercentage),
                result: formattedPercent(summary.currentHealthPercentage),
                change: signedDifference(summary.currentHealthPercentage, baseline.healthPercentage, suffix: " pp")
            ),
            BenchmarkComparisonRow(
                metric: t("Cycle count"),
                baseline: baseline.cycleCount.map(String.init) ?? "-",
                result: summary.currentCycleCount.map(String.init) ?? "-",
                change: signedDifference(summary.currentCycleCount, baseline.cycleCount)
            ),
            BenchmarkComparisonRow(
                metric: t("Avg temperature"),
                baseline: formattedTemperature(baseline.temperatureC),
                result: formattedTemperature(summary.averageTemperatureC),
                change: signedDifference(summary.averageTemperatureC, baseline.temperatureC, suffix: " C")
            ),
            BenchmarkComparisonRow(metric: t("Time above 80%"), baseline: "-", result: formattedDuration(summary.above80Seconds), change: "-"),
            BenchmarkComparisonRow(metric: t("Time at 38 C+"), baseline: "-", result: formattedDuration(summary.hotSeconds), change: "-"),
            BenchmarkComparisonRow(metric: t("Protected time"), baseline: "-", result: formattedPercent(summary.protectedPercentage), change: "-"),
            BenchmarkComparisonRow(metric: t("Control reliability"), baseline: "-", result: formattedPercent(summary.controllerReliabilityPercentage), change: "-")
        ]
    }

    private var settingsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                SettingsGroup(title: t("Language"), icon: "globe") {
                    Picker(t("App language"), selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.selectionTitle).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                SettingsGroup(title: t("Custom charge range"), icon: "slider.horizontal.3") {
                    HStack(spacing: 10) {
                        RangeStepper(title: t("Resume"), value: lowerBinding, range: 5...95)
                        RangeStepper(title: t("Stop"), value: upperBinding, range: 10...100)
                    }
                }

                SettingsGroup(title: t("Safety limits"), icon: "cross.case.fill") {
                    VStack(spacing: 10) {
                        Stepper(value: criticalBinding, in: 5...30, step: 1) {
                            SettingValueRow(title: t("Critical low"), value: "\(settings.customThresholds.criticalLow)%")
                        }
                        Stepper(value: temperatureBinding, in: 30...55, step: 1) {
                            SettingValueRow(title: t("Cooling pause"), value: "\(Int(settings.customThresholds.hotTemperatureC)) C")
                        }
                        Text(t("Resume after 5 minutes and 3 C below the pause temperature"))
                            .font(language.uiFont(.caption2))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SettingsGroup(title: t("Preferences"), icon: "switch.2") {
                    VStack(spacing: 12) {
                        SettingToggle(
                            title: t("Notifications"),
                            detail: t("Alert when protection changes state"),
                            isOn: $settings.notificationsEnabled
                        )
                        SettingToggle(
                            title: t("Launch at login"),
                            detail: t("Keep protection available after restart"),
                            isOn: $settings.launchAtLogin
                        )
                        SettingToggle(
                            title: t("Simulation mode"),
                            detail: t("Test the dashboard without changing hardware"),
                            isOn: simulationBinding
                        )
                    }
                }

                SettingsGroup(title: t("Charge controller"), icon: "cpu") {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(controlColor)
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(engine.chargeControlResult.backendName) - \(controlValue)")
                                .font(language.uiFont(.caption, weight: .semibold))
                            Text(settings.simulationMode ? t("Simulation is isolated from hardware charge control.") : engine.chargeControlResult.message)
                                .font(language.uiFont(.caption2))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let verifiedAt = engine.chargeControlResult.verifiedAt {
                                Text(t("Verified %@", localizedDate(verifiedAt, includesTime: true)))
                                    .font(language.uiFont(.caption2).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    if SystemChargeController.installedBattPath == nil {
                        if MacArchitecture.current == .intel {
                            Label {
                                Text(t("Intel Macs run in monitoring mode because the verified batt backend supports Apple Silicon only."))
                                    .font(language.uiFont(.caption2))
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "info.circle")
                            }
                        } else {
                            HStack {
                                Button(action: openBattGuide) {
                                    Label(t("Installation Guide"), systemImage: "safari")
                                }
                                Button(action: copyBattInstallCommand) {
                                    Label(t("Copy Install Command"), systemImage: "doc.on.doc")
                                }
                            }
                        }
                    }
                }

                SettingsGroup(title: t("Battery calibration"), icon: "gauge.with.dots.needle.bottom.50percent") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localizedCalibrationPhase)
                                    .font(language.uiFont(.caption, weight: .semibold))
                                Text(calibrationDetail)
                                    .font(language.uiFont(.caption2))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if engine.isPerformingMaintenance {
                                ProgressView().controlSize(.small)
                            } else {
                                Button {
                                    Task { await engine.refreshCalibrationStatus() }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .help(t("Refresh calibration status"))
                            }
                        }

                        HStack(spacing: 8) {
                            if engine.calibrationStatus.isRunning {
                                Button {
                                    Task {
                                        await engine.performCalibration(engine.calibrationStatus.isPaused ? .resume : .pause)
                                    }
                                } label: {
                                    Label(
                                        engine.calibrationStatus.isPaused ? t("Resume") : t("Pause"),
                                        systemImage: engine.calibrationStatus.isPaused ? "play.fill" : "pause.fill"
                                    )
                                }
                                .disabled(!engine.calibrationStatus.isPaused && !engine.calibrationStatus.canPause)

                                Button(role: .destructive) {
                                    Task { await engine.performCalibration(.cancel) }
                                } label: {
                                    Label(t("Cancel"), systemImage: "xmark")
                                }
                                .disabled(!engine.calibrationStatus.canCancel)
                            } else {
                                Button {
                                    showsCalibrationStart = true
                                } label: {
                                    Label(t("Start Calibration"), systemImage: "play.fill")
                                }
                                .disabled(
                                    !engine.calibrationStatus.isAvailable || settings.simulationMode ||
                                    engine.snapshot.powerSource != .acPower
                                )
                                .help(
                                    engine.snapshot.powerSource == .acPower
                                        ? t("Start a verified batt calibration workflow")
                                        : t("Connect a power adapter before starting calibration")
                                )
                            }
                        }
                    }
                }

                SettingsGroup(title: t("Software updates"), icon: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingToggle(
                            title: t("Check automatically"),
                            detail: t("Check GitHub Releases at most once per day"),
                            isOn: $settings.checksForUpdates
                        )
                        HStack {
                            Text(updateDetail)
                                .font(language.uiFont(.caption2))
                                .foregroundStyle(updateColor)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if engine.updateStatus.state == .checking {
                                ProgressView().controlSize(.small)
                            } else {
                                Button {
                                    Task { await engine.checkForUpdates() }
                                } label: {
                                    Label(t("Check Now"), systemImage: "arrow.clockwise")
                                }
                            }
                            if engine.updateStatus.state == .updateAvailable,
                               let releaseURL = engine.updateStatus.releaseURL {
                                Button {
                                    NSWorkspace.shared.open(releaseURL)
                                } label: {
                                    Label(t("Open Release"), systemImage: "arrow.up.forward.app")
                                }
                            }
                        }
                    }
                }

                SettingsGroup(title: t("Command line tool"), icon: "terminal") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("orca")
                                .font(language.uiFont(.caption, weight: .semibold).monospaced())
                            Text(t("Read status, diagnostics, history, and benchmark data from Terminal."))
                                .font(language.uiFont(.caption2))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: copyCLIInstallCommand) {
                            Label(t("Copy Install Command"), systemImage: "doc.on.doc")
                        }
                    }
                }

                if engine.isNativeChargeLimitAvailable {
                    SettingsGroup(title: t("macOS Charge Limit"), icon: "apple.logo") {
                        HStack(spacing: 10) {
                            Label(t("Available · 80-100%"), systemImage: "checkmark.circle.fill")
                                .font(language.uiFont(.caption, weight: .medium))
                                .foregroundStyle(GuardianPalette.accent)
                            Spacer()
                            Button(action: useMacOSChargeLimit) {
                                Label(t("Use macOS Limit"), systemImage: "arrow.up.forward.app")
                            }
                            .help(t("Disable Orca control and open Battery Settings"))
                        }
                    }
                }

                SettingsGroup(title: t("Diagnostics"), icon: "stethoscope") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(diagnosticsSummary)
                                .font(language.uiFont(.caption))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                Task { await engine.runDiagnostics() }
                            } label: {
                                if engine.isRunningDiagnostics {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(t("Run"), systemImage: "play.fill")
                                }
                            }
                            .disabled(engine.isRunningDiagnostics)
                        }

                        ForEach(engine.diagnosticChecks) { check in
                            DiagnosticRow(check: check, language: language)
                            if check.id != engine.diagnosticChecks.last?.id {
                                Divider().overlay(GuardianPalette.stroke)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: controlIcon)
                .foregroundStyle(controlColor)
            Text(engine.protectionStatusText)
                .font(language.uiFont(.caption, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Text(engine.snapshot.timestamp, format: .dateTime.hour().minute().second())
                .font(language.uiFont(.caption2).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(GuardianPalette.surface.opacity(0.72))
        .overlay(alignment: .top) {
            Divider().overlay(GuardianPalette.stroke)
        }
    }

    private var modeBinding: Binding<GuardianMode> {
        Binding(
            get: { settings.mode },
            set: {
                settings.mode = $0
                engine.refresh()
            }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { settings.language },
            set: { newValue in
                settings.language = newValue
                benchmarkMessage = nil
                engine.refresh()
                if !engine.diagnosticChecks.isEmpty {
                    Task { await engine.runDiagnostics() }
                }
            }
        )
    }

    private var protectionBinding: Binding<Bool> {
        Binding(
            get: { settings.protectionEnabled },
            set: { engine.setProtectionEnabled($0) }
        )
    }

    private var protectionControlsEnabled: Bool {
        settings.simulationMode || MacArchitecture.current != .intel
    }

    private var simulationBinding: Binding<Bool> {
        Binding(
            get: { settings.simulationMode },
            set: {
                settings.simulationMode = $0
                engine.refresh()
            }
        )
    }

    private var lowerBinding: Binding<Int> {
        Binding(
            get: { settings.customThresholds.lower },
            set: { newValue in
                settings.mode = .custom
                settings.customThresholds.lower = min(newValue, settings.customThresholds.upper - 5)
                engine.refresh()
            }
        )
    }

    private var upperBinding: Binding<Int> {
        Binding(
            get: { settings.customThresholds.upper },
            set: { newValue in
                settings.mode = .custom
                settings.customThresholds.upper = max(newValue, settings.customThresholds.lower + 5)
                engine.refresh()
            }
        )
    }

    private var criticalBinding: Binding<Int> {
        Binding(
            get: { settings.customThresholds.criticalLow },
            set: {
                settings.customThresholds.criticalLow = $0
                engine.refresh()
            }
        )
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { settings.customThresholds.hotTemperatureC },
            set: {
                settings.customThresholds.hotTemperatureC = $0
                engine.refresh()
            }
        )
    }

    private var temperatureText: String {
        guard let temperature = engine.snapshot.temperatureC else { return t("Unavailable") }
        return "\(Int(temperature.rounded())) C"
    }

    private var localizedHealth: String {
        guard let health = engine.snapshot.health else { return t("Unavailable") }
        return t(health)
    }

    private var temperatureColor: Color {
        guard let temperature = engine.snapshot.temperatureC else { return .secondary }
        return temperature >= settings.activeThresholds.hotTemperatureC ? GuardianPalette.warning : GuardianPalette.accent
    }

    private var powerIcon: String {
        switch engine.snapshot.powerSource {
        case .acPower: "powerplug.fill"
        case .battery: "battery.75percent"
        case .unknown: "questionmark.circle"
        }
    }

    private var controlValue: String {
        if settings.simulationMode { return t("Simulation") }
        if engine.chargeControlResult.backendName == t("Checking") { return t("Checking") }
        return engine.isControlVerified ? t("Verified") : t("Unverified")
    }

    private var controlTitle: String {
        engine.protectionStatusText
    }

    private var controlDetail: String {
        if settings.simulationMode { return t("Live battery settings are not changed.") }
        return engine.chargeControlResult.message
    }

    private var controlIcon: String {
        if settings.simulationMode { return "testtube.2" }
        if settings.isChargeToFullActive { return "bolt.badge.clock.fill" }
        return engine.isControlVerified ? (engine.chargeControlResult.isLimitEnabled == true ? "checkmark.shield.fill" : "shield.slash") : "exclamationmark.shield.fill"
    }

    private var controlColor: Color {
        if settings.simulationMode { return GuardianPalette.cyan }
        if settings.isChargeToFullActive { return GuardianPalette.accent }
        return engine.isControlVerified ? (engine.chargeControlResult.isLimitEnabled == true ? GuardianPalette.accent : .secondary) : GuardianPalette.warning
    }

    private var diagnosticsSummary: String {
        guard !engine.diagnosticChecks.isEmpty else { return t("Not run yet") }
        let issues = engine.diagnosticChecks.filter { $0.level == .warning || $0.level == .failed }.count
        guard issues > 0 else { return t("All checks passed") }
        return t(issues == 1 ? "%d item needs attention" : "%d items need attention", issues)
    }

    private func openBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func useMacOSChargeLimit() {
        engine.switchToMacOSChargeLimit()
        openBatterySettings()
    }

    private func exportBenchmark(_ report: BatteryBenchmarkReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "Orca-Battery-Benchmark-\(date).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(report.csv.utf8).write(to: url, options: .atomic)
            benchmarkMessage = t("CSV exported")
        } catch {
            benchmarkMessage = t("Export failed: %@", error.localizedDescription)
        }
    }

    private func exportActivity(format: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "Orca-Activity-\(date).\(format)"
        panel.allowedContentTypes = format == "json" ? [.json] : [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = format == "json"
                ? try StatusHistoryExporter.json(engine.events)
                : Data(StatusHistoryExporter.csv(engine.events).utf8)
            try data.write(to: url, options: .atomic)
            activityMessage = t("Activity exported")
            activityExportFailed = false
        } catch {
            activityMessage = t("Export failed: %@", error.localizedDescription)
            activityExportFailed = true
        }
    }

    private func openBattGuide() {
        if let url = URL(string: "https://github.com/charlie0129/batt#installation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyBattInstallCommand() {
        copyToPasteboard("brew install batt")
    }

    private func copyCLIInstallCommand() {
        copyToPasteboard("mkdir -p \"$HOME/.local/bin\"; install -m 755 '/Applications/OrcaBatteryGuardian.app/Contents/MacOS/orca-battery' \"$HOME/.local/bin/orca\"; ln -sfn orca \"$HOME/.local/bin/orca-battery\"")
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var localizedCalibrationPhase: String {
        guard engine.calibrationStatus.isAvailable else { return t("Calibration unavailable") }
        if engine.calibrationStatus.isPaused { return t("Calibration paused") }
        return t(engine.calibrationStatus.phase)
    }

    private var calibrationDetail: String {
        if let message = engine.maintenanceMessage, !message.isEmpty { return message }
        if !engine.calibrationStatus.message.isEmpty { return t(engine.calibrationStatus.message) }
        return engine.calibrationStatus.isRunning
            ? t("Orca charge control is paused while batt manages calibration.")
            : t("A full calibration cycle can take several hours and adds battery wear.")
    }

    private var updateDetail: String {
        let status = engine.updateStatus
        switch status.state {
        case .notChecked: return t("Updates have not been checked yet.")
        case .checking: return t("Checking for updates...")
        case .upToDate: return t("Orca is up to date.")
        case .updateAvailable: return t("Version %@ is available.", status.latestVersion ?? "")
        case .noPublishedRelease: return t("No published releases are available yet.")
        case .failed: return t("Update check failed: %@", status.message)
        }
    }

    private var updateColor: Color {
        switch engine.updateStatus.state {
        case .updateAvailable: GuardianPalette.accent
        case .failed: GuardianPalette.warning
        default: .secondary
        }
    }

    private func formattedCapacity(_ value: Int?) -> String {
        value.map { "\($0.formatted(.number.locale(language.locale))) mAh" } ?? "-"
    }

    private func formattedPercent(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(value.formatted(.number.precision(.fractionLength(1)).locale(language.locale)))%"
    }

    private func formattedTemperature(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(value.formatted(.number.precision(.fractionLength(1)).locale(language.locale))) C"
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return t("0 min") }
        if seconds < 60 { return t("<1 min") }
        let minutes = Int(seconds / 60)
        guard minutes >= 60 else { return t("%d min", minutes) }
        return t("%d hr %d min", minutes / 60, minutes % 60)
    }

    private func signedDifference(_ current: Int?, _ baseline: Int?, suffix: String = "") -> String {
        guard let current, let baseline else { return "-" }
        let difference = current - baseline
        return "\(difference > 0 ? "+" : "")\(difference)\(suffix)"
    }

    private func signedDifference(_ current: Double?, _ baseline: Double?, suffix: String) -> String {
        guard let current, let baseline else { return "-" }
        let rawDifference = current - baseline
        let difference = abs(rawDifference) < 0.05 ? 0 : rawDifference
        let value = difference.formatted(.number.precision(.fractionLength(1)).locale(language.locale))
        return "\(difference > 0 ? "+" : "")\(value)\(suffix)"
    }

    private func capacityChangeText(_ summary: BatteryBenchmarkSummary) -> String {
        guard let baseline = engine.benchmarkReport?.baseline.fullChargeCapacityMah else {
            return t("Baseline pending")
        }
        return t("%@ from baseline", signedDifference(summary.currentFullChargeCapacityMah, baseline, suffix: " mAh"))
    }

    private func shortTitle(for mode: GuardianMode) -> String {
        mode == .maximumLife ? t("Max Life") : mode.title(language: language)
    }

    private var language: AppLanguage { settings.language }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, language: language, arguments: arguments)
    }

    private func localizedDate(_ value: Date, includesTime: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = includesTime ? .medium : .none
        return formatter.string(from: value)
    }
}

public struct MenuBarContentView: View {
    @ObservedObject private var engine: GuardianEngine
    @ObservedObject private var settings: GuardianSettings
    private let onOpen: () -> Void
    private let onRefresh: () -> Void
    private let onQuit: () -> Void

    public init(
        engine: GuardianEngine,
        onOpen: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.engine = engine
        settings = engine.settings
        self.onOpen = onOpen
        self.onRefresh = onRefresh
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                OrcaMascotView(size: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(engine.snapshot.percentage)%")
                        .font(language.uiFont(.title2, weight: .bold).monospacedDigit())
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(for: engine.decision.state))
                            .frame(width: 7, height: 7)
                        Text(engine.decision.statusText)
                            .font(language.uiFont(.callout, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(engine.snapshot.powerSource.title(language: language))
                        .font(language.uiFont(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ThresholdRangeView(thresholds: engine.effectiveThresholds, compact: true, language: language)

            HStack {
                Label(temperatureText, systemImage: "thermometer.medium")
                Spacer()
                Label(engine.effectiveModeTitle, systemImage: settings.isChargeToFullActive ? "bolt.badge.clock" : "slider.horizontal.3")
                    .lineLimit(1)
            }
            .font(language.uiFont(.caption, weight: .medium))
            .foregroundStyle(.secondary)

            Toggle(t("Battery protection"), isOn: protectionBinding)
                .toggleStyle(.switch)
                .tint(GuardianPalette.accent)
                .disabled(!protectionControlsEnabled)

            if let until = settings.chargeToFullUntil, settings.isChargeToFullActive {
                HStack {
                    Label(t("Charging to 100%"), systemImage: "battery.100percent")
                    Spacer()
                    Text(timerInterval: Date()...until, countsDown: true)
                        .monospacedDigit()
                    Button(action: engine.cancelTemporaryFullCharge) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(t("Cancel temporary full charge"))
                }
                .font(language.uiFont(.caption, weight: .medium))
                .foregroundStyle(GuardianPalette.accent)
            }

            Label(engine.protectionStatusText, systemImage: settings.simulationMode ? "testtube.2" : (engine.isControlVerified ? "shield.lefthalf.filled" : "exclamationmark.triangle"))
                .font(language.uiFont(.caption, weight: .medium))
                .foregroundStyle(settings.simulationMode ? GuardianPalette.cyan : (engine.isControlVerified ? GuardianPalette.accent : GuardianPalette.warning))
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(engine.chargeControlResult.message)

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Label(t("Open Dashboard"), systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(GuardianPalette.accent)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 20)
                }
                .buttonStyle(.bordered)
                .help(t("Refresh battery status"))

                Button(action: onQuit) {
                    Image(systemName: "power")
                        .frame(width: 20)
                }
                .buttonStyle(.bordered)
                .help(t("Quit Orca Battery Guardian"))
            }
        }
        .padding(16)
        .frame(width: 320)
        .foregroundStyle(Color.white)
        .background(GuardianPalette.background)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, language.locale)
        .environment(\.guardianLanguage, language)
        .font(language.uiFont(.body))
        .preferredColorScheme(.dark)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                engine.start()
            }
        }
    }

    private var protectionBinding: Binding<Bool> {
        Binding(
            get: { settings.protectionEnabled },
            set: { engine.setProtectionEnabled($0) }
        )
    }

    private var protectionControlsEnabled: Bool {
        settings.simulationMode || MacArchitecture.current != .intel
    }

    private var temperatureText: String {
        guard let temperature = engine.snapshot.temperatureC else { return t("No temperature") }
        return "\(Int(temperature.rounded())) C"
    }

    private var language: AppLanguage { settings.language }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, language: language, arguments: arguments)
    }
}

public struct MenuBarLabelView: View {
    private let percentage: Int

    public init(percentage: Int) {
        self.percentage = percentage
    }

    public var body: some View {
        HStack(spacing: 4) {
            OrcaMenuBarIconView()
            Text("\(percentage)%")
                .monospacedDigit()
        }
    }
}

private struct BatteryRingView: View {
    let percentage: Int
    let color: Color
    let language: AppLanguage

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.075), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.01, Double(percentage) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text("\(percentage)")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(L10n.string("PERCENT", language: language))
                    .font(language.uiFont(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 94, height: 94)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("Battery %d percent", language: language, percentage))
    }
}

private struct ThresholdRangeView: View {
    let thresholds: ChargeThresholds
    var compact = false
    let language: AppLanguage

    var body: some View {
        VStack(spacing: compact ? 7 : 9) {
            if !compact {
                HStack {
                    Label(t("Resume charging"), systemImage: "bolt.fill")
                    Spacer()
                    Label(t("Stop charging"), systemImage: "pause.fill")
                }
                .font(language.uiFont(.caption))
                .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let lowerX = width * CGFloat(thresholds.lower) / 100
                let upperX = width * CGFloat(thresholds.upper) / 100

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(GuardianPalette.accent)
                        .frame(width: max(4, upperX - lowerX))
                        .offset(x: lowerX)
                    Circle()
                        .fill(GuardianPalette.background)
                        .overlay(Circle().stroke(GuardianPalette.accent, lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, lowerX - 6))
                    Circle()
                        .fill(GuardianPalette.accent)
                        .frame(width: 12, height: 12)
                        .offset(x: min(width - 12, upperX - 6))
                }
            }
            .frame(height: 12)

            HStack {
                Text("\(thresholds.lower)%")
                Spacer()
                Text(t(compact ? "Target range" : "Protected range"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(thresholds.upper)%")
            }
            .font(language.uiFont(.caption, weight: .semibold).monospacedDigit())
        }
        .padding(compact ? 11 : 13)
        .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GuardianPalette.stroke, lineWidth: 1)
        }
    }

    private func t(_ key: String) -> String {
        L10n.string(key, language: language)
    }
}

private struct MetricTile: View {
    @Environment(\.guardianLanguage) private var language
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(height: 16)
            Text(title)
                .font(language.uiFont(.caption2))
                .foregroundStyle(.secondary)
            Text(value)
                .font(language.uiFont(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(10)
        .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GuardianPalette.stroke, lineWidth: 1)
        }
    }
}

private struct BenchmarkMetricTile: View {
    @Environment(\.guardianLanguage) private var language
    let title: String
    let value: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                Text(value)
                    .font(language.uiFont(.callout, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Text(title)
                .font(language.uiFont(.caption, weight: .medium))
            Text(detail)
                .font(language.uiFont(.caption2))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .padding(10)
        .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GuardianPalette.stroke, lineWidth: 1)
        }
    }
}

private struct BatteryCapacityChart: View {
    let days: [BatteryBenchmarkDay]
    let period: BenchmarkPeriod
    let language: AppLanguage

    private var points: [(date: Date, capacity: Int)] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let cutoff = calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: today) ?? today
        return days
            .filter { $0.date >= cutoff && $0.date <= today }
            .compactMap { day in day.endFullChargeCapacityMah.map { (day.date, $0) } }
    }

    private var capacityDomain: ClosedRange<Double> {
        let values = points.map { Double($0.capacity) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let margin = max(50, (high - low) * 0.2)
        return (low - margin)...(high + margin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(t("Capacity trend"), systemImage: "chart.xyaxis.line")
                    .font(language.uiFont(.caption, weight: .semibold))
                Spacer()
                Text(t(period.shortTitle))
                    .font(language.uiFont(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(GuardianPalette.cyan)
            }

            if points.count >= 2 {
                Chart(points, id: \.date) { point in
                    LineMark(
                        x: .value(t("Date"), point.date),
                        y: .value(t("Capacity"), point.capacity)
                    )
                    .foregroundStyle(GuardianPalette.cyan)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value(t("Date"), point.date),
                        y: .value(t("Capacity"), point.capacity)
                    )
                    .foregroundStyle(GuardianPalette.accent)
                }
                .chartYScale(domain: capacityDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(GuardianPalette.stroke)
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(GuardianPalette.stroke)
                        AxisValueLabel()
                    }
                }
                .frame(height: 118)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(GuardianPalette.cyan)
                    Text(t("The capacity trend appears after a second day is collected."))
                        .font(language.uiFont(.caption))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
        }
        .padding(12)
        .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GuardianPalette.stroke, lineWidth: 1)
        }
    }

    private func t(_ key: String) -> String {
        L10n.string(key, language: language)
    }
}

private struct BenchmarkComparisonRow: Identifiable {
    let id = UUID()
    let metric: String
    let baseline: String
    let result: String
    let change: String
}

private struct BenchmarkComparisonTable: View {
    let title: String
    let rows: [BenchmarkComparisonRow]
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("Metric")).frame(width: 112, alignment: .leading)
                Text(t("Baseline")).frame(maxWidth: .infinity, alignment: .trailing)
                Text(title).frame(maxWidth: .infinity, alignment: .trailing)
                Text(t("Change")).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(language.uiFont(.caption2, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)

            Divider().overlay(GuardianPalette.stroke)

            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Text(row.metric)
                        .frame(width: 112, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(row.baseline).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(row.result).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(row.change)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(row.change != "-" && row.change.hasPrefix("-") ? GuardianPalette.warning : .secondary)
                }
                .font(language.uiFont(.caption2).monospacedDigit())
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                if row.id != rows.last?.id {
                    Divider().overlay(GuardianPalette.stroke)
                }
            }
        }
        .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GuardianPalette.stroke, lineWidth: 1)
        }
    }

    private func t(_ key: String) -> String {
        L10n.string(key, language: language)
    }
}

private struct EventRow: View {
    let event: StatusEvent
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GuardianPalette.cyan)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.title)
                        .font(language.uiFont(.caption, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
                Text(localizedDate)
                    .font(language.uiFont(.caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(event.detail)
                    .font(language.uiFont(.caption2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    private var localizedDate: String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: event.date)
    }
}

private struct DiagnosticRow: View {
    let check: DiagnosticCheck
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(language.uiFont(.caption, weight: .semibold))
                Text(check.detail)
                    .font(language.uiFont(.caption2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var icon: String {
        switch check.level {
        case .passed: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch check.level {
        case .passed: GuardianPalette.accent
        case .information: GuardianPalette.cyan
        case .warning, .failed: GuardianPalette.warning
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    @Environment(\.guardianLanguage) private var language
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon)
                .font(language.uiFont(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GuardianPalette.stroke, lineWidth: 1)
        }
    }
}

private struct RangeStepper: View {
    @Environment(\.guardianLanguage) private var language
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range, step: 5) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(language.uiFont(.caption))
                    .foregroundStyle(.secondary)
                Text("\(value)%")
                    .font(language.uiFont(.title3, weight: .semibold).monospacedDigit())
            }
        }
        .padding(10)
        .background(GuardianPalette.raised, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SettingValueRow: View {
    @Environment(\.guardianLanguage) private var language
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(language.uiFont(.callout))
            Spacer()
            Text(value)
                .font(language.uiFont(.callout, weight: .semibold).monospacedDigit())
                .foregroundStyle(GuardianPalette.accent)
        }
    }
}

private struct SettingToggle: View {
    @Environment(\.guardianLanguage) private var language
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(language.uiFont(.callout))
                Text(detail)
                    .font(language.uiFont(.caption2))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(GuardianPalette.accent)
    }
}

private extension ChargeThresholds {
    var rangeText: String { "\(lower)-\(upper)%" }
}

private func statusColor(for state: ChargingState) -> Color {
    switch state {
    case .charging, .safetyCharge:
        GuardianPalette.accent
    case .holding:
        GuardianPalette.cyan
    case .coolingPause:
        GuardianPalette.warning
    case .discharging:
        Color.yellow
    case .unknown:
        Color.secondary
    }
}
