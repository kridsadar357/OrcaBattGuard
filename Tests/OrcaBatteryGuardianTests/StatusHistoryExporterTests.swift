import Foundation
import Testing
@testable import OrcaBatteryGuardian

@Test func historyCSVQuotesCommasQuotesAndNewlines() {
    let event = StatusEvent(
        date: Date(timeIntervalSince1970: 0),
        title: "Holding, verified",
        detail: "A \"quoted\" line\ncontinues"
    )
    let csv = StatusHistoryExporter.csv([event])

    #expect(csv.hasPrefix("timestamp,title,detail\n"))
    #expect(csv.contains("\"Holding, verified\""))
    #expect(csv.contains("\"A \"\"quoted\"\" line\ncontinues\""))
}

@Test func historyJSONUsesPortableISO8601Dates() throws {
    let data = try StatusHistoryExporter.json([
        StatusEvent(date: Date(timeIntervalSince1970: 0), title: "Test", detail: "Detail")
    ])
    let value = String(decoding: data, as: UTF8.self)
    #expect(value.contains("1970-01-01T00:00:00Z"))
}
