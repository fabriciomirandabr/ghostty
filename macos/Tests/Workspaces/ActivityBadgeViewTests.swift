import SwiftUI
import Testing
@testable import Ghostty

struct ActivityBadgeViewTests {
    @Test func accessibilityLabel() {
        #expect(
            ActivityBadgeView.accessibilityLabel(runningCount: 2, needsAttention: true)
                == "Workspaces overview: 2 running, attention needed"
        )
        #expect(
            ActivityBadgeView.accessibilityLabel(runningCount: 0, needsAttention: false)
                == "Workspaces"
        )
        #expect(
            ActivityBadgeView.accessibilityLabel(runningCount: 1, needsAttention: false)
                == "Workspaces overview: 1 running"
        )
        #expect(
            ActivityBadgeView.accessibilityLabel(runningCount: 0, needsAttention: true)
                == "Workspaces, attention needed"
        )
    }

    @Test func gridReplacesZeroCount() {
        #expect(ActivityBadgeView.showsGrid(runningCount: 0))
        #expect(!ActivityBadgeView.showsGrid(runningCount: 1))
        #expect(!ActivityBadgeView.showsGrid(runningCount: 100))
    }

    @Test func titlebarBadgeStyleInvertsWhileRunning() {
        #expect(
            ActivityBadgeView.badgeStyle(runningCount: 0)
                == WorkspaceBadgeStyle(fillHex: 0x3A3A3A, foregroundHex: 0xFFFFFF)
        )
        #expect(
            ActivityBadgeView.badgeStyle(runningCount: 1)
                == WorkspaceBadgeStyle(fillHex: 0xFFFFFF, foregroundHex: 0x111111)
        )
        #expect(
            ActivityBadgeView.badgeStyle(runningCount: 120)
                == ActivityBadgeView.badgeStyle(runningCount: 1)
        )
    }

    @Test func badgeStyleContrastsInLightMode() {
        let dark = WorkspaceBadgeStyle(fillHex: 0x3A3A3A, foregroundHex: 0xFFFFFF)
        #expect(ActivityBadgeView.badgeStyle(runningCount: 2, colorScheme: .light) == dark)
        #expect(WorkspaceBadgeStyle.make(for: .running, colorScheme: .light) == dark)
        #expect(WorkspaceBadgeStyle.make(for: .done, colorScheme: .light) == dark)
        #expect(
            WorkspaceBadgeStyle.make(for: .needsAttention, colorScheme: .light)
                == WorkspaceBadgeStyle.make(for: .needsAttention, colorScheme: .dark)
        )
        #expect(
            ActivityBadgeView.badgeStyle(runningCount: 2, colorScheme: .dark)
                == WorkspaceBadgeStyle(fillHex: 0xFFFFFF, foregroundHex: 0x111111)
        )
    }

    @Test(arguments: [
        (SurfaceActivityState.idle, UInt32(0x3A3A3A), UInt32(0xFFFFFF)),
        (.running, 0xFFFFFF, 0x111111),
        (.done, 0xFFFFFF, 0x111111),
        (.needsAttention, 0xF5D90A, 0x111111),
    ])
    func badgeStyleMapsStateToTokens(state: SurfaceActivityState, fill: UInt32, foreground: UInt32) {
        let style = WorkspaceBadgeStyle.make(for: state)
        #expect(style.fillHex == fill)
        #expect(style.foregroundHex == foreground)
    }

    @Test func displayTextCapsLargeCounts() {
        #expect(ActivityBadgeView.displayText(runningCount: 0) == "0")
        #expect(ActivityBadgeView.displayText(runningCount: 7) == "7")
        #expect(ActivityBadgeView.displayText(runningCount: 99) == "99")
        #expect(ActivityBadgeView.displayText(runningCount: 100) == "99+")
    }
}
