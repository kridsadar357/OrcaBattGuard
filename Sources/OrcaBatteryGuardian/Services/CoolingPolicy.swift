import Foundation

public struct CoolingPauseEvaluation: Equatable, Sendable {
    public let startedAt: Date?
    public var isActive: Bool { startedAt != nil }
}

public struct CoolingPolicy: Sendable {
    public let resumeDeltaC: Double
    public let minimumPause: TimeInterval

    public init(resumeDeltaC: Double = 3, minimumPause: TimeInterval = 5 * 60) {
        self.resumeDeltaC = max(1, resumeDeltaC)
        self.minimumPause = max(0, minimumPause)
    }

    public func evaluate(
        temperatureC: Double?, pauseAtC: Double,
        startedAt: Date?, now: Date = Date()
    ) -> CoolingPauseEvaluation {
        guard let startedAt else {
            guard let temperatureC, temperatureC >= pauseAtC else {
                return CoolingPauseEvaluation(startedAt: nil)
            }
            return CoolingPauseEvaluation(startedAt: now)
        }

        guard now.timeIntervalSince(startedAt) >= minimumPause,
              let temperatureC,
              temperatureC <= pauseAtC - resumeDeltaC else {
            return CoolingPauseEvaluation(startedAt: startedAt)
        }
        return CoolingPauseEvaluation(startedAt: nil)
    }
}
