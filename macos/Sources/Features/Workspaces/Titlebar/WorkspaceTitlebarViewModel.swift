import AppKit
import Combine
import SwiftUI

struct WorkspaceTitlebarWorkspace: Identifiable, Equatable {
    let id: UUID
    var name: String
    var folder: String
    var isDefault: Bool
    var state: SurfaceActivityState
    var runningCount: Int
}

struct WorkspaceTitlebarTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var state: SurfaceActivityState
    var runningCount: Int
}

struct WorkspaceTitlebarSnapshot: Equatable {
    var workspaces: [WorkspaceTitlebarWorkspace] = []
    var selectedWorkspaceID: UUID?
    var tabs: [WorkspaceTitlebarTab] = []
    var selectedTabID: UUID?
    var badge = WorkspaceActivityAggregator.Summary(runningCount: 0, needsAttention: false)
    var fontSize: Int?
    var canSplit = false
}

enum SplitTerminalDirection: Equatable {
    case right
    case down

    init(modifiers: NSEvent.ModifierFlags) {
        self = modifiers.contains(.option) ? .down : .right
    }

    var bindingAction: String {
        switch self {
        case .right: "new_split:right"
        case .down: "new_split:down"
        }
    }
}

extension WorkspaceTitlebarSnapshot {
    @MainActor
    static func make<ViewType: NSView & Codable & Identifiable>(
        store: WorkspaceStore<ViewType>,
        homeDirectory: URL,
        fontSize: Int? = nil,
        canSplit: Bool = false,
        activity: (ViewType) -> SurfaceActivityState,
        surfaceTitle: (WorkspaceTab<ViewType>) -> String,
        surfacePwd: (WorkspaceTab<ViewType>) -> String? = { _ in nil }
    ) -> WorkspaceTitlebarSnapshot where ViewType.ID == UUID {
        func tabStates(_ workspace: Workspace<ViewType>) -> [[SurfaceActivityState]] {
            workspace.tabs.map { Array($0.tree).map(activity) }
        }

        let workspaces = store.workspaces.map { workspace -> WorkspaceTitlebarWorkspace in
            let states = tabStates(workspace)
            return WorkspaceTitlebarWorkspace(
                id: workspace.id,
                name: workspace.name,
                folder: WorkspaceTitlebarPath.abbreviate(workspace.directory.path, home: homeDirectory.path),
                isDefault: workspace.isDefault,
                state: WorkspaceActivityAggregator.workspaceState(states),
                runningCount: WorkspaceActivityAggregator.summary(states).runningCount
            )
        }

        var tabs: [WorkspaceTitlebarTab] = []
        if let selected = store.selectedWorkspace {
            tabs = selected.tabs.map { tab in
                let states = Array(tab.tree).map(activity)
                return WorkspaceTitlebarTab(
                    id: tab.id,
                    title: WorkspaceTabTitle.override(tab.titleOverride)
                        ?? WorkspaceTabTitle.resolve(title: surfaceTitle(tab), pwd: surfacePwd(tab)),
                    state: WorkspaceActivityAggregator.tabState(states),
                    runningCount: WorkspaceActivityAggregator.runningPaneCount(states)
                )
            }
        }

        return WorkspaceTitlebarSnapshot(
            workspaces: workspaces,
            selectedWorkspaceID: store.selectedWorkspaceID,
            tabs: tabs,
            selectedTabID: store.selectedWorkspace?.selectedTabID,
            badge: WorkspaceActivityAggregator.summary(store.workspaces.flatMap(tabStates)),
            fontSize: fontSize,
            canSplit: canSplit
        )
    }
}

enum WorkspaceTabTitle {
    static let placeholder = "👻"
    static let fallback = "Terminal"

    static func override(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    static func resolve(title: String, pwd: String?) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(placeholder) {
            text = String(text.dropFirst(placeholder.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !text.isEmpty { return text }

        if let pwd, !pwd.isEmpty {
            let folder = URL(fileURLWithPath: pwd).lastPathComponent
            if !folder.isEmpty { return folder }
        }
        return fallback
    }
}

enum WorkspaceTitlebarPath {
    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

struct WorkspaceTitlebarActions {
    var selectWorkspace: (UUID) -> Void = { _ in }
    var closeWorkspace: (UUID) -> Void = { _ in }
    var selectTab: (UUID) -> Void = { _ in }
    var closeTab: (UUID) -> Void = { _ in }
    var renameTab: (UUID, String) -> Void = { _, _ in }
    var newTab: () -> Void = {}
    var splitTerminal: (SplitTerminalDirection) -> Void = { _ in }
    var newWorkspace: () -> Void = {}
    var switchWorkspace: () -> Void = {}
    var showAll: () -> Void = {}
    var setFontSize: (Int) -> Void = { _ in }
    var toggleOverview: () -> Void = {}
    var badgeHoverChanged: (Bool) -> Void = { _ in }
}

struct WorkspaceMenuItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case workspace(UUID)
        case switchWorkspace
        case newWorkspace
        case newTerminal
        case closeWorkspace
        case showAll
        case fontSize
        case separator
    }

    let id: String
    let kind: Kind
    var title: String = ""
    var shortcut: String?
    var isEnabled = true
    var isActive = false
    var state: SurfaceActivityState = .idle
    var runningLabel: String?
    var runningCount = 0
    var folder: String?
    var showsClose = false
}

struct WorkspaceFontSizeOption: Identifiable, Equatable {
    let size: Int
    let isCurrent: Bool

    var id: Int { size }
}

@MainActor
final class WorkspaceTitlebarViewModel: ObservableObject {
    static let fontSizes = [12, 13, 14, 15, 16, 18]

    @Published private(set) var snapshot = WorkspaceTitlebarSnapshot()
    @Published var isMenuPresented = false {
        didSet {
            if !isMenuPresented { isFontSizeExpanded = false }
        }
    }
    @Published private(set) var isFontSizeExpanded = false
    @Published private(set) var renamingTabID: UUID?
    @Published var renameDraft = "" {
        didSet {
            if renameDraft.count > WorkspaceName.maxLength {
                renameDraft = String(renameDraft.prefix(WorkspaceName.maxLength))
            }
        }
    }
    @Published var isOverviewOpen = false
    @Published var fontFamily: String?

    var actions: WorkspaceTitlebarActions
    private let shortcut: (String) -> KeyboardShortcut?

    init(
        fontFamily: String? = nil,
        actions: WorkspaceTitlebarActions = WorkspaceTitlebarActions(),
        shortcut: @escaping (String) -> KeyboardShortcut?
    ) {
        self.fontFamily = fontFamily
        self.actions = actions
        self.shortcut = shortcut
    }

    func apply(_ newSnapshot: WorkspaceTitlebarSnapshot) {
        guard newSnapshot != snapshot else { return }
        snapshot = newSnapshot
        if let renamingTabID, !newSnapshot.tabs.contains(where: { $0.id == renamingTabID }) {
            cancelRename()
        }
    }

    var workspaces: [WorkspaceTitlebarWorkspace] { snapshot.workspaces }
    var tabs: [WorkspaceTitlebarTab] { snapshot.tabs }
    var selectedTabID: UUID? { snapshot.selectedTabID }
    var badge: WorkspaceActivityAggregator.Summary { snapshot.badge }
    var currentFontSize: Int? { snapshot.fontSize }

    var activeWorkspace: WorkspaceTitlebarWorkspace? {
        workspaces.first { $0.id == snapshot.selectedWorkspaceID }
    }

    var activeWorkspaceName: String {
        activeWorkspace?.name ?? ""
    }

    var fontSizeOptions: [WorkspaceFontSizeOption] {
        Self.fontSizes.map { WorkspaceFontSizeOption(size: $0, isCurrent: $0 == currentFontSize) }
    }

    var menuItems: [WorkspaceMenuItem] {
        var items = workspaces.enumerated().map { index, workspace in
            WorkspaceMenuItem(
                id: "workspace-\(workspace.id.uuidString)",
                kind: .workspace(workspace.id),
                title: workspace.name,
                shortcut: index < 9 ? shortcutText("goto_workspace:\(index + 1)") : nil,
                isActive: workspace.id == snapshot.selectedWorkspaceID,
                state: workspace.state,
                runningLabel: workspace.runningCount > 0 ? "\(workspace.runningCount) running" : nil,
                runningCount: workspace.runningCount,
                folder: workspace.folder,
                showsClose: !workspace.isDefault
            )
        }

        items.append(WorkspaceMenuItem(id: "separator-workspaces", kind: .separator))
        items.append(WorkspaceMenuItem(
            id: "switch-workspace",
            kind: .switchWorkspace,
            title: "Switch Workspace…",
            shortcut: shortcutText("toggle_workspace_switcher")
        ))
        items.append(WorkspaceMenuItem(
            id: "new-workspace",
            kind: .newWorkspace,
            title: "New Workspace…",
            shortcut: shortcutText("new_workspace")
        ))
        items.append(WorkspaceMenuItem(
            id: "new-terminal",
            kind: .newTerminal,
            title: "New Terminal",
            shortcut: shortcutText("new_tab")
        ))
        items.append(WorkspaceMenuItem(
            id: "close-workspace",
            kind: .closeWorkspace,
            title: "Close Workspace",
            shortcut: shortcutText("close_workspace"),
            isEnabled: activeWorkspace.map { !$0.isDefault } ?? false
        ))
        items.append(WorkspaceMenuItem(
            id: "show-all",
            kind: .showAll,
            title: "Show All",
            shortcut: shortcutText("toggle_workspace_overview")
        ))
        items.append(WorkspaceMenuItem(id: "separator-actions", kind: .separator))
        items.append(WorkspaceMenuItem(id: "font-size", kind: .fontSize, title: "Font Size"))
        return items
    }

    func toggleMenu() {
        isMenuPresented.toggle()
    }

    func dismissMenu() {
        isMenuPresented = false
    }

    func perform(_ item: WorkspaceMenuItem) {
        guard item.isEnabled else { return }

        switch item.kind {
        case .workspace(let id):
            dismissMenu()
            actions.selectWorkspace(id)

        case .switchWorkspace:
            dismissMenu()
            actions.switchWorkspace()

        case .newWorkspace:
            dismissMenu()
            actions.newWorkspace()

        case .newTerminal:
            dismissMenu()
            actions.newTab()

        case .closeWorkspace:
            guard let active = activeWorkspace, !active.isDefault else { return }
            dismissMenu()
            actions.closeWorkspace(active.id)

        case .showAll:
            dismissMenu()
            actions.showAll()

        case .fontSize:
            isFontSizeExpanded.toggle()

        case .separator:
            break
        }
    }

    func closeWorkspace(id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }), !workspace.isDefault else { return }
        dismissMenu()
        actions.closeWorkspace(id)
    }

    func chooseFontSize(_ size: Int) {
        guard Self.fontSizes.contains(size) else { return }
        actions.setFontSize(size)
    }

    func selectTab(_ id: UUID) {
        guard id != snapshot.selectedTabID else { return }
        actions.selectTab(id)
    }

    func closeTab(_ id: UUID) {
        actions.closeTab(id)
    }

    func newTab() {
        actions.newTab()
    }

    var canSplit: Bool { snapshot.canSplit }

    var splitTerminalTooltip: String {
        let right = shortcutText(SplitTerminalDirection.right.bindingAction).map { " (\($0))" } ?? ""
        let down = shortcutText(SplitTerminalDirection.down.bindingAction).map { " (\($0))" } ?? ""
        return "Split Terminal\(right). Option-click: Split Down\(down)"
    }

    func splitTerminal(_ direction: SplitTerminalDirection) {
        guard snapshot.canSplit else { return }
        actions.splitTerminal(direction)
    }

    func badgeTapped() {
        actions.toggleOverview()
    }

    func badgeHoverChanged(_ hovering: Bool) {
        actions.badgeHoverChanged(hovering)
    }

    func beginRename(tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        renamingTabID = tabID
        renameDraft = tab.title
    }

    func beginRenamingSelectedTab() {
        guard let selectedTabID else { return }
        beginRename(tabID: selectedTabID)
    }

    func commitRename() {
        guard let id = renamingTabID else { return }
        renamingTabID = nil
        let name = WorkspaceName.normalize(renameDraft)
        renameDraft = ""
        guard !name.isEmpty, name != tabs.first(where: { $0.id == id })?.title else { return }
        actions.renameTab(id, name)
    }

    func blurRename() {
        commitRename()
    }

    func cancelRename() {
        renamingTabID = nil
        renameDraft = ""
    }

    private func shortcutText(_ action: String) -> String? {
        shortcut(action)?.description
    }
}
