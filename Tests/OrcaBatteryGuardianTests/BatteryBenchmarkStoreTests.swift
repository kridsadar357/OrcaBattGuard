import Foundation
import Testing
@testable import OrcaBatteryGuardian

private struct TemporaryBenchmark {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OrcaBenchmarkTests-\(UUID().uuidString)")
    var file: URL { directory.appendingPathComponent("benchmark.json") }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func benchmarkObservation(
    at date: Date,
    percentage: Int = 85,
    temperature: Double = 39,
    cycle: Int = 120,
    capacity: Int = 8_000,
    protection: Bool = true,
    verified: Bool = true
) -> BatteryBenchmarkObservation {
    let snapshot = BatterySnapshot(
        percentage: percentage,
        powerSource: .acPower,
        isCharging: false,
        isFullyCharged: false,
        temperatureC: temperature,
        cycleCount: cycle,
        health: "Good",
        fullChargeCapacityMah: capacity,
        designCapacityMah: 8_500,
        timestamp: date
    )
    return BatteryBenchmarkObservation(
        snapshot: snapshot,
        state: .holding,
        protectionEnabled: protection,
        controlVerified: verified
    )
}

@Test func benchmarkCreatesBaselineAndAccumulatesDailyMetrics() async throws {
    let temp = TemporaryBenchmark()
    defer { temp.remove() }
    let start = Date(timeIntervalSince1970: 1_735_732_800)
    let store = BatteryBenchmarkStore(fileURL: temp.file, calendar: utcCalendar)
    _ = try await store.record(benchmarkObservation(at: start))
    let report = try await store.record(benchmarkObservation(
        at: start.addingTimeInterval(60), percentage: 79, temperature: 35, cycle: 121, capacity: 7_990
    ))

    #expect(report.baseline.cycleCount == 120)
    #expect(report.baseline.fullChargeCapacityMah == 8_000)
    #expect(report.days.count == 1)
    let day = try #require(report.days.first)
    #expect(day.sampleCount == 2)
    #expect(day.observedSeconds == 60)
    #expect(day.above80Seconds == 60)
    #expect(day.hotSeconds == 60)
    #expect(day.protectedSeconds == 60)
    #expect(day.verifiedProtectionSeconds == 60)
    #expect(day.endCycleCount == 121)
    #expect(day.endFullChargeCapacityMah == 7_990)
    let permissions = try FileManager.default.attributesOfItem(atPath: temp.file.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
}

@Test func benchmarkDoesNotGuessAcrossLongMonitoringGaps() async throws {
    let temp = TemporaryBenchmark()
    defer { temp.remove() }
    let start = Date(timeIntervalSince1970: 1_735_732_800)
    let store = BatteryBenchmarkStore(fileURL: temp.file, calendar: utcCalendar)
    _ = try await store.record(benchmarkObservation(at: start))
    let report = try await store.record(benchmarkObservation(at: start.addingTimeInterval(3_600)))
    #expect(report.days.first?.observedSeconds == BatteryBenchmarkStore.maximumSampleInterval)
}

@Test func benchmarkSplitsObservedTimeAtMidnight() async throws {
    let temp = TemporaryBenchmark()
    defer { temp.remove() }
    let midnight = Date(timeIntervalSince1970: 1_735_776_000)
    let start = midnight.addingTimeInterval(-60)
    let store = BatteryBenchmarkStore(fileURL: temp.file, calendar: utcCalendar)
    _ = try await store.record(benchmarkObservation(at: start))
    let report = try await store.record(benchmarkObservation(at: midnight.addingTimeInterval(60)))
    #expect(report.days.count == 2)
    #expect(report.days[0].observedSeconds == 60)
    #expect(report.days[1].observedSeconds == 60)
}

@Test func benchmarkSurvivesRelaunchWithoutCountingOfflineTime() async throws {
    let temp = TemporaryBenchmark()
    defer { temp.remove() }
    let start = Date(timeIntervalSince1970: 1_735_732_800)
    _ = try await BatteryBenchmarkStore(fileURL: temp.file, calendar: utcCalendar)
        .record(benchmarkObservation(at: start))
    let reloaded = BatteryBenchmarkStore(fileURL: temp.file, calendar: utcCalendar)
    let report = try await reloaded.record(benchmarkObservation(at: start.addingTimeInterval(86_400)))
    #expect(report.baseline.date == start)
    #expect(report.days.count == 2)
    #expect(report.days.allSatisfy { $0.observedSeconds == 0 })
}

@Test func resetBenchmarkReplacesEarlierBaselineAndDays() async throws {
    let temp = TemporaryBenchmark()
    defer { temp.remove() }
    let start = Date(timeIntervalSince1970: 1_735_732_800)
    let store = BatteryBenchmarkStore(fileURL: temp.file, calendar: utcCalendar)
    _ = try await store.record(benchmarkObservation(at: start, cycle: 100))
    let resetDate = start.addingTimeInterval(86_400)
    let report = try await store.reset(with: benchmarkObservation(at: resetDate, cycle: 110, capacity: 7_900))
    #expect(report.baseline.date == resetDate)
    #expect(report.baseline.cycleCount == 110)
    #expect(report.days.count == 1)
    #expect(report.days.first?.endFullChargeCapacityMah == 7_900)
}

@Test func corruptBenchmarkIsPreservedUntilExplicitReset() async throws {
    let temp = TemporaryBenchmark()
    defer { temp.remove() }
    try FileManager.default.createDirectory(at: temp.directory, withIntermediateDirectories: true)
    let original = Data("not json".utf8)
    try original.write(to: temp.file)
    let store = BatteryBenchmarkStore(fileURL: temp.file, calendar: utcCalendar)
    let observation = benchmarkObservation(at: Date(timeIntervalSince1970: 1_735_732_800))
    await #expect(throws: (any Error).self) { try await store.record(observation) }
    #expect(try Data(contentsOf: temp.file) == original)
    let reset = try await store.reset(with: observation)
    #expect(reset.days.count == 1)
    #expect(try Data(contentsOf: temp.file) != original)
}

@Test func benchmarkSummaryAndCSVExposeComparableMetrics() async throws {
    let temp = TemporaryBenchmark()
    defer { temp.remove() }
    let start = Date(timeIntervalSince1970: 1_735_732_800)
    let store = BatteryBenchmarkStore(fileURL: temp.file, calendar: utcCalendar)
    _ = try await store.record(benchmarkObservation(at: start, cycle: 120, capacity: 8_000))
    let report = try await store.record(benchmarkObservation(
        at: start.addingTimeInterval(60), percentage: 75, temperature: 35, cycle: 122, capacity: 7_900,
        protection: true, verified: false
    ))
    let summary = report.summary(for: .sevenDays, now: start, calendar: utcCalendar)
    #expect(summary.currentCycleCount == 122)
    #expect(summary.currentHealthPercentage != nil)
    #expect(summary.protectedPercentage == 100)
    #expect(summary.controllerReliabilityPercentage == 100)
    #expect(report.csv.contains("controller_reliability_percent"))
    #expect(report.csv.contains(",122,7900,8500,"))
}
