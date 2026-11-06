import SwiftUI
import Testing
@testable import Ghostty

@MainActor
struct SplitPaneHeaderTests {
    @Test func headerOnlyForSplitsUnderWorkspacesStyle() {
        #expect(SplitPaneHeader.isVisible(isSplit: true, windowDecorations: true, style: .workspaces))
        #expect(!SplitPaneHeader.isVisible(isSplit: false, windowDecorations: true, style: .workspaces))
    }

    @Test func headerHiddenUnderOtherStyles() {
        for style in [Ghostty.Config.MacOSTitlebarStyle.native, .transparent, .tabs, .hidden] {
            #expect(!SplitPaneHeader.isVisible(isSplit: true, windowDecorations: true, style: style))
        }
    }

    @Test func headerHiddenWithoutWindowDecorations() throws {
        #expect(!SplitPaneHeader.isVisible(isSplit: true, windowDecorations: false, style: .workspaces))

        let config = try TemporaryConfig("window-decoration = none")
        #expect(config.macosTitlebarStyle == .workspaces)
        #expect(!config.usesWorkspaceWindow)
        #expect(!SplitPaneHeader.isVisible(
            isSplit: true,
            windowDecorations: config.windowDecorations,
            style: config.macosTitlebarStyle))
    }

    @Test(arguments: ["auto", "client", "server"])
    func decoratedWindowsUseTheWorkspaceWindow(decoration: String) throws {
        let config = try TemporaryConfig("window-decoration = \(decoration)")
        #expect(config.usesWorkspaceWindow)
    }

    @Test func headerIsTwentyFourPointsTall() {
        #expect(SplitPaneHeaderView.height == 24)

        let host = NSHostingView(rootView: SplitPaneHeaderView(title: "api", state: .running, isActive: true, onClose: {}))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height == 24)
    }

    @Test func closeActionIsTheOneHandedToTheHeader() {
        var closed = 0
        let header = SplitPaneHeaderView(title: "api", state: .idle, isActive: false, onClose: { closed += 1 })
        header.onClose()
        header.onClose()
        #expect(closed == 2)
        #expect(header.title == "api")
        #expect(!header.isActive)
    }

    @Test(arguments: [
        (SurfaceActivityState.running, "Running"),
        (.needsAttention, "Needs you"),
        (.done, "Done"),
    ])
    func headerShowsStateGlyphWhenNotIdle(state: SurfaceActivityState, label: String) {
        #expect(SplitPaneHeaderView.showsIndicator(for: state))
        #expect(SplitPaneHeaderView.accessibilityLabel(title: "api", state: state) == "Pane api, \(label)")
    }

    @Test func idleHeaderHasNoGlyph() {
        #expect(!SplitPaneHeaderView.showsIndicator(for: .idle))
        #expect(SplitPaneHeaderView.accessibilityLabel(title: "api", state: .idle) == "Pane api")
    }

    @Test func glyphIsSmallAndCarriesNoDigit() {
        #expect(SplitPaneHeaderView.indicatorDiameter == 10)
        #expect(SplitPaneHeaderView.indicatorDiameter + 5 < SplitPaneHeaderView.height)
        #expect(StatusIndicatorView.badgeText(for: .running, context: .tab, runningCount: 1) == nil)
    }

    @Test func noTimersInSplitSources() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features")
        let files = [
            "Splits/SplitPaneHeaderView.swift",
            "Workspaces/Titlebar/WorkspaceTabPill.swift",
            "Workspaces/Titlebar/StatusIndicatorView.swift",
            "Workspaces/Overlays/WorkspaceOverlaySnapshot.swift",
            "Workspaces/Activity/WorkspaceActivityAggregator.swift",
            "Workspaces/Overlays/ActivityPopoverView.swift",
        ]
        let banned = ["Timer(", "Timer.", "DispatchSource", "asyncAfter", "withAnimation", ".animation("]
        for file in files {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for token in banned {
                #expect(!text.contains(token), "\(file) contains \(token)")
            }
        }
    }

    @Test func activeLineIsDistinctFromInactive() {
        let dark = SplitPaneHeaderPalette(colorScheme: .dark)
        #expect(dark.activeBackground != dark.background)
        #expect(dark.activeText != dark.text)
    }
}
