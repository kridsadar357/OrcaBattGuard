import Foundation
import ServiceManagement

@MainActor
public final class GuardianSettings: ObservableObject {
    @Published public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published public var mode: GuardianMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.mode)
        }
    }

    @Published public var customThresholds: ChargeThresholds {
        didSet {
            defaults.set(customThresholds.lower, forKey: Keys.lower)
            defaults.set(customThresholds.upper, forKey: Keys.upper)
            defaults.set(customThresholds.criticalLow, forKey: Keys.criticalLow)
            defaults.set(customThresholds.hotTemperatureC, forKey: Keys.hotTemperature)
        }
    }

    @Published public var protectionEnabled: Bool {
        didSet { defaults.set(protectionEnabled, forKey: Keys.protectionEnabled) }
    }

    @Published public var simulationMode: Bool {
        didSet { defaults.set(simulationMode, forKey: Keys.simulationMode) }
    }

    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    @Published public var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Keys.checksForUpdates) }
    }

    public var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Keys.lastUpdateCheck) as? Date }
        set {
            if let newValue { defaults.set(newValue, forKey: Keys.lastUpdateCheck) }
            else { defaults.removeObject(forKey: Keys.lastUpdateCheck) }
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            configureLaunchAtLogin(launchAtLogin)
        }
    }

    @Published public var chargeToFullUntil: Date? {
        didSet {
            if let chargeToFullUntil {
                defaults.set(chargeToFullUntil, forKey: Keys.chargeToFullUntil)
            } else {
                defaults.removeObject(forKey: Keys.chargeToFullUntil)
            }
        }
    }

    private let defaults: UserDefaults

    public var activeThresholds: ChargeThresholds {
        let chargeRange = mode == .custom ? customThresholds : mode.thresholds
        return ChargeThresholds(
            lower: chargeRange.lower,
            upper: chargeRange.upper,
            criticalLow: customThresholds.criticalLow,
            hotTemperatureC: customThresholds.hotTemperatureC
        ).normalized
    }

    public var isChargeToFullActive: Bool {
        guard let chargeToFullUntil else { return false }
        return chargeToFullUntil > Date()
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        let savedMode = defaults.string(forKey: Keys.mode).flatMap(GuardianMode.init(rawValue:)) ?? .balanced
        mode = savedMode
        customThresholds = ChargeThresholds(
            lower: defaults.object(forKey: Keys.lower) as? Int ?? savedMode.thresholds.lower,
            upper: defaults.object(forKey: Keys.upper) as? Int ?? savedMode.thresholds.upper,
            criticalLow: defaults.object(forKey: Keys.criticalLow) as? Int ?? 15,
            hotTemperatureC: defaults.object(forKey: Keys.hotTemperature) as? Double ?? 38
        )
        protectionEnabled = defaults.object(forKey: Keys.protectionEnabled) as? Bool ?? true
        simulationMode = defaults.object(forKey: Keys.simulationMode) as? Bool ?? false
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        checksForUpdates = defaults.object(forKey: Keys.checksForUpdates) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        chargeToFullUntil = defaults.object(forKey: Keys.chargeToFullUntil) as? Date
    }

    public func beginTemporaryFullCharge(duration: FullChargeDuration, now: Date = Date()) {
        chargeToFullUntil = now.addingTimeInterval(duration.rawValue)
    }

    public func endTemporaryFullCharge() {
        chargeToFullUntil = nil
    }

    private func configureLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            defaults.set(false, forKey: Keys.launchAtLogin)
            launchAtLogin = false
        }
    }

    private enum Keys {
        static let language = "guardian.language"
        static let mode = "guardian.mode"
        static let lower = "guardian.lower"
        static let upper = "guardian.upper"
        static let criticalLow = "guardian.criticalLow"
        static let hotTemperature = "guardian.hotTemperature"
        static let protectionEnabled = "guardian.protectionEnabled"
        static let simulationMode = "guardian.simulationMode"
        static let notificationsEnabled = "guardian.notificationsEnabled"
        static let checksForUpdates = "guardian.checksForUpdates"
        static let lastUpdateCheck = "guardian.lastUpdateCheck"
        static let launchAtLogin = "guardian.launchAtLogin"
        static let chargeToFullUntil = "guardian.chargeToFullUntil"
    }
}
