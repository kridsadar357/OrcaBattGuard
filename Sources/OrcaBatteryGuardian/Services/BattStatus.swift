import Foundation

struct BattStatus: Decodable, Sendable {
    struct Configuration: Decodable, Sendable {
        let enabled: Bool
        let upperLimitPercent: Int
        let lowerLimitPercent: Int
    }

    struct Compatibility: Decodable, Sendable {
        let chargingControl: Bool
        let calibration: Bool?
    }

    struct Calibration: Decodable, Sendable {
        let phase: String
        let paused: Bool?
        let canPause: Bool?
        let canCancel: Bool?
        let message: String?
    }

    let configuration: Configuration
    let compatibility: Compatibility
    let calibration: Calibration?

    static func decode(_ output: String) throws -> BattStatus {
        let status = try JSONDecoder().decode(Self.self, from: Data(output.utf8))
        let configuration = status.configuration
        guard (10...100).contains(configuration.upperLimitPercent),
              (0...100).contains(configuration.lowerLimitPercent),
              !configuration.enabled || configuration.lowerLimitPercent < configuration.upperLimitPercent else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid charge limits."))
        }
        return status
    }
}
