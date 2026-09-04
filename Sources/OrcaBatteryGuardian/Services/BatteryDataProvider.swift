import Foundation
import IOKit
import IOKit.ps

public protocol BatteryDataProviding {
    func currentSnapshot() -> BatterySnapshot
}

public final class IOKitBatteryDataProvider: BatteryDataProviding {
    public init() {}

    public func currentSnapshot() -> BatterySnapshot {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as Array

        guard let source = sources.first,
              let description = IOPSGetPowerSourceDescription(psInfo, source).takeUnretainedValue() as? [String: Any] else {
            return BatterySnapshot(
                percentage: 0,
                powerSource: .unknown,
                isCharging: false,
                isFullyCharged: false,
                temperatureC: readSmartBatteryTemperature(),
                cycleCount: readSmartBatteryInt("CycleCount"),
                health: readSmartBatteryString("BatteryHealth"),
                fullChargeCapacityMah: readFullChargeCapacity(),
                designCapacityMah: readSmartBatteryInt("DesignCapacity")
            )
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCapacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let percentage = maxCapacity > 0 ? Int((Double(current) / Double(maxCapacity) * 100).rounded()) : 0
        let sourceState = description[kIOPSPowerSourceStateKey] as? String
        let powerSource: PowerSource = sourceState == kIOPSACPowerValue ? .acPower : (sourceState == kIOPSBatteryPowerValue ? .battery : .unknown)

        return BatterySnapshot(
            percentage: min(max(percentage, 0), 100),
            powerSource: powerSource,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
            isFullyCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
            temperatureC: readSmartBatteryTemperature(),
            cycleCount: readSmartBatteryInt("CycleCount"),
            health: (description[kIOPSBatteryHealthKey] as? String) ?? readSmartBatteryString("BatteryHealth"),
            fullChargeCapacityMah: readFullChargeCapacity(),
            designCapacityMah: readSmartBatteryInt("DesignCapacity")
        )
    }

    private func readFullChargeCapacity() -> Int? {
        readSmartBatteryInt("AppleRawMaxCapacity") ?? readSmartBatteryInt("NominalChargeCapacity")
    }

    private func readSmartBatteryTemperature() -> Double? {
        guard let raw = readSmartBatteryInt("Temperature") else { return nil }
        return Self.celsiusTemperature(from: raw)
    }

    static func celsiusTemperature(from rawValue: Int) -> Double? {
        guard rawValue > 0 else { return nil }
        return Double(rawValue) / 100.0
    }

    private func readSmartBatteryInt(_ key: String) -> Int? {
        readSmartBatteryValue(key) as? Int
    }

    private func readSmartBatteryString(_ key: String) -> String? {
        readSmartBatteryValue(key) as? String
    }

    private func readSmartBatteryValue(_ key: String) -> Any? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue()
    }
}

public final class MockBatteryDataProvider: BatteryDataProviding {
    private var snapshot: BatterySnapshot
    private var direction: Int = 1

    public init(startingPercentage: Int = 64) {
        snapshot = BatterySnapshot(
            percentage: startingPercentage,
            powerSource: .acPower,
            isCharging: true,
            isFullyCharged: false,
            temperatureC: 32,
            cycleCount: 218,
            health: "Good",
            fullChargeCapacityMah: 7_850,
            designCapacityMah: 8_600
        )
    }

    public func currentSnapshot() -> BatterySnapshot {
        let next = min(max(snapshot.percentage + direction, 12), 100)
        if next >= 86 { direction = -1 }
        if next <= 42 { direction = 1 }

        snapshot.percentage = next
        snapshot.isCharging = direction > 0
        snapshot.isFullyCharged = next >= 100
        snapshot.powerSource = direction > 0 ? .acPower : .battery
        snapshot.temperatureC = next > 78 ? 39.4 : 31.8
        snapshot.timestamp = Date()
        return snapshot
    }
}
