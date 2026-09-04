import Foundation

public protocol StatusHistoryStoring: Sendable {
    func load() async throws -> [StatusEvent]
    func save(_ events: [StatusEvent]) async throws -> [StatusEvent]
}

public actor StatusHistoryStore: StatusHistoryStoring {
    public static let maximumEvents = 500
    public static let maximumBytes = 512 * 1024

    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("OrcaBatteryGuardian", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    private let fileURL: URL
    private let maxEvents: Int
    private let maxBytes: Int
    private var refusesOverwrite = false

    public init(fileURL: URL = StatusHistoryStore.defaultURL, maxEvents: Int = maximumEvents, maxBytes: Int = maximumBytes) {
        self.fileURL = fileURL
        self.maxEvents = max(1, maxEvents)
        self.maxBytes = max(128, maxBytes)
    }

    public func load() throws -> [StatusEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= maxBytes else { throw HistoryError.invalidFile }
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
            guard document.version == 1 else { throw HistoryError.invalidFile }
            refusesOverwrite = false
            return bounded(document.events)
        } catch {
            refusesOverwrite = true
            throw HistoryError.unreadable
        }
    }

    public func save(_ events: [StatusEvent]) throws -> [StatusEvent] {
        guard !refusesOverwrite else { throw HistoryError.unreadable }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var retained = bounded(events)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(Document(version: 1, events: retained))
        while data.count > maxBytes, !retained.isEmpty {
            retained.removeLast()
            data = try encoder.encode(Document(version: 1, events: retained))
        }
        try data.write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return retained
    }

    private func bounded(_ events: [StatusEvent]) -> [StatusEvent] {
        var seen = Set<UUID>()
        return events.sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
            .prefix(maxEvents)
            .map { StatusEvent(id: $0.id, date: $0.date, title: String($0.title.prefix(160)), detail: String($0.detail.prefix(1_024))) }
    }

    private struct Document: Codable {
        let version: Int
        let events: [StatusEvent]
    }

    private enum HistoryError: LocalizedError {
        case invalidFile
        case unreadable

        var errorDescription: String? {
            "Saved history is unreadable or exceeds the size limit. The existing file was preserved. New events remain in memory."
        }
    }
}

public enum StatusHistoryExporter {
    public static func csv(_ events: [StatusEvent]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = ["timestamp,title,detail"]
        rows += events.sorted { $0.date > $1.date }.map { event in
            [formatter.string(from: event.date), event.title, event.detail]
                .map(escapeCSV)
                .joined(separator: ",")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    public static func json(_ events: [StatusEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(events.sorted { $0.date > $1.date })
    }

    private static func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
