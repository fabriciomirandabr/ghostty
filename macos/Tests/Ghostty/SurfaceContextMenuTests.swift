import AppKit
import SwiftUI
import Testing
@testable import Ghostty

@MainActor
struct SurfaceContextMenuTests {
    private static let shortcuts: [String: KeyboardShortcut] = [
        "new_tab": KeyboardShortcut("t", modifiers: .command),
        "new_split:right": KeyboardShortcut("d", modifiers: .command),
        "new_split:down": KeyboardShortcut("d", modifiers: [.command, .shift]),
        "copy_to_clipboard": KeyboardShortcut("c", modifiers: .command),
        "paste_from_clipboard": KeyboardShortcut("v", modifiers: .command),
        "select_all": KeyboardShortcut("a", modifiers: .command),
        "close_surface": KeyboardShortcut("w", modifiers: .command),
    ]

    private static func entries(
        workspace: Bool,
        hasSelection: Bool = true,
        isReadonly: Bool = false,
        table: [String: KeyboardShortcut] = SurfaceContextMenuTests.shortcuts
    ) -> [SurfaceContextMenu.Entry] {
        SurfaceContextMenu.entries(
            context: .init(
                hasSelection: hasSelection,
                isReadonly: isReadonly,
                isWorkspaceWindow: workspace),
            shortcut: { table[$0] })
    }

    private static func items(_ entries: [SurfaceContextMenu.Entry]) -> [SurfaceContextMenu.Item] {
        entries.compactMap {
            if case .item(let item) = $0 { return item }
            return nil
        }
    }

    private static func item(
        _ title: String,
        in entries: [SurfaceContextMenu.Entry]
    ) -> SurfaceContextMenu.Item? {
        items(entries).first { $0.title == title }
    }

    private static func titles(_ entries: [SurfaceContextMenu.Entry]) -> [String] {
        entries.map {
            switch $0 {
            case .item(let item): item.title
            case .separator: "-"
            }
        }
    }

    @Test func workspaceWindowOrderAndTitles() {
        let entries = Self.entries(workspace: true)

        #expect(Self.titles(entries) == [
            "New Terminal", "Split Terminal", "Split Down", "Split Left", "Split Up", "-",
            "Copy", "Copy as HTML", "Paste", "Select All", "-",
            "Clear", "Kill Terminal", "-",
            "Reset Terminal", "Toggle Terminal Inspector", "Terminal Read-only", "-",
            "Rename Terminal…", "Change Terminal Title…",
        ])

        let expected: [(String, Selector, String?)] = [
            ("New Terminal", #selector(Ghostty.SurfaceView.newTerminalFromContextMenu(_:)), "new_tab"),
            ("Split Terminal", #selector(Ghostty.SurfaceView.splitRight(_:)), "new_split:right"),
            ("Split Down", #selector(Ghostty.SurfaceView.splitDown(_:)), "new_split:down"),
            ("Split Left", #selector(Ghostty.SurfaceView.splitLeft(_:)), "new_split:left"),
            ("Split Up", #selector(Ghostty.SurfaceView.splitUp(_:)), "new_split:up"),
            ("Copy", #selector(Ghostty.SurfaceView.copy(_:)), "copy_to_clipboard"),
            ("Copy as HTML", #selector(Ghostty.SurfaceView.copyAsHTMLFromContextMenu(_:)), "copy_to_clipboard:html"),
            ("Paste", #selector(Ghostty.SurfaceView.paste(_:)), "paste_from_clipboard"),
            ("Select All", #selector(Ghostty.SurfaceView.selectAll(_:)), "select_all"),
            ("Clear", #selector(Ghostty.SurfaceView.clearScreenFromContextMenu(_:)), "clear_screen"),
            ("Kill Terminal", #selector(Ghostty.SurfaceView.closeSurface(_:)), "close_surface"),
            ("Reset Terminal", #selector(Ghostty.SurfaceView.resetTerminal(_:)), "reset"),
            ("Toggle Terminal Inspector", #selector(Ghostty.SurfaceView.toggleTerminalInspector(_:)), "inspector:toggle"),
            ("Terminal Read-only", #selector(Ghostty.SurfaceView.toggleReadonly(_:)), "toggle_readonly"),
            ("Rename Terminal…", #selector(Ghostty.SurfaceView.renameTerminalFromContextMenu(_:)), "prompt_tab_title"),
            ("Change Terminal Title…", #selector(Ghostty.SurfaceView.changeTitle(_:)), "prompt_surface_title"),
        ]
        let items = Self.items(entries)
        #expect(items.count == expected.count)
        for (item, row) in zip(items, expected) {
            #expect(item.title == row.0)
            #expect(item.selector == row.1)
            #expect(item.bindingAction == row.2)
        }
    }

    @Test func otherWindowUsesUpstreamTitles() {
        let entries = Self.entries(workspace: false)

        #expect(Self.titles(entries) == [
            "Copy", "Paste", "-",
            "Split Right", "Split Left", "Split Down", "Split Up", "-",
            "Close Split", "-",
            "Reset Terminal", "Toggle Terminal Inspector", "Terminal Read-only", "-",
            "Change Tab Title...", "Change Terminal Title...",
        ])

        let selectors = Self.items(entries).map(\.selector)
        #expect(selectors == [
            #selector(Ghostty.SurfaceView.copy(_:)),
            #selector(Ghostty.SurfaceView.paste(_:)),
            #selector(Ghostty.SurfaceView.splitRight(_:)),
            #selector(Ghostty.SurfaceView.splitLeft(_:)),
            #selector(Ghostty.SurfaceView.splitDown(_:)),
            #selector(Ghostty.SurfaceView.splitUp(_:)),
            #selector(Ghostty.SurfaceView.closeSurface(_:)),
            #selector(Ghostty.SurfaceView.resetTerminal(_:)),
            #selector(Ghostty.SurfaceView.toggleTerminalInspector(_:)),
            #selector(Ghostty.SurfaceView.toggleReadonly(_:)),
            #selector(BaseTerminalController.changeTabTitle(_:)),
            #selector(Ghostty.SurfaceView.changeTitle(_:)),
        ])
        for item in Self.items(entries) {
            #expect(item.isEnabled)
        }
    }

    @Test func otherWindowHidesCopyWithoutSelection() {
        let entries = Self.entries(workspace: false, hasSelection: false)

        #expect(Self.titles(entries) == [
            "Paste", "-",
            "Split Right", "Split Left", "Split Down", "Split Up", "-",
            "Close Split", "-",
            "Reset Terminal", "Toggle Terminal Inspector", "Terminal Read-only", "-",
            "Change Tab Title...", "Change Terminal Title...",
        ])
    }

    @Test func otherWindowHasNoForkOnlyItems() {
        let titles = Self.titles(Self.entries(workspace: false))
        for forbidden in [
            "New Tab", "New Terminal", "Copy as HTML", "Select All", "Clear",
            "Kill Terminal", "Split Terminal", "Rename Terminal…",
        ] {
            #expect(!titles.contains(forbidden))
        }
    }

    @Test func dispatchedActionsMatchItemBindingActions() {
        let table = SurfaceContextMenu.dispatchedActions
        #expect(table.count == 4)
        let items = Self.items(Self.entries(workspace: true))
        for (selector, action) in table {
            let matching = items.filter { $0.selector == selector }
            #expect(matching.count == 1)
            #expect(matching.first?.bindingAction == action)
        }
        #expect(table[#selector(Ghostty.SurfaceView.newTerminalFromContextMenu(_:))] == "new_tab")
        #expect(table[#selector(Ghostty.SurfaceView.copyAsHTMLFromContextMenu(_:))] == "copy_to_clipboard:html")
        #expect(table[#selector(Ghostty.SurfaceView.clearScreenFromContextMenu(_:))] == "clear_screen")
        #expect(table[#selector(Ghostty.SurfaceView.renameTerminalFromContextMenu(_:))] == "prompt_tab_title")
    }

    @Test func shortcutsComeFromTheTable() {
        let entries = Self.entries(workspace: true)
        let expected: [(String, KeyboardShortcut)] = [
            ("New Terminal", KeyboardShortcut("t", modifiers: .command)),
            ("Split Terminal", KeyboardShortcut("d", modifiers: .command)),
            ("Split Down", KeyboardShortcut("d", modifiers: [.command, .shift])),
            ("Copy", KeyboardShortcut("c", modifiers: .command)),
            ("Paste", KeyboardShortcut("v", modifiers: .command)),
            ("Select All", KeyboardShortcut("a", modifiers: .command)),
            ("Kill Terminal", KeyboardShortcut("w", modifiers: .command)),
        ]
        for (title, shortcut) in expected {
            #expect(Self.item(title, in: entries)?.shortcut == shortcut)
        }
    }

    @Test func missingBindingShowsNoShortcut() {
        let workspace = Self.entries(workspace: true)
        for title in ["Clear", "Copy as HTML", "Split Left", "Split Up", "Reset Terminal", "Change Terminal Title…"] {
            let item = Self.item(title, in: workspace)
            #expect(item != nil)
            #expect(item?.shortcut == nil)
        }
        let stock = Self.entries(workspace: false)
        for title in ["Split Left", "Split Up", "Reset Terminal", "Change Terminal Title..."] {
            let item = Self.item(title, in: stock)
            #expect(item != nil)
            #expect(item?.shortcut == nil)
        }
    }

    @Test func clearShowsShortcutOnlyWhenBound() {
        var table = Self.shortcuts
        table["clear_screen"] = KeyboardShortcut("k", modifiers: .command)
        let bound = Self.entries(workspace: true, table: table)
        #expect(Self.item("Clear", in: bound)?.shortcut == KeyboardShortcut("k", modifiers: .command))
        let unbound = Self.entries(workspace: true)
        #expect(Self.item("Clear", in: unbound)?.shortcut == nil)
    }

    @Test func copyItemsFollowSelection() {
        let withoutSelection = Self.entries(workspace: true, hasSelection: false)
        for item in Self.items(withoutSelection) {
            let expected = item.title != "Copy" && item.title != "Copy as HTML"
            #expect(item.isEnabled == expected)
        }

        let withSelection = Self.entries(workspace: true, hasSelection: true)
        for item in Self.items(withSelection) {
            #expect(item.isEnabled)
        }
    }

    @Test func readonlyStateFollowsContext() {
        let on = Self.entries(workspace: true, isReadonly: true)
        #expect(Self.item("Terminal Read-only", in: on)?.state == .on)
        let off = Self.entries(workspace: true, isReadonly: false)
        #expect(Self.item("Terminal Read-only", in: off)?.state == .off)
        for item in Self.items(on) where item.title != "Terminal Read-only" {
            #expect(item.state == .off)
        }
    }

    @Test func bindingActionsForNewHandlers() {
        let entries = Self.entries(workspace: true)
        #expect(Self.item("Copy as HTML", in: entries)?.bindingAction == "copy_to_clipboard:html")
        #expect(Self.item("Clear", in: entries)?.bindingAction == "clear_screen")
        #expect(Self.item("New Terminal", in: entries)?.bindingAction == "new_tab")
        #expect(Self.item("Rename Terminal…", in: entries)?.bindingAction == "prompt_tab_title")
    }

    @Test func menuFromEntriesKeepsSeparators() {
        let entries = Self.entries(workspace: true)
        let menu = SurfaceContextMenu.menu(from: entries)

        #expect(menu.items.count == entries.count)
        #expect(menu.items.count == 20)
        let separators = menu.items.enumerated().filter { $0.element.isSeparatorItem }.map(\.offset)
        #expect(separators == [5, 10, 13, 17])
    }

    @Test func menuFromEntriesMapsKeyEquivalents() {
        let menu = SurfaceContextMenu.menu(from: Self.entries(workspace: true))

        let splitDown = menu.items.first { $0.title == "Split Down" }
        #expect(splitDown?.keyEquivalent == "d")
        #expect(splitDown?.keyEquivalentModifierMask == [.command, .shift])

        let clear = menu.items.first { $0.title == "Clear" }
        #expect(clear?.keyEquivalent == "")
    }

    @Test func menuFromEntriesMapsEnabledAndState() {
        let menu = SurfaceContextMenu.menu(from: Self.entries(workspace: true, hasSelection: false, isReadonly: true))

        #expect(menu.autoenablesItems == false)
        #expect(menu.items.first { $0.title == "Copy" }?.isEnabled == false)
        #expect(menu.items.first { $0.title == "Copy as HTML" }?.isEnabled == false)
        #expect(menu.items.first { $0.title == "Paste" }?.isEnabled == true)
        #expect(menu.items.first { $0.title == "Terminal Read-only" }?.state == .on)
        #expect(menu.items.first { $0.title == "Kill Terminal" }?.action == #selector(Ghostty.SurfaceView.closeSurface(_:)))
    }
}
