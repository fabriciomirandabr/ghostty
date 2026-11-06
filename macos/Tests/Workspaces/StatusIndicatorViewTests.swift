import SwiftUI
import Testing
@testable import Ghostty

struct StatusIndicatorViewTests {
    @Test func colors() {
        #expect(WorkspaceStatusColors.needsAttentionHex == 0xF5D90A)
        #expect(WorkspaceStatusColors.needsAttentionLightHex == 0x8A5A00)
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

    @Test func workspaceContextKeepsTheRunningCount() {
        #expect(StatusIndicatorView.badgeText(for: .running, context: .workspace, runningCount: 3) == "3")
        #expect(StatusIndicatorView.badgeText(for: .running, context: .workspace, runningCount: 1) == "1")
        #expect(StatusIndicatorView.badgeText(for: .running, context: .workspace, runningCount: 0) == nil)
        #expect(StatusIndicatorView.badgeText(for: .needsAttention, context: .workspace, runningCount: 2) == "2")
        #expect(StatusIndicatorView.badgeText(for: .needsAttention, context: .workspace, runningCount: 0) == nil)
        #expect(StatusIndicatorView.badgeText(for: .idle, context: .workspace, runningCount: 2) == nil)
        #expect(StatusIndicatorView.badgeText(for: .done, context: .workspace, runningCount: 2) == nil)
    }

    @Test func tabContextShowsDigitOnlyForTwoOrMorePanes() {
        #expect(StatusIndicatorView.badgeText(for: .running, context: .tab, runningCount: 1) == nil)
        #expect(StatusIndicatorView.badgeText(for: .running, context: .tab, runningCount: 0) == nil)
        #expect(StatusIndicatorView.badgeText(for: .running, context: .tab, runningCount: 2) == "2")
        #expect(StatusIndicatorView.badgeText(for: .running, context: .tab, runningCount: 9) == "9")
        #expect(StatusIndicatorView.badgeText(for: .needsAttention, context: .tab, runningCount: 2) == nil)
        #expect(StatusIndicatorView.badgeText(for: .done, context: .tab, runningCount: 2) == nil)
        #expect(StatusIndicatorView.badgeText(for: .idle, context: .tab, runningCount: 0) == nil)
    }

    @Test func pillDigitFollowsTheTabRunningCount() {
        let split = WorkspaceTitlebarTab(id: UUID(), title: "api", state: .running, runningCount: 2)
        let single = WorkspaceTitlebarTab(id: UUID(), title: "api", state: .running, runningCount: 1)
        let attention = WorkspaceTitlebarTab(id: UUID(), title: "api", state: .needsAttention, runningCount: 2)
        #expect(WorkspaceTabPill.indicatorText(for: split) == "2")
        #expect(WorkspaceTabPill.indicatorText(for: single) == nil)
        #expect(WorkspaceTabPill.indicatorText(for: attention) == nil)
    }

    @Test(arguments: [
        (SurfaceActivityState.idle, WorkspaceTabPill.Indicator?.none),
        (.running, .some(.ring)),
        (.needsAttention, .some(.dot)),
        (.done, .some(.check)),
    ])
    func pillIndicatorMapsState(state: SurfaceActivityState, expected: WorkspaceTabPill.Indicator?) {
        #expect(WorkspaceTabPill.indicator(for: state) == expected)
    }

    @Test(arguments: [
        SurfaceActivityState.idle, .running, .done, .needsAttention,
    ])
    func singlePaneTabsShowNoDigit(state: SurfaceActivityState) {
        #expect(StatusIndicatorView.badgeText(for: state, context: .tab, runningCount: 1) == nil)
    }
}
