import Foundation

public enum BenchmarkPeriod: Int, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    public var id: Int { rawValue }
    public var title: String { "\(rawValue) days" }
    public var shortTitle: String { "\(rawValue)D" }
}

public struct BatteryBenchmarkBaseline: Codable, Equatable, Sendable {
    public let date: Date
    public var cycleCount: Int?
    public var fullChargeCapacityMah: Int?
    public var designCapacityMah: Int?
    public var temperatureC: Double?

    public var healthPercentage: Double? {
        Self.healthPercentage(fullChargeCapacityMah: fullChargeCapacityMah, designCapacityMah: designCapacityMah)
    }

    static func healthPercentage(fullChargeCapacityMah: Int?, designCapacityMah: Int?) -> Double? {
        guard let fullChargeCapacityMah, let designCapacityMah,
              fullChargeCapacityMah > 0, designCapacityMah > 0 else { return nil }
        return min(100, Double(fullChargeCapacityMah) / Double(designCapacityMah) * 100)
    }
}

public struct BatteryBenchmarkDay: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public var sampleCount: Int
    public var percentageTotal: Double
    public var temperatureTotal: Double
    public var temperatureSampleCount: Int
    public var observedSeconds: TimeInterval
    public var above80Seconds: TimeInterval
    public var hotSeconds: TimeInterval
    public var protectedSeconds: TimeInterval
    public var verifiedProtectionSeconds: TimeInterval
    public var acPowerSeconds: TimeInterval
    public var batteryPowerSeconds: TimeInterval
    public var chargingSeconds: TimeInterval
    public var holdingSeconds: TimeInterval
    public var coolingPauseSeconds: TimeInterval
    public var minimumPercentage: Int
    public var maximumPercentage: Int
    public var maximumTemperatureC: Double?
    public var startCycleCount: Int?
    public var endCycleCount: Int?
    public var startFullChargeCapacityMah: Int?
    public var endFullChargeCapacityMah: Int?
    public var designCapacityMah: Int?

    public init(date: Date) {
        self.date = date
        sampleCount = 0
        percentageTotal = 0
        temperatureTotal = 0
        temperatureSampleCount = 0
        observedSeconds = 0
        above80Seconds = 0
        hotSeconds = 0
        protectedSeconds = 0
        verifiedProtectionSeconds = 0
        acPowerSeconds = 0
        batteryPowerSeconds = 0
        chargingSeconds = 0
        holdingSeconds = 0
        coolingPauseSeconds = 0
        minimumPercentage = 100
        maximumPercentage = 0
    }

    public var averagePercentage: Double? {
        sampleCount > 0 ? percentageTotal / Double(sampleCount) : nil
    }

    public var averageTemperatureC: Double? {
        temperatureSampleCount > 0 ? temperatureTotal / Double(temperatureSampleCount) : nil
    }

    public var healthPercentage: Double? {
        BatteryBenchmarkBaseline.healthPercentage(
            fullChargeCapacityMah: endFullChargeCapacityMah,
            designCapacityMah: designCapacityMah
        )
    }

    public var protectedPercentage: Double? {
        observedSeconds > 0 ? protectedSeconds / observedSeconds * 100 : nil
    }

    public var controllerReliabilityPercentage: Double? {
        protectedSeconds > 0 ? verifiedProtectionSeconds / protectedSeconds * 100 : nil
    }

    mutating func observe(_ observation: BatteryBenchmarkObservation) {
        sampleCount += 1
        percentageTotal += Double(observation.percentage)
        minimumPercentage = min(minimumPercentage, observation.percentage)
        maximumPercentage = max(maximumPercentage, observation.percentage)
        if let temperatureC = observation.temperatureC {
            temperatureTotal += temperatureC
            temperatureSampleCount += 1
            maximumTemperatureC = max(maximumTemperatureC ?? temperatureC, temperatureC)
        }
        if startCycleCount == nil { startCycleCount = observation.cycleCount }
        if startFullChargeCapacityMah == nil { startFullChargeCapacityMah = observation.fullChargeCapacityMah }
        endCycleCount = observation.cycleCount ?? endCycleCount
        endFullChargeCapacityMah = observation.fullChargeCapacityMah ?? endFullChargeCapacityMah
        designCapacityMah = observation.designCapacityMah ?? designCapacityMah
    }

    mutating func accumulate(_ observation: BatteryBenchmarkObservation, seconds: TimeInterval) {
        guard seconds > 0 else { return }
        observedSeconds += seconds
        if observation.percentage > 80 { above80Seconds += seconds }
        if observation.temperatureC.map({ $0 >= 38 }) == true { hotSeconds += seconds }
        if observation.protectionEnabled {
            protectedSeconds += seconds
            if observation.controlVerified { verifiedProtectionSeconds += seconds }
        }
        switch observation.powerSource {
        case .acPower: acPowerSeconds += seconds
        case .battery: batteryPowerSeconds += seconds
        case .unknown: break
        }
        if observation.isCharging { chargingSeconds += seconds }
        if observation.state == .holding { holdingSeconds += seconds }
        if observation.state == .coolingPause { coolingPauseSeconds += seconds }
    }
}

public struct BatteryBenchmarkObservation: Equatable, Sendable {
    public let timestamp: Date
    public let percentage: Int
    public let temperatureC: Double?
    public let cycleCount: Int?
    public let fullChargeCapacityMah: Int?
    public let designCapacityMah: Int?
    public let powerSource: PowerSource
    public let isCharging: Bool
    public let state: ChargingState
    public let protectionEnabled: Bool
    public let controlVerified: Bool

    public init(
        snapshot: BatterySnapshot,
        state: ChargingState,
        protectionEnabled: Bool,
        controlVerified: Bool
    ) {
        timestamp = snapshot.timestamp
        percentage = snapshot.percentage
        temperatureC = snapshot.temperatureC
        cycleCount = snapshot.cycleCount
        fullChargeCapacityMah = snapshot.fullChargeCapacityMah
        designCapacityMah = snapshot.designCapacityMah
        powerSource = snapshot.powerSource
        isCharging = snapshot.isCharging
        self.state = state
        self.protectionEnabled = protectionEnabled
        self.controlVerified = controlVerified
    }
}

public struct BatteryBenchmarkSummary: Equatable, Sendable {
    public let period: BenchmarkPeriod
    public let daysCollected: Int
    public let observedSeconds: TimeInterval
    public let averagePercentage: Double?
    public let averageTemperatureC: Double?
    public let maximumTemperatureC: Double?
    public let above80Seconds: TimeInterval
    public let hotSeconds: TimeInterval
    public let protectedPercentage: Double?
    public let controllerReliabilityPercentage: Double?
    public let currentCycleCount: Int?
    public let currentFullChargeCapacityMah: Int?
    public let currentHealthPercentage: Double?
}

public struct BatteryBenchmarkReport: Equatable, Sendable {
    public let baseline: BatteryBenchmarkBaseline
    public let days: [BatteryBenchmarkDay]

    public init(baseline: BatteryBenchmarkBaseline, days: [BatteryBenchmarkDay]) {
        self.baseline = baseline
        self.days = days.sorted { $0.date < $1.date }
    }

    public func summary(
        for period: BenchmarkPeriod,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> BatteryBenchmarkSummary {
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: today) ?? today
        let selected = days.filter { $0.date >= cutoff && $0.date <= today }
        let sampleCount = selected.reduce(0) { $0 + $1.sampleCount }
        let temperatureSamples = selected.reduce(0) { $0 + $1.temperatureSampleCount }
        let observed = selected.reduce(0) { $0 + $1.observedSeconds }
        let protected = selected.reduce(0) { $0 + $1.protectedSeconds }
        let verified = selected.reduce(0) { $0 + $1.verifiedProtectionSeconds }
        let latest = selected.last ?? days.last
        let currentCapacity = latest?.endFullChargeCapacityMah
        let designCapacity = latest?.designCapacityMah ?? baseline.designCapacityMah

        return BatteryBenchmarkSummary(
            period: period,
            daysCollected: selected.filter { $0.sampleCount > 0 }.count,
            observedSeconds: observed,
            averagePercentage: sampleCount > 0
                ? selected.reduce(0) { $0 + $1.percentageTotal } / Double(sampleCount) : nil,
            averageTemperatureC: temperatureSamples > 0
                ? selected.reduce(0) { $0 + $1.temperatureTotal } / Double(temperatureSamples) : nil,
            maximumTemperatureC: selected.compactMap(\.maximumTemperatureC).max(),
            above80Seconds: selected.reduce(0) { $0 + $1.above80Seconds },
            hotSeconds: selected.reduce(0) { $0 + $1.hotSeconds },
            protectedPercentage: observed > 0 ? protected / observed * 100 : nil,
            controllerReliabilityPercentage: protected > 0 ? verified / protected * 100 : nil,
            currentCycleCount: latest?.endCycleCount,
            currentFullChargeCapacityMah: currentCapacity,
            currentHealthPercentage: BatteryBenchmarkBaseline.healthPercentage(
                fullChargeCapacityMah: currentCapacity,
                designCapacityMah: designCapacity
            )
        )
    }

    public var csv: String {
        var rows = [
            "date,samples,observed_hours,average_soc,minimum_soc,maximum_soc,average_temperature_c,maximum_temperature_c,above_80_hours,hot_hours,protected_percent,controller_reliability_percent,ac_power_hours,battery_power_hours,charging_hours,holding_hours,cooling_pause_hours,cycle_count,full_charge_capacity_mah,design_capacity_mah,health_estimate_percent"
        ]
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for day in days {
            var columns: [String] = []
            columns.append(formatter.string(from: day.date))
            columns.append(String(day.sampleCount))
            columns.append(Self.decimal(day.observedSeconds / 3_600))
            columns.append(Self.decimal(day.averagePercentage))
            columns.append(day.sampleCount > 0 ? String(day.minimumPercentage) : "")
            columns.append(day.sampleCount > 0 ? String(day.maximumPercentage) : "")
            columns.append(Self.decimal(day.averageTemperatureC))
            columns.append(Self.decimal(day.maximumTemperatureC))
            columns.append(Self.decimal(day.above80Seconds / 3_600))
            columns.append(Self.decimal(day.hotSeconds / 3_600))
            columns.append(Self.decimal(day.protectedPercentage))
            columns.append(Self.decimal(day.controllerReliabilityPercentage))
            columns.append(Self.decimal(day.acPowerSeconds / 3_600))
            columns.append(Self.decimal(day.batteryPowerSeconds / 3_600))
            columns.append(Self.decimal(day.chargingSeconds / 3_600))
            columns.append(Self.decimal(day.holdingSeconds / 3_600))
            columns.append(Self.decimal(day.coolingPauseSeconds / 3_600))
            columns.append(day.endCycleCount.map(String.init) ?? "")
            columns.append(day.endFullChargeCapacityMah.map(String.init) ?? "")
            columns.append(day.designCapacityMah.map(String.init) ?? "")
            columns.append(Self.decimal(day.healthPercentage))
            rows.append(columns.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func decimal(_ value: Double?) -> String {
        value.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
    }
}
