import Foundation

public struct CalibrationStatus: Equatable, Sendable {
    public var isAvailable: Bool
    public var phase: String
    public var isPaused: Bool
    public var canPause: Bool
    public var canCancel: Bool
    public var message: String

    public init(
        isAvailable: Bool, phase: String = "Unavailable", isPaused: Bool = false,
        canPause: Bool = false, canCancel: Bool = false, message: String = ""
    ) {
        self.isAvailable = isAvailable
        self.phase = phase
        self.isPaused = isPaused
        self.canPause = canPause
        self.canCancel = canCancel
        self.message = message
    }

    public var isRunning: Bool {
        isAvailable && phase.caseInsensitiveCompare("idle") != .orderedSame
    }

    public static let unavailable = CalibrationStatus(
        isAvailable: false,
        message: "Calibration requires a compatible batt daemon."
    )
}

public enum CalibrationCommand: String, Sendable {
    case start
    case pause
    case resume
    case cancel
}

public struct MaintenanceResult: Equatable, Sendable {
    public var succeeded: Bool
    public var message: String
    public var calibration: CalibrationStatus

    public init(succeeded: Bool, message: String, calibration: CalibrationStatus) {
        self.succeeded = succeeded
        self.message = message
        self.calibration = calibration
    }
}

public protocol MaintenanceServicing: Sendable {
    func calibrationStatus() async -> CalibrationStatus
    func performCalibration(_ command: CalibrationCommand) async -> MaintenanceResult
}

public actor BattMaintenanceService: MaintenanceServicing {
    private let runner: any CommandRunning
    private let battPath: String?
    private let timeout: TimeInterval

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        battPath: String? = SystemChargeController.installedBattPath,
        timeout: TimeInterval = 5
    ) {
        self.runner = runner
        self.battPath = battPath
        self.timeout = timeout
    }

    public func calibrationStatus() async -> CalibrationStatus {
        guard let battPath else { return .unavailable }
        let result = await runner.run(
            executable: battPath,
            arguments: ["status", "--json"],
            timeout: timeout
        )
        guard result.succeeded, let status = try? BattStatus.decode(result.output) else {
            return CalibrationStatus(
                isAvailable: false,
                message: result.timedOut
                    ? "The batt daemon did not respond before the timeout."
                    : "Calibration status could not be verified."
            )
        }
        guard status.compatibility.calibration == true, let calibration = status.calibration else {
            return CalibrationStatus(
                isAvailable: false,
                message: "This batt version does not report calibration support."
            )
        }
        return CalibrationStatus(
            isAvailable: true,
            phase: calibration.phase,
            isPaused: calibration.paused ?? false,
            canPause: calibration.canPause ?? false,
            canCancel: calibration.canCancel ?? false,
            message: calibration.message ?? ""
        )
    }

    public func performCalibration(_ command: CalibrationCommand) async -> MaintenanceResult {
        guard let battPath else {
            return MaintenanceResult(succeeded: false, message: CalibrationStatus.unavailable.message, calibration: .unavailable)
        }
        let before = await calibrationStatus()
        guard before.isAvailable else {
            return MaintenanceResult(succeeded: false, message: before.message, calibration: before)
        }
        if let rejection = rejectionReason(for: command, status: before) {
            return MaintenanceResult(succeeded: false, message: rejection, calibration: before)
        }

        let result = await runner.run(
            executable: battPath,
            arguments: ["calibration", command.rawValue],
            timeout: timeout
        )
        guard result.succeeded else {
            let message = result.timedOut
                ? "The calibration command timed out."
                : result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return MaintenanceResult(
                succeeded: false,
                message: message.isEmpty ? "The calibration command failed." : message,
                calibration: before
            )
        }

        let after = await calibrationStatus()
        guard after.isAvailable else {
            return MaintenanceResult(
                succeeded: false,
                message: "The command completed, but the resulting calibration state could not be verified.",
                calibration: after
            )
        }
        guard transitionVerified(command, status: after) else {
            return MaintenanceResult(
                succeeded: false,
                message: "The daemon did not confirm the requested calibration state.",
                calibration: after
            )
        }
        return MaintenanceResult(
            succeeded: true,
            message: "Calibration command verified.",
            calibration: after
        )
    }

    private func rejectionReason(for command: CalibrationCommand, status: CalibrationStatus) -> String? {
        switch command {
        case .start where status.isRunning:
            "Calibration is already running."
        case .pause where !status.canPause || status.isPaused:
            "Calibration cannot be paused in its current phase."
        case .resume where !status.isPaused:
            "Calibration is not paused."
        case .cancel where !status.canCancel:
            "Calibration cannot be cancelled in its current phase."
        default:
            nil
        }
    }

    private func transitionVerified(_ command: CalibrationCommand, status: CalibrationStatus) -> Bool {
        switch command {
        case .start: status.isRunning
        case .pause: status.isRunning && status.isPaused
        case .resume: status.isRunning && !status.isPaused
        case .cancel: !status.isRunning
        }
    }
}
