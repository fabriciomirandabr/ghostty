import Testing
@testable import Ghostty

@MainActor
struct WorkspaceNotificationAuthorizationTests {
    private func requests(workspace: Bool, desktop: Bool) -> Int {
        var count = 0
        WorkspaceJobNotificationCenterSink.requestAuthorizationIfEnabled(
            workspaceNotifications: workspace,
            desktopNotifications: desktop,
            request: { count += 1 })
        return count
    }

    @Test func requestsOnlyWhenWorkspaceNotificationsAreOn() {
        #expect(requests(workspace: true, desktop: true) == 1)
        #expect(requests(workspace: false, desktop: true) == 0)
        #expect(requests(workspace: false, desktop: false) == 0)
    }

    @Test func desktopNotificationsOffNeverRequests() {
        #expect(requests(workspace: true, desktop: false) == 0)
    }
}
