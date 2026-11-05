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
