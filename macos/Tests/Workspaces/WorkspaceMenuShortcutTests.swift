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

    @Test func newWorkspaceUsesCommandGUnderWorkspacesStyle() throws {
        let config = try TemporaryConfig("macos-titlebar-style = workspaces")
        let item = sync(config, action: "new_workspace")

        #expect(item.keyEquivalent == "g")
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @Test func switcherUsesCommandKUnderWorkspacesStyle() throws {
        let config = try TemporaryConfig("macos-titlebar-style = workspaces")
        let item = sync(config, action: "toggle_workspace_switcher")

        #expect(item.keyEquivalent == "k")
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @Test func newWorkspaceHasNoShortcutWithoutTheStyle() throws {
        let config = try TemporaryConfig("")
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
