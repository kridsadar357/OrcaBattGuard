import Foundation
import OrcaBatteryGuardian

@main
struct OrcaBatteryCLI {
    private static var commandName: String {
        let invokedName = URL(fileURLWithPath: CommandLine.arguments.first ?? "orca").lastPathComponent
        return invokedName.isEmpty ? "orca" : invokedName
    }

    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        switch arguments.first {
        case "status":
            try printStatus(json: arguments.contains("--json"))
        case "diagnostics":
            await printDiagnostics()
        case "history":
            try await exportHistory(arguments)
        case "benchmark":
            try exportBenchmark(arguments)
        case "calibration":
            await printCalibration()
        case "update":
            await printUpdateStatus()
        case "version":
            print("\(commandName) 0.9.0")
        default:
            printHelp()
        }
    }

    private static func printStatus(json: Bool) throws {
        let snapshot = IOKitBatteryDataProvider().currentSnapshot()
        if json {
            let object: [String: Any] = [
                "percentage": snapshot.percentage,
                "powerSource": snapshot.powerSource.rawValue,
                "charging": snapshot.isCharging,
                "fullyCharged": snapshot.isFullyCharged,
                "temperatureC": jsonValue(snapshot.temperatureC),
                "cycleCount": jsonValue(snapshot.cycleCount),
                "health": jsonValue(snapshot.health),
                "fullChargeCapacityMah": jsonValue(snapshot.fullChargeCapacityMah),
                "designCapacityMah": jsonValue(snapshot.designCapacityMah)
            ]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } else {
            print("Battery: \(snapshot.percentage)%")
            print("Power: \(snapshot.powerSource.rawValue)")
            print("State: \(snapshot.chargingDescription)")
            print("Temperature: \(snapshot.temperatureC.map { String(format: "%.1f C", $0) } ?? "Unavailable")")
            print("Cycles: \(snapshot.cycleCount.map(String.init) ?? "Unavailable")")
            print("Capacity: \(snapshot.fullChargeCapacityMah.map { "\($0) mAh" } ?? "Unavailable")")
        }
    }

    private static func printDiagnostics() async {
        let snapshot = IOKitBatteryDataProvider().currentSnapshot()
        let installedPath = "/Applications/OrcaBatteryGuardian.app"
        let appPath = FileManager.default.fileExists(atPath: installedPath) ? installedPath : Bundle.main.bundlePath
        let checks = await SystemDiagnosticsService(applicationPath: appPath).run(snapshot: snapshot)
        for check in checks {
            let mark: String
            switch check.level {
            case .passed: mark = "PASS"
            case .information: mark = "INFO"
            case .warning: mark = "WARN"
            case .failed: mark = "FAIL"
            }
            print("[\(mark)] \(check.title): \(check.detail)")
        }
    }

    private static func exportHistory(_ arguments: [String]) async throws {
        let events = try await StatusHistoryStore().load()
        let format = option("--format", in: arguments) ?? "csv"
        let data: Data
        switch format {
        case "csv": data = Data(StatusHistoryExporter.csv(events).utf8)
        case "json": data = try StatusHistoryExporter.json(events)
        default: throw CLIError("History format must be csv or json.")
        }
        try write(data, to: option("--output", in: arguments))
    }

    private static func exportBenchmark(_ arguments: [String]) throws {
        guard let report = try BatteryBenchmarkStore.loadReport() else {
            throw CLIError("No benchmark data has been collected yet.")
        }
        try write(Data(report.csv.utf8), to: option("--output", in: arguments))
    }

    private static func printCalibration() async {
        let status = await BattMaintenanceService().calibrationStatus()
        print("Available: \(status.isAvailable)")
        print("Phase: \(status.phase)")
        print("Paused: \(status.isPaused)")
        if !status.message.isEmpty { print("Message: \(status.message)") }
    }

    private static func printUpdateStatus() async {
        let status = await GitHubUpdateService().check(currentVersion: "0.9.0")
        switch status.state {
        case .updateAvailable: print("Update available: \(status.latestVersion ?? "unknown")\n\(status.releaseURL?.absoluteString ?? "")")
        case .upToDate: print("Orca Battery Guardian is up to date.")
        case .noPublishedRelease: print("No published Orca Battery Guardian releases are available yet.")
        case .failed: print("Update check failed: \(status.message)")
        case .notChecked, .checking: print("Update status is unavailable.")
        }
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func jsonValue<T>(_ value: T?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    private static func write(_ data: Data, to path: String?) throws {
        guard let path else {
            FileHandle.standardOutput.write(data)
            if data.last != 10 { print() }
            return
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        print("Saved \(path)")
    }

    private static func printHelp() {
        print("""
        Orca Battery Guardian CLI

          \(commandName) status [--json]
          \(commandName) diagnostics
          \(commandName) calibration
          \(commandName) history [--format csv|json] [--output PATH]
          \(commandName) benchmark [--output PATH]
          \(commandName) update
          \(commandName) version

        The CLI is read-only. Battery-changing operations remain in the GUI.
        """)
    }

    private struct CLIError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
