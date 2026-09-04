import Foundation

public protocol BatteryBenchmarkStoring: Sendable {
    func record(_ observation: BatteryBenchmarkObservation) async throws -> BatteryBenchmarkReport
    func reset(with observation: BatteryBenchmarkObservation) async throws -> BatteryBenchmarkReport
    func flush(at date: Date) async throws
}

public actor BatteryBenchmarkStore: BatteryBenchmarkStoring {
    public static let maximumDays = 400
    public static let maximumBytes = 2 * 1_024 * 1_024
    public static let maximumSampleInterval: TimeInterval = 5 * 60
    public static let persistenceInterval: TimeInterval = 5 * 60

    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("OrcaBatteryGuardian", isDirectory: true)
            .appendingPathComponent("benchmark.json")
    }

    private let fileURL: URL
    private let calendar: Calendar
    private var document: Document?
    private var lastObservation: BatteryBenchmarkObservation?
    private var lastPersistedAt: Date?
    private var loaded = false
    private var dirty = false
    private var refusesOverwrite = false

    public init(fileURL: URL = BatteryBenchmarkStore.defaultURL, calendar: Calendar = .autoupdatingCurrent) {
        self.fileURL = fileURL
        self.calendar = calendar
    }

    public static func loadReport(at fileURL: URL = defaultURL) throws -> BatteryBenchmarkReport? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= maximumBytes else { throw BenchmarkError.invalidFile }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
        guard document.version == 1 else { throw BenchmarkError.invalidFile }
        return BatteryBenchmarkReport(baseline: document.baseline, days: document.days)
    }

    public func record(_ observation: BatteryBenchmarkObservation) throws -> BatteryBenchmarkReport {
        try loadIfNeeded()
        if document == nil { document = newDocument(from: observation) }
        fillMissingBaselineValues(from: observation)

        if let previous = lastObservation, observation.timestamp > previous.timestamp {
            let end = min(observation.timestamp, previous.timestamp.addingTimeInterval(Self.maximumSampleInterval))
            accumulate(previous, from: previous.timestamp, to: end)
        }
        observe(observation)
        lastObservation = observation
        dirty = true

        if lastPersistedAt == nil || observation.timestamp.timeIntervalSince(lastPersistedAt!) >= Self.persistenceInterval {
            try persist()
            lastPersistedAt = observation.timestamp
        }
        return report
    }

    public func reset(with observation: BatteryBenchmarkObservation) throws -> BatteryBenchmarkReport {
        loaded = true
        refusesOverwrite = false
        document = newDocument(from: observation)
        lastObservation = observation
        observe(observation)
        dirty = true
        try persist()
        lastPersistedAt = observation.timestamp
        return report
    }

    public func flush(at date: Date = Date()) throws {
        try loadIfNeeded()
        if let previous = lastObservation, date > previous.timestamp {
            let end = min(date, previous.timestamp.addingTimeInterval(Self.maximumSampleInterval))
            accumulate(previous, from: previous.timestamp, to: end)
            dirty = true
        }
        if dirty { try persist() }
    }

    private var report: BatteryBenchmarkReport {
        guard let document else {
            preconditionFailure("A benchmark document must exist before requesting a report.")
        }
        return BatteryBenchmarkReport(baseline: document.baseline, days: document.days)
    }

    private func loadIfNeeded() throws {
        guard !loaded else {
            if refusesOverwrite { throw BenchmarkError.unreadable }
            return
        }
        loaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= Self.maximumBytes else { throw BenchmarkError.invalidFile }
            let decoded = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
            guard decoded.version == 1 else { throw BenchmarkError.invalidFile }
            document = Document(version: 1, baseline: decoded.baseline, days: bounded(decoded.days))
        } catch {
            refusesOverwrite = true
            throw BenchmarkError.unreadable
        }
    }

    private func newDocument(from observation: BatteryBenchmarkObservation) -> Document {
        Document(
            version: 1,
            baseline: BatteryBenchmarkBaseline(
                date: observation.timestamp,
                cycleCount: observation.cycleCount,
                fullChargeCapacityMah: observation.fullChargeCapacityMah,
                designCapacityMah: observation.designCapacityMah,
                temperatureC: observation.temperatureC
            ),
            days: []
        )
    }

    private func fillMissingBaselineValues(from observation: BatteryBenchmarkObservation) {
        guard var value = document else { return }
        if value.baseline.cycleCount == nil { value.baseline.cycleCount = observation.cycleCount }
        if value.baseline.fullChargeCapacityMah == nil { value.baseline.fullChargeCapacityMah = observation.fullChargeCapacityMah }
        if value.baseline.designCapacityMah == nil { value.baseline.designCapacityMah = observation.designCapacityMah }
        if value.baseline.temperatureC == nil { value.baseline.temperatureC = observation.temperatureC }
        document = value
    }

    private func observe(_ observation: BatteryBenchmarkObservation) {
        guard var value = document else { return }
        let day = calendar.startOfDay(for: observation.timestamp)
        let index = value.days.firstIndex { $0.date == day }
        if let index {
            value.days[index].observe(observation)
        } else {
            var summary = BatteryBenchmarkDay(date: day)
            summary.observe(observation)
            value.days.append(summary)
        }
        value.days = bounded(value.days)
        document = value
    }

    private func accumulate(_ observation: BatteryBenchmarkObservation, from start: Date, to end: Date) {
        guard var value = document, end > start else { return }
        var cursor = start
        while cursor < end {
            let day = calendar.startOfDay(for: cursor)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? end
            let segmentEnd = min(end, nextDay)
            let seconds = segmentEnd.timeIntervalSince(cursor)
            if let index = value.days.firstIndex(where: { $0.date == day }) {
                value.days[index].accumulate(observation, seconds: seconds)
            } else {
                var summary = BatteryBenchmarkDay(date: day)
                summary.accumulate(observation, seconds: seconds)
                value.days.append(summary)
            }
            cursor = segmentEnd
        }
        value.days = bounded(value.days)
        document = value
    }

    private func persist() throws {
        guard !refusesOverwrite else { throw BenchmarkError.unreadable }
        guard let document else { return }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumBytes else { throw BenchmarkError.invalidFile }
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        dirty = false
    }

    private func bounded(_ days: [BatteryBenchmarkDay]) -> [BatteryBenchmarkDay] {
        Array(days.sorted { $0.date < $1.date }.suffix(Self.maximumDays))
    }

    private struct Document: Codable {
        let version: Int
        var baseline: BatteryBenchmarkBaseline
        var days: [BatteryBenchmarkDay]
    }

    enum BenchmarkError: LocalizedError {
        case invalidFile
        case unreadable

        var errorDescription: String? {
            "Saved benchmark data is unreadable or exceeds the size limit. The existing file was preserved."
        }
    }
}
