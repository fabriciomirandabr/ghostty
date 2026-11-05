import Foundation
import GhosttyKit
import Testing
@testable import Ghostty

struct GhosttyAppActionTests {
    @Test func commandStartedSetsRunning() {
        let now = Date(timeIntervalSinceReferenceDate: 2_000)
        let signals = SurfaceActivityState.Signals().applying(.commandStarted, at: now)
        #expect(signals.state(at: now) == .running)
    }

    @Test func gotoTabPerformableInWorkspaceWindow() {
        let performable = WorkspaceTabNavigation.isGotoTabPerformable

        #expect(performable(0, true))
        #expect(performable(1, true))
        #expect(!performable(0, false))
        #expect(!performable(1, false))
        #expect(performable(2, false))
    }

    @Test func workspaceActionsReturnFalseWithoutWorkspaceWindow() {
        var target = ghostty_target_s()
        target.tag = GHOSTTY_TARGET_APP
        var posted = 0
        let name = Notification.Name("test.workspace-action.\(UUID().uuidString)")
        let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
            posted += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        #expect(!Ghostty.App.workspaceAction(target: target, name: name))
        #expect(posted == 0)
    }

    @Test func commandStartedKeepsBellAttention() {
        let now = Date(timeIntervalSinceReferenceDate: 2_000)
        let signals = SurfaceActivityState.Signals()
            .applying(.bell, at: now)
            .applying(.commandStarted, at: now)
        #expect(signals.state(at: now) == .needsAttention)
    }
}
