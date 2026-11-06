import SwiftUI
import Testing
@testable import Ghostty

@MainActor
struct WorkspaceTitlebarViewModelTests {
    private static let shortcuts: [String: KeyboardShortcut] = {
        var table: [String: KeyboardShortcut] = [
            "toggle_workspace_switcher": KeyboardShortcut("k", modifiers: .command),
            "new_workspace": KeyboardShortcut("g", modifiers: .command),
            "new_tab": KeyboardShortcut("t", modifiers: .command),
            "close_workspace": KeyboardShortcut("w", modifiers: [.command, .shift]),
            "toggle_workspace_overview": KeyboardShortcut("o", modifiers: .command),
        ]
        for index in 1...9 {
            table["goto_workspace:\(index)"] = KeyboardShortcut(
                KeyEquivalent(Character("\(index)")),
                modifiers: [.command, .option]
            )
        }
        return table
    }()

    private static func workspace(
        _ name: String,
        isDefault: Bool = false,
        state: SurfaceActivityState = .idle,
        running: Int = 0
    ) -> WorkspaceTitlebarWorkspace {
        WorkspaceTitlebarWorkspace(
            id: UUID(),
            name: name,
            folder: "~/\(name.lowercased())",
            isDefault: isDefault,
            state: state,
            runningCount: running
        )
    }

    private static func makeModel(
        workspaces: [WorkspaceTitlebarWorkspace],
        activeIndex: Int = 0,
        tabs: [WorkspaceTitlebarTab] = [],
        selectedTab: Int = 0,
        table: [String: KeyboardShortcut] = WorkspaceTitlebarViewModelTests.shortcuts
    ) -> WorkspaceTitlebarViewModel {
        let model = WorkspaceTitlebarViewModel(shortcut: { table[$0] })
        model.apply(WorkspaceTitlebarSnapshot(
            workspaces: workspaces,
            selectedWorkspaceID: workspaces[activeIndex].id,
            tabs: tabs,
            selectedTabID: tabs.isEmpty ? nil : tabs[selectedTab].id
        ))
        return model
    }

    private static func tab(_ title: String, state: SurfaceActivityState = .idle) -> WorkspaceTitlebarTab {
        WorkspaceTitlebarTab(id: UUID(), title: title, state: state)
    }

    @Test func menuItemsShape() {
        let workspaces = [
            Self.workspace("Default", isDefault: true),
            Self.workspace("api", state: .running, running: 2),
            Self.workspace("web"),
        ]
        let model = Self.makeModel(workspaces: workspaces, activeIndex: 1)
        let items = model.menuItems

        #expect(items.map(\.kind) == [
            .workspace(workspaces[0].id),
            .workspace(workspaces[1].id),
            .workspace(workspaces[2].id),
            .separator,
            .switchWorkspace,
            .newWorkspace,
            .newTerminal,
            .closeWorkspace,
            .showAll,
            .separator,
            .fontSize,
        ])
        #expect(items.map(\.title).filter { !$0.isEmpty } == [
            "Default", "api", "web",
            "Switch Workspace…", "New Workspace…", "New Terminal", "Close Workspace", "Show All", "Font Size",
        ])
        #expect(items.map(\.isActive).prefix(3) == [false, true, false])
        #expect(items[1].runningLabel == "2 running")
        #expect(items[0].runningLabel == nil)
        #expect(items[2].runningLabel == nil)
        #expect(items[1].folder == "~/api")
        #expect(items[1].state == .running)

        #expect(items[0].shortcut == Self.shortcuts["goto_workspace:1"]?.description)
        #expect(items[1].shortcut == "⌥⌘2")
        #expect(items[4].shortcut == Self.shortcuts["toggle_workspace_switcher"]?.description)
        #expect(items[5].shortcut == Self.shortcuts["new_workspace"]?.description)
        #expect(items[6].shortcut == Self.shortcuts["new_tab"]?.description)
        #expect(items[7].shortcut == Self.shortcuts["close_workspace"]?.description)
        #expect(items[8].shortcut == Self.shortcuts["toggle_workspace_overview"]?.description)
        #expect(items[10].shortcut == nil)
    }

    @Test func workspaceShortcutsOnlyForFirstNine() {
        let workspaces = (0..<11).map { Self.workspace("w\($0)", isDefault: $0 == 0) }
        var table = Self.shortcuts
        for index in 10...11 {
            table["goto_workspace:\(index)"] = KeyboardShortcut(KeyEquivalent("z"), modifiers: .command)
        }
        let items = Self.makeModel(workspaces: workspaces, table: table).menuItems
        let rows = items.prefix(11)

        #expect(rows.prefix(9).allSatisfy { $0.shortcut != nil })
        #expect(rows.suffix(2).allSatisfy { $0.shortcut == nil })
    }

    @Test func shortcutIsAbsentWhenConfigHasNone() {
        let model = Self.makeModel(workspaces: [Self.workspace("Default", isDefault: true)], table: [:])
        #expect(model.menuItems.allSatisfy { $0.shortcut == nil })
    }

    private static func splitModel(
        canSplit: Bool,
        table: [String: KeyboardShortcut]
    ) -> WorkspaceTitlebarViewModel {
        let model = WorkspaceTitlebarViewModel(shortcut: { table[$0] })
        let only = workspace("Default", isDefault: true)
        model.apply(WorkspaceTitlebarSnapshot(
            workspaces: [only],
            selectedWorkspaceID: only.id,
            canSplit: canSplit
        ))
        return model
    }

    private static let splitShortcuts: [String: KeyboardShortcut] = [
        "new_split:right": KeyboardShortcut("d", modifiers: .command),
        "new_split:down": KeyboardShortcut("d", modifiers: [.command, .shift]),
    ]

    @Test func splitDirectionFollowsOptionModifier() {
        #expect(SplitTerminalDirection(modifiers: []) == .right)
        #expect(SplitTerminalDirection(modifiers: [.command]) == .right)
        #expect(SplitTerminalDirection(modifiers: [.option]) == .down)
        #expect(SplitTerminalDirection(modifiers: [.option, .shift]) == .down)
        #expect(SplitTerminalDirection.right.bindingAction == "new_split:right")
        #expect(SplitTerminalDirection.down.bindingAction == "new_split:down")
    }

    @Test func splitTerminalForwardsDirection() {
        let model = Self.splitModel(canSplit: true, table: [:])
        var received: [SplitTerminalDirection] = []
        model.actions.splitTerminal = { received.append($0) }

        model.splitTerminal(SplitTerminalDirection(modifiers: []))
        model.splitTerminal(SplitTerminalDirection(modifiers: [.option]))

        #expect(received == [.right, .down])
    }

    @Test func splitTerminalIgnoredWithoutFocusedSurface() {
        let model = Self.splitModel(canSplit: false, table: [:])
        var received: [SplitTerminalDirection] = []
        model.actions.splitTerminal = { received.append($0) }

        model.splitTerminal(.right)

        #expect(model.canSplit == false)
        #expect(received.isEmpty)
    }

    @Test func splitTerminalTooltipShowsBothShortcuts() {
        let model = Self.splitModel(canSplit: true, table: Self.splitShortcuts)
        #expect(model.splitTerminalTooltip == "Split Terminal (⌘D). Option-click: Split Down (⇧⌘D)")
    }

    @Test func splitTerminalTooltipWithoutBindings() {
        let model = Self.splitModel(canSplit: true, table: [:])
        #expect(model.splitTerminalTooltip == "Split Terminal. Option-click: Split Down")
    }

    @Test func closeItemDisabledOnDefault() {
        let workspaces = [Self.workspace("Default", isDefault: true), Self.workspace("api")]

        let onDefault = Self.makeModel(workspaces: workspaces, activeIndex: 0).menuItems
        #expect(onDefault.first { $0.kind == .closeWorkspace }?.isEnabled == false)
        #expect(onDefault[0].showsClose == false)
        #expect(onDefault[1].showsClose == true)

        let onOther = Self.makeModel(workspaces: workspaces, activeIndex: 1).menuItems
        #expect(onOther.first { $0.kind == .closeWorkspace }?.isEnabled == true)
    }

    @Test func closeActionIgnoredOnDefault() {
        let workspaces = [Self.workspace("Default", isDefault: true), Self.workspace("api")]
        let model = Self.makeModel(workspaces: workspaces, activeIndex: 0)
        var closed: [UUID] = []
        model.actions.closeWorkspace = { closed.append($0) }

        if let item = model.menuItems.first(where: { $0.kind == .closeWorkspace }) {
            model.perform(item)
        }
        model.closeWorkspace(id: workspaces[0].id)
        #expect(closed.isEmpty)

        model.closeWorkspace(id: workspaces[1].id)
        #expect(closed == [workspaces[1].id])
    }

    @Test func performDispatchesAndDismissesMenu() {
        let workspaces = [Self.workspace("Default", isDefault: true), Self.workspace("api")]
        let model = Self.makeModel(workspaces: workspaces, activeIndex: 1)
        var log: [String] = []
        model.actions.selectWorkspace = { id in log.append(id == workspaces[0].id ? "select-default" : "select-other") }
        model.actions.newWorkspace = { log.append("new-workspace") }
        model.actions.newTab = { log.append("new-tab") }
        model.actions.switchWorkspace = { log.append("switch") }
        model.actions.showAll = { log.append("show-all") }
        model.actions.closeWorkspace = { _ in log.append("close") }

        for item in model.menuItems where item.kind != .separator && item.kind != .fontSize {
            model.isMenuPresented = true
            model.perform(item)
            #expect(model.isMenuPresented == false)
        }

        #expect(log == ["select-default", "select-other", "switch", "new-workspace", "new-tab", "close", "show-all"])
    }

    @Test func fontSizeRowTogglesSubmenuAndPicksSize() {
        let model = WorkspaceTitlebarViewModel(shortcut: { _ in nil })
        let only = Self.workspace("Default", isDefault: true)
        model.apply(WorkspaceTitlebarSnapshot(workspaces: [only], selectedWorkspaceID: only.id, fontSize: 14))
        var chosen: [Int] = []
        model.actions.setFontSize = { chosen.append($0) }

        #expect(model.fontSizeOptions.map(\.size) == [12, 13, 14, 15, 16, 18])
        #expect(model.fontSizeOptions.filter(\.isCurrent).map(\.size) == [14])

        model.isMenuPresented = true
        if let item = model.menuItems.first(where: { $0.kind == .fontSize }) {
            model.perform(item)
            #expect(model.isFontSizeExpanded)
            #expect(model.isMenuPresented)
        }

        model.chooseFontSize(16)
        model.chooseFontSize(17)
        #expect(chosen == [16])

        model.dismissMenu()
        #expect(model.isFontSizeExpanded == false)
    }

    @Test func renameApplyCancelBlur() {
        let tabs = [Self.tab("one"), Self.tab("two")]
        let model = Self.makeModel(workspaces: [Self.workspace("Default", isDefault: true)], tabs: tabs)
        var renamed: [(UUID, String)] = []
        model.actions.renameTab = { renamed.append(($0, $1)) }

        model.beginRename(tabID: tabs[0].id)
        #expect(model.renamingTabID == tabs[0].id)
        #expect(model.renameDraft == "one")
        model.renameDraft = String(repeating: "x", count: 60)
        #expect(model.renameDraft.count == 40)
        model.commitRename()
        #expect(model.renamingTabID == nil)
        #expect(renamed.count == 1)
        #expect(renamed[0].0 == tabs[0].id)
        #expect(renamed[0].1 == String(repeating: "x", count: 40))

        model.beginRename(tabID: tabs[1].id)
        model.renameDraft = "changed"
        model.cancelRename()
        #expect(model.renamingTabID == nil)
        #expect(renamed.count == 1)

        model.beginRename(tabID: tabs[1].id)
        model.renameDraft = "  blurred  "
        model.blurRename()
        model.blurRename()
        #expect(renamed.count == 2)
        #expect(renamed[1].0 == tabs[1].id)
        #expect(renamed[1].1 == "blurred")
    }

    @Test func renameWithEmptyOrUnchangedNameKeepsTitle() {
        let tabs = [Self.tab("one")]
        let model = Self.makeModel(workspaces: [Self.workspace("Default", isDefault: true)], tabs: tabs)
        var count = 0
        model.actions.renameTab = { _, _ in count += 1 }

        model.beginRename(tabID: tabs[0].id)
        model.renameDraft = "   "
        model.commitRename()

        model.beginRename(tabID: tabs[0].id)
        model.commitRename()

        #expect(count == 0)
    }

    @Test func f2StartsRenamingSelectedTab() {
        let tabs = [Self.tab("one"), Self.tab("two")]
        let model = Self.makeModel(workspaces: [Self.workspace("Default", isDefault: true)], tabs: tabs, selectedTab: 1)
        model.beginRenamingSelectedTab()
        #expect(model.renamingTabID == tabs[1].id)
        #expect(model.renameDraft == "two")
    }

    @Test func doubleClickSelectsTheTabAndStartsRenamingWithItsCurrentTitle() {
        let tabs = [Self.tab("one"), Self.tab("two")]
        let model = Self.makeModel(workspaces: [Self.workspace("Default", isDefault: true)], tabs: tabs)
        var selected: [UUID] = []
        model.actions.selectTab = { selected.append($0) }

        model.selectTab(tabs[1].id)
        model.beginRename(tabID: tabs[1].id)

        #expect(selected == [tabs[1].id])
        #expect(model.renamingTabID == tabs[1].id)
        #expect(model.renameDraft == "two")
        #expect(model.renameDraft == model.tabs[1].title)
    }

    @Test func renameCannotStartForUnknownTabOrWithoutSelection() {
        let model = Self.makeModel(workspaces: [Self.workspace("Default", isDefault: true)])
        model.beginRenamingSelectedTab()
        model.beginRename(tabID: UUID())
        #expect(model.renamingTabID == nil)
        #expect(model.renameDraft.isEmpty)
    }

    @Test func tabPillStateReflectsSelectionStatesAndTruncation() {
        let tabs = [Self.tab("one", state: .running), Self.tab("two", state: .needsAttention), Self.tab("three")]
        let model = Self.makeModel(workspaces: [Self.workspace("Default", isDefault: true)], tabs: tabs, selectedTab: 1)
        #expect(model.tabs.map(\.state) == [.running, .needsAttention, .idle])
        #expect(model.selectedTabID == tabs[1].id)

        var closed: [UUID] = []
        model.actions.closeTab = { closed.append($0) }
        model.closeTab(tabs[2].id)
        #expect(closed == [tabs[2].id])

        var created = 0
        model.actions.newTab = { created += 1 }
        model.newTab()
        #expect(created == 1)
        #expect(WorkspaceTabPill.maxWidth == 240)
        #expect(WorkspaceTabPill.isTruncated(naturalWidth: 300, visibleWidth: 200))
    }

    @Test func emptyOrBlankTitleOverrideIsTreatedAsAbsent() throws {
        let store = WorkspaceFixtures.makeStore()
        let workspaceID = store.workspaces[0].id
        let tabID = store.workspaces[0].tabs[0].id
        let homeDirectory = URL(fileURLWithPath: "/tmp/ws-home")

        for override in ["", "   ", "\n"] {
            store.updateTab(workspaceID: workspaceID, tabID: tabID) { $0.titleOverride = override }
            let titlebar = WorkspaceTitlebarSnapshot.make(
                store: store,
                homeDirectory: homeDirectory,
                activity: { _ in .idle },
                surfaceTitle: { _ in "shell" }
            )
            let overlay = store.overlaySnapshot { _ in
                WorkspaceSurfaceInfo(title: "shell", lastCommand: nil, state: .idle)
            }
            #expect(titlebar.tabs.map(\.title) == ["shell"])
            #expect(overlay.workspaces[0].tabs.map(\.title) == ["shell"])
        }

        store.updateTab(workspaceID: workspaceID, tabID: tabID) { $0.titleOverride = "build" }
        let titlebar = WorkspaceTitlebarSnapshot.make(
            store: store,
            homeDirectory: homeDirectory,
            activity: { _ in .idle },
            surfaceTitle: { _ in "shell" }
        )
        #expect(titlebar.tabs.map(\.title) == ["build"])
    }

    @Test func renamingEndsWhenTabDisappears() {
        let tabs = [Self.tab("one"), Self.tab("two")]
        let only = Self.workspace("Default", isDefault: true)
        let model = Self.makeModel(workspaces: [only], tabs: tabs)
        model.beginRename(tabID: tabs[1].id)

        model.apply(WorkspaceTitlebarSnapshot(
            workspaces: [only],
            selectedWorkspaceID: only.id,
            tabs: [tabs[0]],
            selectedTabID: tabs[0].id
        ))

        #expect(model.renamingTabID == nil)
    }

    @Test func tabActionsAreForwarded() {
        let tabs = [Self.tab("one"), Self.tab("two")]
        let model = Self.makeModel(workspaces: [Self.workspace("Default", isDefault: true)], tabs: tabs)
        var log: [String] = []
        model.actions.selectTab = { log.append($0 == tabs[1].id ? "select-two" : "select-other") }
        model.actions.closeTab = { log.append($0 == tabs[0].id ? "close-one" : "close-other") }
        model.actions.newTab = { log.append("new") }
        model.actions.toggleOverview = { log.append("overview") }
        model.actions.badgeHoverChanged = { log.append("hover-\($0)") }

        model.selectTab(tabs[0].id)
        model.selectTab(tabs[1].id)
        model.closeTab(tabs[0].id)
        model.newTab()
        model.badgeTapped()
        model.badgeHoverChanged(true)

        #expect(log == ["select-two", "close-one", "new", "overview", "hover-true"])
    }

    @Test func snapshotFromStoreAggregatesPerTab() throws {
        let store = WorkspaceFixtures.makeStore()
        let defaultViews = store.workspaces[0].surfaces
        let busyViews = [MockView(), MockView()]
        let attentionView = MockView()
        let workspace = try store.addWorkspace(
            name: "api",
            directory: URL(fileURLWithPath: "/tmp/ws-home/api"),
            makeTab: { WorkspaceFixtures.makeTab(views: busyViews) }
        )
        store.addTab(WorkspaceFixtures.makeTab(title: "renamed", views: [attentionView]), to: workspace.id)
        store.select(workspaceID: workspace.id)

        let states: [ObjectIdentifier: SurfaceActivityState] = [
            ObjectIdentifier(busyViews[0]): .running,
            ObjectIdentifier(busyViews[1]): .running,
            ObjectIdentifier(attentionView): .needsAttention,
            ObjectIdentifier(defaultViews[0]): .done,
        ]

        let snapshot = WorkspaceTitlebarSnapshot.make(
            store: store,
            homeDirectory: URL(fileURLWithPath: "/tmp/ws-home"),
            fontSize: 15,
            activity: { states[ObjectIdentifier($0)] ?? .idle },
            surfaceTitle: { _ in "shell" }
        )

        #expect(snapshot.workspaces.map(\.name) == ["Default", "api"])
        #expect(snapshot.workspaces.map(\.folder) == ["~", "~/api"])
        #expect(snapshot.workspaces.map(\.state) == [.done, .needsAttention])
        #expect(snapshot.workspaces.map(\.runningCount) == [0, 1])
        #expect(snapshot.selectedWorkspaceID == workspace.id)
        #expect(snapshot.tabs.map(\.title) == ["shell", "renamed"])
        #expect(snapshot.tabs.map(\.state) == [.running, .needsAttention])
        #expect(snapshot.badge == .init(runningCount: 1, needsAttention: true))
        #expect(snapshot.fontSize == 15)
    }

    @Test func tabTitleNeverShowsPlaceholderOrEmpty() {
        #expect(WorkspaceTabTitle.resolve(title: "👻", pwd: "/Users/x/Code/api") == "api")
        #expect(WorkspaceTabTitle.resolve(title: "", pwd: "/Users/x/Code/api/") == "api")
        #expect(WorkspaceTabTitle.resolve(title: "  \n", pwd: nil) == "Terminal")
        #expect(WorkspaceTabTitle.resolve(title: "👻", pwd: "") == "Terminal")
        #expect(WorkspaceTabTitle.resolve(title: "👻 vim", pwd: "/Users/x") == "vim")
        #expect(WorkspaceTabTitle.resolve(title: "👻 ", pwd: "/Users/x") == "x")
        #expect(WorkspaceTabTitle.resolve(title: "shell", pwd: "/Users/x") == "shell")
    }

    @Test func snapshotTabTitlesFallBackToFolderName() throws {
        let store = WorkspaceFixtures.makeStore()
        let snapshot = WorkspaceTitlebarSnapshot.make(
            store: store,
            homeDirectory: URL(fileURLWithPath: "/tmp/ws-home"),
            activity: { _ in .idle },
            surfaceTitle: { _ in "👻" },
            surfacePwd: { _ in "/tmp/ws-home/api" }
        )

        #expect(snapshot.tabs.map(\.title) == ["api"])
    }

    @Test func pathAbbreviation() {
        #expect(WorkspaceTitlebarPath.abbreviate("/Users/x", home: "/Users/x") == "~")
        #expect(WorkspaceTitlebarPath.abbreviate("/Users/x/Code/api", home: "/Users/x") == "~/Code/api")
        #expect(WorkspaceTitlebarPath.abbreviate("/Users/xy/Code", home: "/Users/x") == "/Users/xy/Code")
        #expect(WorkspaceTitlebarPath.abbreviate("/opt/api", home: "/Users/x") == "/opt/api")
    }

    @Test func truncationNeedsRealOverflow() {
        #expect(WorkspaceTabPill.isTruncated(naturalWidth: 120, visibleWidth: 100))
        #expect(!WorkspaceTabPill.isTruncated(naturalWidth: 100, visibleWidth: 100))
        #expect(!WorkspaceTabPill.isTruncated(naturalWidth: 100.3, visibleWidth: 100))
    }
}
