import Foundation
import UserNotifications

@MainActor
final class WorkspaceJobNotificationCenterSink: WorkspaceJobNotificationSink {
    static let workspaceUserInfoKey = "workspace"

    static func requestAuthorizationIfEnabled(
        workspaceNotifications: Bool,
        desktopNotifications: Bool,
        request: () -> Void = WorkspaceJobNotificationCenterSink.requestAuthorization
    ) {
        guard WorkspaceJobNotifier.isEnabled(
            workspaceNotifications: workspaceNotifications,
            desktopNotifications: desktopNotifications) else { return }
        request()
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            guard let error else { return }
            Ghostty.logger.error("Error requesting notification authorization: \(error, privacy: .public)")
        }
    }

    func post(_ notification: WorkspaceJobNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = UNNotificationSound.default
        content.threadIdentifier = notification.threadIdentifier
        content.categoryIdentifier = Ghostty.userNotificationCategory
        content.userInfo = [
            "surface": notification.surfaceID.uuidString,
            Self.workspaceUserInfoKey: notification.workspaceID.uuidString,
            "requireFocus": false,
        ]

        let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            Ghostty.logger.error("Error scheduling workspace notification: \(error, privacy: .public)")
        }
    }

    func retract(identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
