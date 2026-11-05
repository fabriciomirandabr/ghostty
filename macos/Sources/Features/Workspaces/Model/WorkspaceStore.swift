import AppKit

protocol WorkspaceStoreDelegate<ViewType>: AnyObject {
    associatedtype ViewType: NSView & Codable & Identifiable

    @MainActor func surfacesDidEnter(_ surfaces: [ViewType])
    @MainActor func surfacesDidLeave(_ surfaces: [ViewType])
}

@MainActor
final class WorkspaceStore<ViewType: NSView & Codable & Identifiable>: ObservableObject where ViewType.ID == UUID {
    @Published private(set) var workspaces: [Workspace<ViewType>]
    @Published private(set) var selectedWorkspaceID: UUID

    let snapshots = WorkspaceSnapshotStore()
    weak var delegate: (any WorkspaceStoreDelegate<ViewType>)?

    init(defaultDirectory: URL, makeTab: () -> WorkspaceTab<ViewType>) {
        let defaultWorkspace = Workspace(
            name: WorkspaceName.defaultName,
            directory: defaultDirectory,
            isDefault: true,
            tab: makeTab()
        )
        self.workspaces = [defaultWorkspace]
        self.selectedWorkspaceID = defaultWorkspace.id
    }

    init(
        restoring state: WorkspacesState<ViewType>,
        defaultDirectory: URL,
        makeTab: () -> WorkspaceTab<ViewType>
    ) {
        var restored: [Workspace<ViewType>] = []
        var seen = Set<UUID>()
        var hasDefault = false

        for entry in state.workspaces {
            let asDefault = entry.isDefault && !hasDefault
            guard let workspace = Workspace(
                restoring: entry,
                isDefault: asDefault,
                makeReplacementTab: makeTab
            ), seen.insert(workspace.id).inserted else { continue }

            if asDefault {
                hasDefault = true
                restored.insert(workspace, at: 0)
            } else {
                restored.append(workspace)
            }
        }

        if !hasDefault {
            restored.insert(
                Workspace(
                    name: WorkspaceName.defaultName,
                    directory: defaultDirectory,
                    isDefault: true,
                    tab: makeTab()
                ),
                at: 0
            )
        }

        let selected = UUID(uuidString: state.selectedWorkspace)
            .flatMap { selectedID in restored.first { $0.id == selectedID }?.id }
            ?? restored[0].id

        self.workspaces = restored
        self.selectedWorkspaceID = selected
    }

    var selectedWorkspace: Workspace<ViewType>? {
        workspace(id: selectedWorkspaceID)
    }

    var selectedTab: WorkspaceTab<ViewType>? {
        selectedWorkspace?.selectedTab
    }

    var allSurfaces: [ViewType] {
        workspaces.flatMap { $0.surfaces }
    }

    func workspace(id: UUID) -> Workspace<ViewType>? {
        workspaces.first { $0.id == id }
    }

    func contains(_ surface: ViewType) -> Bool {
        workspaces.contains { $0.contains(surface) }
    }

    func workspace(containing surface: ViewType) -> Workspace<ViewType>? {
        workspaces.first { $0.contains(surface) }
    }

    func tab(containing surface: ViewType) -> WorkspaceTab<ViewType>? {
        workspace(containing: surface)?.tab(containing: surface)
    }

    func makeState() -> WorkspacesState<ViewType> {
        WorkspacesState(
            selectedWorkspace: selectedWorkspaceID.uuidString,
            workspaces: workspaces.map(WorkspaceState.init)
        )
    }

    @discardableResult
    func addWorkspace(
        name: String,
        directory: URL,
        makeTab: () -> WorkspaceTab<ViewType>
    ) throws(WorkspaceError) -> Workspace<ViewType> {
        let normalized = WorkspaceName.normalize(name)
        guard !normalized.isEmpty else { throw WorkspaceError.emptyName }
        guard !workspaces.contains(where: {
            $0.name.compare(normalized, options: .caseInsensitive) == .orderedSame
        }) else { throw WorkspaceError.duplicateName }

        let workspace = Workspace(name: normalized, directory: directory, tab: makeTab())
        workspaces.append(workspace)
        delegate?.surfacesDidEnter(workspace.surfaces)
        return workspace
    }

    @discardableResult
    func closeWorkspace(id: UUID) -> Bool {
        guard let index = workspaces.firstIndex(where: { $0.id == id }),
              !workspaces[index].isDefault else { return false }

        let removed = workspaces.remove(at: index)
        if removed.id == selectedWorkspaceID {
            selectedWorkspaceID = workspaces[index - 1].id
        }
        pruneSnapshots()
        delegate?.surfacesDidLeave(removed.surfaces)
        return true
    }

    @discardableResult
    func select(workspaceID: UUID, tabID: UUID? = nil) -> Bool {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return false }
        if let tabID {
            guard workspaces[index].selectTab(id: tabID) else { return false }
        }
        selectedWorkspaceID = workspaceID
        return true
    }

    func selectPrevious() {
        selectWorkspace(offsetBy: -1)
    }

    func selectNext() {
        selectWorkspace(offsetBy: 1)
    }

    @discardableResult
    func goto(index: Int) -> Bool {
        guard index >= 1, index <= workspaces.count else { return false }
        selectedWorkspaceID = workspaces[index - 1].id
        return true
    }

    @discardableResult
    func addTab(_ tab: WorkspaceTab<ViewType>, to workspaceID: UUID) -> Bool {
        mutateWorkspace(id: workspaceID) { $0.appendTab(tab) } != nil
    }

    @discardableResult
    func removeTab(
        workspaceID: UUID,
        tabID: UUID,
        makeReplacement: () -> WorkspaceTab<ViewType>
    ) -> WorkspaceTab<ViewType>? {
        let removed = mutateWorkspace(id: workspaceID) {
            $0.removeTab(id: tabID, makeReplacement: makeReplacement)
        } ?? nil
        if let removed {
            snapshots.remove(tabID: removed.id)
        }
        return removed
    }

    @discardableResult
    func updateTab(
        workspaceID: UUID,
        tabID: UUID,
        _ body: (inout WorkspaceTab<ViewType>) -> Void
    ) -> Bool {
        mutateWorkspace(id: workspaceID) { $0.updateTab(id: tabID, body) } == true
    }

    func insert(view: ViewType, at surface: ViewType, direction: SplitTree<ViewType>.NewDirection) throws {
        guard let workspace = workspace(containing: surface),
              let tab = workspace.tab(containing: surface) else {
            throw WorkspaceError.surfaceNotFound
        }

        let newTree = try tab.tree.inserting(view: view, at: surface, direction: direction)
        updateTab(workspaceID: workspace.id, tabID: tab.id) { $0.setTree(newTree) }
    }

    @discardableResult
    func remove(surface: ViewType, makeReplacement: () -> WorkspaceTab<ViewType>) -> Bool {
        guard let workspace = workspace(containing: surface),
              let tab = workspace.tab(containing: surface),
              let node = tab.tree.root?.node(view: surface) else { return false }

        let newTree = tab.tree.removing(node)
        if newTree.isEmpty {
            removeTab(workspaceID: workspace.id, tabID: tab.id, makeReplacement: makeReplacement)
        } else {
            updateTab(workspaceID: workspace.id, tabID: tab.id) { tab in
                tab.setTree(newTree)
                if tab.focusedSurfaceID == surface.id {
                    tab.focusedSurfaceID = nil
                }
            }
        }
        return true
    }

    private func mutateWorkspace<Result>(
        id: UUID,
        _ body: (inout Workspace<ViewType>) -> Result
    ) -> Result? {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return nil }

        let before = workspaces[index].surfaces
        let result = body(&workspaces[index])
        let after = workspaces[index].surfaces

        let beforeIDs = Set(before.map(ObjectIdentifier.init))
        let afterIDs = Set(after.map(ObjectIdentifier.init))
        let left = before.filter { !afterIDs.contains(ObjectIdentifier($0)) }
        let entered = after.filter { !beforeIDs.contains(ObjectIdentifier($0)) }
        if !left.isEmpty { delegate?.surfacesDidLeave(left) }
        if !entered.isEmpty { delegate?.surfacesDidEnter(entered) }

        return result
    }

    private func selectWorkspace(offsetBy offset: Int) {
        guard let current = workspaces.firstIndex(where: { $0.id == selectedWorkspaceID }) else { return }
        let count = workspaces.count
        let target = ((current + offset) % count + count) % count
        selectedWorkspaceID = workspaces[target].id
    }

    private func pruneSnapshots() {
        let live = workspaces.flatMap { $0.tabs.map(\.id) }
        snapshots.prune(keeping: Set(live))
    }
}
