import SwiftUI
import Testing
@testable import Ghostty

@MainActor
struct SplitPaneHeaderTests {
    @Test func headerOnlyForSplitsUnderWorkspacesStyle() {
        #expect(SplitPaneHeader.isVisible(isSplit: true, style: .workspaces))
        #expect(!SplitPaneHeader.isVisible(isSplit: false, style: .workspaces))
    }

    @Test func headerHiddenUnderOtherStyles() {
        for style in [Ghostty.Config.MacOSTitlebarStyle.native, .transparent, .tabs, .hidden] {
            #expect(!SplitPaneHeader.isVisible(isSplit: true, style: style))
        }
    }

    @Test func headerIsTwentyFourPointsTall() {
        #expect(SplitPaneHeaderView.height == 24)

        let host = NSHostingView(rootView: SplitPaneHeaderView(title: "api", isActive: true, onClose: {}))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height == 24)
    }

    @Test func closeActionIsTheOneHandedToTheHeader() {
        var closed = 0
        let header = SplitPaneHeaderView(title: "api", isActive: false, onClose: { closed += 1 })
        header.onClose()
        header.onClose()
        #expect(closed == 2)
        #expect(header.title == "api")
        #expect(!header.isActive)
    }

    @Test func activeLineIsDistinctFromInactive() {
        let dark = SplitPaneHeaderPalette(colorScheme: .dark)
        #expect(dark.activeBackground != dark.background)
        #expect(dark.activeText != dark.text)
    }
}
