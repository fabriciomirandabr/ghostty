//
//  CommandPaletteTests.swift
//  GhosttyTests
//
//  Tests for command palette query filtering and match ranking.
//

import Testing
import SwiftUI
@testable import Ghostty

struct CommandPaletteWorkspaceEntriesTests {
    @Test(arguments: [
        "new_workspace", "close_workspace", "goto_workspace", "previous_workspace",
        "next_workspace", "toggle_workspace_overview", "toggle_workspace_switcher",
        "toggle_activity_popover",
    ])
    func workspaceEntriesAreOnlyVisibleInWorkspaceWindows(actionKey: String) {
        #expect(Ghostty.Command.isVisibleInPalette(actionKey: actionKey, inWorkspaceWindow: true))
        #expect(!Ghostty.Command.isVisibleInPalette(actionKey: actionKey, inWorkspaceWindow: false))
    }

    @Test func otherEntriesAreAlwaysVisible() {
        for key in ["new_tab", "prompt_tab_title", "clear_screen", "new_window"] {
            #expect(Ghostty.Command.isVisibleInPalette(actionKey: key, inWorkspaceWindow: false))
            #expect(Ghostty.Command.isVisibleInPalette(actionKey: key, inWorkspaceWindow: true))
        }
    }
}

struct CommandPaletteFilterTests {
    private func option(
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        leadingColor: Color? = nil,
        sortKey: ObjectIdentifier? = nil
    ) -> CommandOption {
        CommandOption(
            title: title,
            subtitle: subtitle,
            description: description,
            leadingColor: leadingColor,
            sortKey: sortKey
        ) {}
    }

    /// Title matches outrank subtitle matches, which outrank description
    /// matches. Options that don't match at all are dropped.
    @Test func textMatchTiers() {
        let byDescription = option(title: "Alpha", description: "make it fast")
        let bySubtitle = option(title: "Beta", subtitle: "fast scrolling")
        let byTitle = option(title: "Fast Redraw")
        let noMatch = option(title: "Quit")

        let results = [noMatch, byDescription, bySubtitle, byTitle]
            .filteredAndSorted(query: "fast")

        #expect(results == [byTitle, bySubtitle, byDescription])
    }

    /// Options with equal scores keep their original relative order.
    @Test func tiesPreserveOriginalOrder() {
        let first = option(title: "New Window")
        let second = option(title: "New Tab")

        #expect([first, second].filteredAndSorted(query: "new") == [first, second])
        #expect([second, first].filteredAndSorted(query: "new") == [second, first])
    }

    /// Equal titles use their sort keys independent of input order.
    @Test func equalTitlesUseSortKey() {
        let firstKey = NSObject()
        let secondKey = NSObject()
        let first = option(
            title: "Focus: Shell",
            subtitle: "/tmp",
            sortKey: ObjectIdentifier(firstKey)
        )
        let second = option(
            title: "Focus: Shell",
            subtitle: "/tmp",
            sortKey: ObjectIdentifier(secondKey)
        )

        let forward = sortedTerminalPaletteOptions([first, second])
        let reverse = sortedTerminalPaletteOptions([second, first])
        #expect(forward == reverse)
    }
}
