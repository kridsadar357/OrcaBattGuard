import Foundation

public enum PowerSource: String, CaseIterable, Sendable {
    case acPower = "AC Power"
    case battery = "Battery"
    case unknown = "Unknown"
}

public enum ChargingState: String, CaseIterable, Sendable {
    case charging = "Charging"
    case holding = "Holding"
    case discharging = "Discharging"
    case coolingPause = "Cooling Pause"
    case safetyCharge = "Safety Charge"
    case unknown = "Unknown"
}

public enum GuardianMode: String, CaseIterable, Identifiable, Sendable {
    case maximumLife
    case balanced
    case travel
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .maximumLife: "Maximum Life"
        case .balanced: "Balanced"
        case .travel: "Travel"
        case .custom: "Custom"
        }
    }

    public var subtitle: String {
        switch self {
        case .maximumLife: "50-70%"
        case .balanced: "50-80%"
        case .travel: "20-100%"
        case .custom: "Manual range"
        }
    }

    public var thresholds: ChargeThresholds {
        switch self {
        case .maximumLife: ChargeThresholds(lower: 50, upper: 70)
        case .balanced: ChargeThresholds(lower: 50, upper: 80)
        case .travel: ChargeThresholds(lower: 20, upper: 100)
        case .custom: ChargeThresholds(lower: 50, upper: 80)
        }
    }
}

public struct ChargeThresholds: Equatable, Sendable {
    public var lower: Int
    public var upper: Int
    public var criticalLow: Int
    public var hotTemperatureC: Double

    public init(lower: Int, upper: Int, criticalLow: Int = 15, hotTemperatureC: Double = 38) {
        self.lower = lower
        self.upper = upper
        self.criticalLow = criticalLow
        self.hotTemperatureC = hotTemperatureC
    }

    public var normalized: ChargeThresholds {
        let safeLower = min(max(lower, 5), 95)
        let safeUpper = min(max(upper, safeLower + 5), 100)
        return ChargeThresholds(
            lower: safeLower,
            upper: safeUpper,
            criticalLow: min(max(criticalLow, 5), safeLower),
            hotTemperatureC: min(max(hotTemperatureC, 30), 55)
        )
    }
}

public struct BatterySnapshot: Equatable, Sendable {
    public var percentage: Int
    public var powerSource: PowerSource
    public var isCharging: Bool
    public var isFullyCharged: Bool
    public var temperatureC: Double?
    public var cycleCount: Int?
    public var health: String?
    public var timestamp: Date

    public init(
        percentage: Int,
        powerSource: PowerSource,
        isCharging: Bool,
        isFullyCharged: Bool,
        temperatureC: Double?,
        cycleCount: Int?,
        health: String?,
        timestamp: Date = Date()
    ) {
        self.percentage = percentage
        self.powerSource = powerSource
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.temperatureC = temperatureC
        self.cycleCount = cycleCount
        self.health = health
        self.timestamp = timestamp
    }
}

public struct GuardianDecision: Equatable, Sendable {
    public var state: ChargingState
    public var desiredAction: ChargeControlAction
    public var statusText: String
    public var reason: String

    public init(state: ChargingState, desiredAction: ChargeControlAction, statusText: String, reason: String) {
        self.state = state
        self.desiredAction = desiredAction
        self.statusText = statusText
        self.reason = reason
    }
}

public enum ChargeControlAction: String, Equatable, Sendable {
    case allowCharging
    case pauseCharging
    case noChange
}

public struct ChargeControlResult: Equatable, Sendable {
    public var backendName: String
    public var isHardwareControlAvailable: Bool
    public var didAttemptHardwareChange: Bool
    public var message: String

    public init(
        backendName: String,
        isHardwareControlAvailable: Bool,
        didAttemptHardwareChange: Bool,
        message: String
    ) {
        self.backendName = backendName
        self.isHardwareControlAvailable = isHardwareControlAvailable
        self.didAttemptHardwareChange = didAttemptHardwareChange
        self.message = message
    }
}

public struct StatusEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let title: String
    public let detail: String

    public init(id: UUID = UUID(), date: Date = Date(), title: String, detail: String) {
        self.id = id
        self.date = date
        self.title = title
        self.detail = detail
    }
}
