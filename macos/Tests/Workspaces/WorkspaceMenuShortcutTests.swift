import AppKit
import Testing
@testable import Ghostty

@MainActor
struct WorkspaceMenuShortcutTests {
    private func sync(_ config: Ghostty.Config, action: String) -> NSMenuItem {
        let item = NSMenuItem(title: "Item", action: nil, keyEquivalent: "")
        let manager = Ghostty.MenuShortcutManager()
        manager.reset()
        manager.syncMenuShortcut(config, action: action, menuItem: item)
        return item
    }

    @Test(arguments: ["new_workspace", "toggle_workspace_switcher", "toggle_workspace_overview"])
    func performableDefaultsHaveNoMenuShortcut(action: String) throws {
        let config = try TemporaryConfig("")
        let item = sync(config, action: action)

        #expect(item.keyEquivalent.isEmpty)
        #expect(item.keyEquivalentModifierMask.isEmpty)
    }

    @Test func newWorkspaceHasNoShortcutWithoutWindowDecorations() throws {
        let config = try TemporaryConfig("window-decoration = none")
        let item = sync(config, action: "new_workspace")

        #expect(item.keyEquivalent.isEmpty)
        #expect(item.keyEquivalentModifierMask.isEmpty)
    }

    @Test func newWorkspaceHasNoShortcutWhenOptedOutOfTheStyle() throws {
        let config = try TemporaryConfig("macos-titlebar-style = tabs")
        let item = sync(config, action: "new_workspace")

        #expect(item.keyEquivalent.isEmpty)
        #expect(item.keyEquivalentModifierMask.isEmpty)
    }

    @Test func userKeybindWinsOverWorkspaceDefault() throws {
        let config = try TemporaryConfig("""
        macos-titlebar-style = workspaces
        keybind = super+g=unbind
        """)
        let item = sync(config, action: "new_workspace")

        #expect(item.keyEquivalent.isEmpty)
    }
}
