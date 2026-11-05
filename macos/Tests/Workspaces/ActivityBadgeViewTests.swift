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

    @Test func displayTextCapsLargeCounts() {
        #expect(ActivityBadgeView.displayText(runningCount: 0) == "0")
        #expect(ActivityBadgeView.displayText(runningCount: 7) == "7")
        #expect(ActivityBadgeView.displayText(runningCount: 99) == "99")
        #expect(ActivityBadgeView.displayText(runningCount: 100) == "99+")
    }
}
