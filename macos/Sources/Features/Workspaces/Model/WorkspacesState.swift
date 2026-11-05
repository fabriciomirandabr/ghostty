import AppKit

struct WorkspacesState<ViewType: NSView & Codable & Identifiable>: Codable {
    let selectedWorkspace: String
    let workspaces: [WorkspaceState<ViewType>]
}

struct WorkspaceState<ViewType: NSView & Codable & Identifiable>: Codable {
    let id: String
    let name: String
    let directory: String
    let isDefault: Bool
    let selectedTab: String
    let tabs: [WorkspaceTabState<ViewType>]
}

struct WorkspaceTabState<ViewType: NSView & Codable & Identifiable>: Codable {
    let id: String
    let titleOverride: String?
    let focusedSurface: String?
    let surfaceTree: SplitTree<ViewType>
}

extension WorkspaceTabState where ViewType.ID == UUID {
    init(_ tab: WorkspaceTab<ViewType>) {
        self.init(
            id: tab.id.uuidString,
            titleOverride: tab.titleOverride,
            focusedSurface: tab.focusedSurfaceID?.uuidString,
            surfaceTree: tab.tree
        )
    }
}

extension WorkspaceState where ViewType.ID == UUID {
    init(_ workspace: Workspace<ViewType>) {
        self.init(
            id: workspace.id.uuidString,
            name: workspace.name,
            directory: workspace.directory.path,
            isDefault: workspace.isDefault,
            selectedTab: workspace.selectedTabID.uuidString,
            tabs: workspace.tabs.map(WorkspaceTabState.init)
        )
    }
}

extension WorkspaceTab where ViewType.ID == UUID {
    init?(restoring state: WorkspaceTabState<ViewType>) {
        guard let id = UUID(uuidString: state.id) else { return nil }
        self.init(
            id: id,
            titleOverride: state.titleOverride,
            tree: state.surfaceTree,
            focusedSurfaceID: state.focusedSurface.flatMap { UUID(uuidString: $0) }
        )
    }
}

extension Workspace where ViewType.ID == UUID {
    init?(
        restoring state: WorkspaceState<ViewType>,
        isDefault: Bool,
        makeReplacementTab: () -> WorkspaceTab<ViewType>
    ) {
        guard let id = UUID(uuidString: state.id) else { return nil }

        var tabs = state.tabs.compactMap { WorkspaceTab(restoring: $0) }
        if tabs.isEmpty {
            tabs = [makeReplacementTab()]
        }

        let selected = UUID(uuidString: state.selectedTab)
            .flatMap { selectedID in tabs.first { $0.id == selectedID }?.id }
            ?? tabs[0].id

        self.init(
            id: id,
            name: state.name,
            directory: URL(fileURLWithPath: state.directory),
            isDefault: isDefault,
            tabs: tabs,
            selectedTabID: selected
        )
    }
}
