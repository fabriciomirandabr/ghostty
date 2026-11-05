import AppKit
import Testing
@testable import Ghostty

@MainActor
struct WorkspacesTerminalWindowTests {
    private func makeWindow() -> WorkspacesTerminalWindow {
        let window = WorkspacesTerminalWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func disallowsTabbing() {
        let window = makeWindow()
        window.tabbingMode = .automatic
        window.applyWorkspacesStyle()

        #expect(window.tabbingMode == .disallowed)
        #expect(window.titleVisibility == .hidden)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
    }

    @Test func keepsTrafficLightsVisible() {
        let window = makeWindow()
        window.applyWorkspacesStyle()

        #expect(window.styleMask.contains(.titled))
        #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
    }

    @Test func titleChangeKeepsTitleHidden() {
        let window = makeWindow()
        window.applyWorkspacesStyle()
        window.titleVisibility = .visible
        window.title = "changed"

        #expect(window.titleVisibility == .hidden)
    }

    @Test func contentLayoutRectCoversWholeFrame() {
        let window = makeWindow()
        window.applyWorkspacesStyle()

        #expect(window.contentLayoutRect.origin.y == 0)
        #expect(window.contentLayoutRect.height == window.frame.height)
    }

    @Test func trafficLightsAreCenteredInTheBar() throws {
        let window = makeWindow()
        window.applyWorkspacesStyle()
        window.contentView = NSView()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        window.update()

        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let button = try #require(window.standardWindowButton(type))
            let superview = try #require(button.superview)
            let centerFromTop = window.frame.height - superview.convert(button.frame, to: nil).midY

            #expect(abs(centerFromTop - WorkspaceTitlebarMetrics.minimumHeight / 2) <= 1)
        }
    }

    @Test func rejectsTitlebarAccessories() {
        let window = makeWindow()
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = NSView()
        window.addTitlebarAccessoryViewController(accessory)

        #expect(window.titlebarAccessoryViewControllers.isEmpty)
        #expect(!window.supportsUpdateAccessory)
    }
}
