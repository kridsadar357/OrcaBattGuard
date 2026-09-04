import Foundation

public struct AppUpdateStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case notChecked
        case checking
        case upToDate
        case updateAvailable
        case noPublishedRelease
        case failed
    }

    public var state: State
    public var currentVersion: String
    public var latestVersion: String?
    public var releaseURL: URL?
    public var message: String

    public init(
        state: State, currentVersion: String, latestVersion: String? = nil,
        releaseURL: URL? = nil, message: String = ""
    ) {
        self.state = state
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
        self.message = message
    }
}

public protocol AppUpdateChecking: Sendable {
    func check(currentVersion: String) async -> AppUpdateStatus
}

public struct GitHubUpdateService: AppUpdateChecking {
    private let session: URLSession
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.github.com/repos/kridsadar357/OrcaBattGuard/releases/latest")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    public func check(currentVersion: String) async -> AppUpdateStatus {
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OrcaBatteryGuardian/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return failed(currentVersion, "The update server returned an unexpected response.")
            }
            if http.statusCode == 404 {
                return AppUpdateStatus(state: .noPublishedRelease, currentVersion: currentVersion)
            }
            guard http.statusCode == 200 else {
                return failed(currentVersion, "The update server returned an unexpected response.")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard !latest.isEmpty, let url = URL(string: release.htmlURL) else {
                return failed(currentVersion, "The latest release information is incomplete.")
            }
            return AppUpdateStatus(
                state: Self.isNewer(latest, than: currentVersion) ? .updateAvailable : .upToDate,
                currentVersion: currentVersion,
                latestVersion: latest,
                releaseURL: url
            )
        } catch {
            return failed(currentVersion, error.localizedDescription)
        }
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = numericParts(candidate)
        let currentParts = numericParts(current)
        for index in 0..<max(candidateParts.count, currentParts.count) {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }

    private func failed(_ currentVersion: String, _ message: String) -> AppUpdateStatus {
        AppUpdateStatus(state: .failed, currentVersion: currentVersion, message: message)
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
