import Foundation
import Testing
@testable import OrcaBatteryGuardian

private struct TemporaryHistory {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OrcaHistoryTests-\(UUID().uuidString)")
    var file: URL { directory.appendingPathComponent("history.json") }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

@Test func historySurvivesNewStoreAndKeepsNewestEvents() async throws {
    let temp = TemporaryHistory()
    defer { temp.remove() }
    let store = StatusHistoryStore(fileURL: temp.file, maxEvents: 3)
    #expect(try await store.load().isEmpty)
    let events = (0..<5).map { StatusEvent(date: Date(timeIntervalSince1970: Double($0)), title: "Event \($0)", detail: "Detail") }
    let saved = try await store.save(events)
    let reloaded = try await StatusHistoryStore(fileURL: temp.file, maxEvents: 3).load()
    #expect(saved == reloaded)
    #expect(reloaded.map(\.title) == ["Event 4", "Event 3", "Event 2"])
    let attributes = try FileManager.default.attributesOfItem(atPath: temp.file.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func historyIsBoundedByBytesAndDeduplicatesIDs() async throws {
    let temp = TemporaryHistory()
    defer { temp.remove() }
    let store = StatusHistoryStore(fileURL: temp.file, maxBytes: 2_000)
    let events = (0..<20).map { StatusEvent(date: Date(timeIntervalSince1970: Double($0)), title: "Event", detail: String(repeating: "x", count: 800)) }
    let saved = try await store.save(events + events)
    #expect(!saved.isEmpty && saved.count < events.count)
    #expect(Set(saved.map(\.id)).count == saved.count)
    #expect(saved.first?.id == events.last?.id)
    #expect(try Data(contentsOf: temp.file).count <= 2_000)
}

@Test func longEventFieldsAreTruncated() async throws {
    let temp = TemporaryHistory()
    defer { temp.remove() }
    let saved = try await StatusHistoryStore(fileURL: temp.file).save([
        StatusEvent(title: String(repeating: "t", count: 500), detail: String(repeating: "d", count: 2_000))
    ])
    #expect(saved.first?.title.count == 160)
    #expect(saved.first?.detail.count == 1_024)
}

@Test(arguments: ["not json", "{\"version\":99,\"events\":[]}", String(repeating: "x", count: 3_000)])
func corruptHistoryIsReportedAndNotOverwritten(contents: String) async throws {
    let temp = TemporaryHistory()
    defer { temp.remove() }
    try FileManager.default.createDirectory(at: temp.directory, withIntermediateDirectories: true)
    let original = Data(contents.utf8)
    try original.write(to: temp.file)
    let store = StatusHistoryStore(fileURL: temp.file, maxBytes: 2_000)
    await #expect(throws: (any Error).self) { try await store.load() }
    await #expect(throws: (any Error).self) { try await store.save([StatusEvent(title: "New", detail: "Keep original")]) }
    #expect(try Data(contentsOf: temp.file) == original)
}

@Test func unwritableHistoryPathReportsFailure() async throws {
    let temp = TemporaryHistory()
    defer { temp.remove() }
    try Data("not a directory".utf8).write(to: temp.directory)
    let store = StatusHistoryStore(fileURL: temp.file)
    await #expect(throws: (any Error).self) { try await store.save([StatusEvent(title: "Test", detail: "Test")]) }
}
