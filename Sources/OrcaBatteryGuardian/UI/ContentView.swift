import SwiftUI

private enum GuardianPalette {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.066)
    static let surface = Color(red: 0.095, green: 0.102, blue: 0.112)
    static let raised = Color(red: 0.125, green: 0.132, blue: 0.143)
    static let stroke = Color.white.opacity(0.09)
    static let accent = Color(red: 0.26, green: 0.84, blue: 0.68)
    static let cyan = Color(red: 0.25, green: 0.72, blue: 0.88)
    static let warning = Color(red: 0.96, green: 0.64, blue: 0.22)
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Activity"
    case settings = "Settings"

    var id: String { rawValue }
}

public struct ContentView: View {
    @ObservedObject private var engine: GuardianEngine
    @ObservedObject private var settings: GuardianSettings
    @State private var section: DashboardSection = .overview

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
    }

    private var appHeader: some View {
        HStack(spacing: 13) {
            OrcaMascotView(size: 72)

            VStack(alignment: .leading, spacing: 2) {
                Text("Orca")
                    .font(.title2.weight(.bold))
                Text("Battery Guardian")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text("Protection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Battery protection", isOn: protectionBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(GuardianPalette.accent)
                    .help("Turn battery protection on or off")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $section) {
            ForEach(DashboardSection.allCases) { item in
                Text(item.rawValue).tag(item)
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
                ThresholdRangeView(thresholds: settings.activeThresholds)
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
                color: statusColor(for: engine.decision.state)
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor(for: engine.decision.state))
                        .frame(width: 8, height: 8)
                    Text(engine.decision.statusText)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Text(engine.decision.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Label(engine.snapshot.powerSource.rawValue, systemImage: powerIcon)
                    Label(temperatureText, systemImage: "thermometer.medium")
                }
                .font(.caption.weight(.medium))
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
                Text("Charge profile")
                    .font(.headline)
                Spacer()
                Text(settings.activeThresholds.rangeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(GuardianPalette.accent)
            }

            Picker("Charge profile", selection: modeBinding) {
                ForEach(GuardianMode.allCases) { mode in
                    Text(shortTitle(for: mode))
                        .tag(mode)
                        .help("\(mode.title), \(mode.subtitle)")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            MetricTile(title: "Power", value: engine.snapshot.powerSource.rawValue, icon: powerIcon, color: GuardianPalette.cyan)
            MetricTile(title: "State", value: engine.decision.state.rawValue, icon: "bolt.fill", color: statusColor(for: engine.decision.state))
            MetricTile(title: "Temperature", value: temperatureText, icon: "thermometer.medium", color: temperatureColor)
            MetricTile(title: "Health", value: engine.snapshot.health ?? "Unavailable", icon: "heart.fill", color: GuardianPalette.accent)
            MetricTile(title: "Cycles", value: engine.snapshot.cycleCount.map(String.init) ?? "Unavailable", icon: "arrow.triangle.2.circlepath", color: GuardianPalette.cyan)
            MetricTile(title: "Control", value: controlValue, icon: "shield.lefthalf.filled", color: controlColor)
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
                    .font(.caption.weight(.semibold))
                Text(controlDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                    Text("Status history")
                        .font(.headline)
                    Text("State changes from this session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(engine.events.count)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(GuardianPalette.cyan)
            }

            if engine.events.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No state changes yet")
                        .font(.callout.weight(.medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(engine.events) { event in
                            EventRow(event: event)
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

    private var settingsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                SettingsGroup(title: "Custom charge range", icon: "slider.horizontal.3") {
                    HStack(spacing: 10) {
                        RangeStepper(title: "Resume", value: lowerBinding, range: 5...95)
                        RangeStepper(title: "Stop", value: upperBinding, range: 10...100)
                    }
                }

                SettingsGroup(title: "Safety limits", icon: "cross.case.fill") {
                    VStack(spacing: 10) {
                        Stepper(value: criticalBinding, in: 5...30, step: 1) {
                            SettingValueRow(title: "Critical low", value: "\(settings.customThresholds.criticalLow)%")
                        }
                        Stepper(value: temperatureBinding, in: 30...55, step: 1) {
                            SettingValueRow(title: "Cooling pause", value: "\(Int(settings.customThresholds.hotTemperatureC)) C")
                        }
                    }
                }

                SettingsGroup(title: "Preferences", icon: "switch.2") {
                    VStack(spacing: 12) {
                        SettingToggle(
                            title: "Notifications",
                            detail: "Alert when protection changes state",
                            isOn: $settings.notificationsEnabled
                        )
                        SettingToggle(
                            title: "Launch at login",
                            detail: "Keep protection available after restart",
                            isOn: $settings.launchAtLogin
                        )
                        SettingToggle(
                            title: "Simulation mode",
                            detail: "Test the dashboard without changing hardware",
                            isOn: simulationBinding
                        )
                    }
                }

                SettingsGroup(title: "Charge controller", icon: "cpu") {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(controlColor)
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(engine.chargeControlResult.backendName) - \(controlValue)")
                                .font(.caption.weight(.semibold))
                            Text(settings.simulationMode ? "Simulation is isolated from hardware charge control." : engine.chargeControlResult.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            }
            .padding(18)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: settings.protectionEnabled ? "shield.checkered" : "shield.slash")
                .foregroundStyle(settings.protectionEnabled ? GuardianPalette.accent : .secondary)
            Text(settings.protectionEnabled ? "Battery Protection Active" : "Protection Disabled")
                .font(.caption.weight(.medium))
            Spacer()
            Text(engine.snapshot.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit())
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

    private var protectionBinding: Binding<Bool> {
        Binding(
            get: { settings.protectionEnabled },
            set: {
                settings.protectionEnabled = $0
                engine.refresh()
            }
        )
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
        guard let temperature = engine.snapshot.temperatureC else { return "Unavailable" }
        return "\(Int(temperature.rounded())) C"
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
        if settings.simulationMode { return "Simulation" }
        return engine.chargeControlResult.isHardwareControlAvailable ? "Connected" : "Needs Setup"
    }

    private var controlTitle: String {
        if settings.simulationMode { return "Simulation is running" }
        return engine.chargeControlResult.isHardwareControlAvailable ? "Hardware protection connected" : "Hardware protection needs setup"
    }

    private var controlDetail: String {
        if settings.simulationMode { return "Live battery settings are not changed." }
        if engine.chargeControlResult.isHardwareControlAvailable {
            return "Charge limits are being applied by \(engine.chargeControlResult.backendName)."
        }
        return "Open Settings to review the controller status."
    }

    private var controlIcon: String {
        settings.simulationMode ? "testtube.2" : (engine.chargeControlResult.isHardwareControlAvailable ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
    }

    private var controlColor: Color {
        settings.simulationMode ? GuardianPalette.cyan : (engine.chargeControlResult.isHardwareControlAvailable ? GuardianPalette.accent : GuardianPalette.warning)
    }

    private func shortTitle(for mode: GuardianMode) -> String {
        mode == .maximumLife ? "Max Life" : mode.title
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
                        .font(.title2.monospacedDigit().weight(.bold))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(for: engine.decision.state))
                            .frame(width: 7, height: 7)
                        Text(engine.decision.statusText)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(engine.snapshot.powerSource.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ThresholdRangeView(thresholds: settings.activeThresholds, compact: true)

            HStack {
                Label(temperatureText, systemImage: "thermometer.medium")
                Spacer()
                Label(settings.mode.title, systemImage: "slider.horizontal.3")
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)

            Toggle("Battery protection", isOn: protectionBinding)
                .toggleStyle(.switch)
                .tint(GuardianPalette.accent)

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Label("Open Dashboard", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(GuardianPalette.accent)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 20)
                }
                .buttonStyle(.bordered)
                .help("Refresh battery status")

                Button(action: onQuit) {
                    Image(systemName: "power")
                        .frame(width: 20)
                }
                .buttonStyle(.bordered)
                .help("Quit Orca Battery Guardian")
            }
        }
        .padding(16)
        .frame(width: 320)
        .foregroundStyle(Color.white)
        .background(GuardianPalette.background)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .onAppear { engine.start() }
    }

    private var protectionBinding: Binding<Bool> {
        Binding(
            get: { settings.protectionEnabled },
            set: {
                settings.protectionEnabled = $0
                engine.refresh()
            }
        )
    }

    private var temperatureText: String {
        guard let temperature = engine.snapshot.temperatureC else { return "No temperature" }
        return "\(Int(temperature.rounded())) C"
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
                Text("PERCENT")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 94, height: 94)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(percentage) percent")
    }
}

private struct ThresholdRangeView: View {
    let thresholds: ChargeThresholds
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 7 : 9) {
            if !compact {
                HStack {
                    Label("Resume charging", systemImage: "bolt.fill")
                    Spacer()
                    Label("Stop charging", systemImage: "pause.fill")
                }
                .font(.caption)
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
                Text(compact ? "Target range" : "Protected range")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(thresholds.upper)%")
            }
            .font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(compact ? 11 : 13)
        .background(GuardianPalette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(GuardianPalette.stroke, lineWidth: 1)
        }
    }
}

private struct MetricTile: View {
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
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
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

private struct EventRow: View {
    let event: StatusEvent

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GuardianPalette.cyan)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(event.date, format: .dateTime.hour().minute().second())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(event.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
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
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: range, step: 5) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(value)%")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
        }
        .padding(10)
        .background(GuardianPalette.raised, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SettingValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(GuardianPalette.accent)
        }
    }
}

private struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(detail)
                    .font(.caption2)
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
