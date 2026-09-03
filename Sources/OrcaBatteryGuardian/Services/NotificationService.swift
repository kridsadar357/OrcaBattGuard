import Foundation
import UserNotifications

public protocol GuardianNotifying {
    func requestAuthorization()
    func notify(title: String, body: String)
}

public final class UserNotificationService: GuardianNotifying {
    public init() {}

    public func requestAuthorization() {
        guard isRunningFromAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func notify(title: String, body: String) {
        guard isRunningFromAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
