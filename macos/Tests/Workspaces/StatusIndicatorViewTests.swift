import SwiftUI
import Testing
@testable import Ghostty

struct StatusIndicatorViewTests {
    @Test func colors() {
        #expect(WorkspaceStatusColors.needsAttentionHex == 0xF5D90A)
        #expect(WorkspaceStatusColors.badgeDotHex == 0xFF7A1A)
        #expect(WorkspaceStatusColors.badgeDarkHex == 0x3A3A3A)
        #expect(WorkspaceStatusColors.badgeLightHex == 0xFFFFFF)
        #expect(WorkspaceStatusColors.badgeInkHex == 0x111111)
    }

    @Test func colorComponents() throws {
        let color = NSColor(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.needsAttentionHex)).usingColorSpace(.sRGB)
        let components = try #require(color)
        #expect(Int((components.redComponent * 255).rounded()) == 0xF5)
        #expect(Int((components.greenComponent * 255).rounded()) == 0xD9)
        #expect(Int((components.blueComponent * 255).rounded()) == 0x0A)
        #expect(components.alphaComponent == 1)
    }

    @Test(arguments: [
        (SurfaceActivityState.idle, "Idle"),
        (.done, "Done"),
        (.running, "Running"),
        (.needsAttention, "Needs you"),
    ])
    func accessibilityLabels(state: SurfaceActivityState, expected: String) {
        #expect(StatusIndicatorView.accessibilityLabel(for: state) == expected)
    }

    @Test func badgeTextShowsCountOnlyWhileRunning() {
        #expect(StatusIndicatorView.badgeText(for: .running, runningCount: 3) == "3")
        #expect(StatusIndicatorView.badgeText(for: .running, runningCount: 1) == "1")
        #expect(StatusIndicatorView.badgeText(for: .running, runningCount: 0) == nil)
        #expect(StatusIndicatorView.badgeText(for: .idle, runningCount: 2) == nil)
        #expect(StatusIndicatorView.badgeText(for: .needsAttention, runningCount: 2) == nil)
        #expect(StatusIndicatorView.badgeText(for: .done, runningCount: 2) == nil)
    }
}
