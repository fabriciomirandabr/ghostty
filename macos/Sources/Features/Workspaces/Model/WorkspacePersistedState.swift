import AppKit

struct WorkspacePersistedState: Codable, Equatable {
    static let currentVersion = 1
    static let maxWorkspaces = 64
    static let maxTabsPerWorkspace = 32

    var version: Int = Self.currentVersion
    var selectedWorkspace: String
    var workspaces: [WorkspacePersistedWorkspace]
}

struct WorkspacePersistedWorkspace: Codable, Equatable {
    var id: String
    var name: String
    var directory: String
    var isDefault: Bool
    var selectedTab: String
    var tabs: [WorkspacePersistedTab]
}

struct WorkspacePersistedTab: Codable, Equatable {
    var id: String
    var titleOverride: String?
    var directory: String
}

extension WorkspacePersistedState {
    @MainActor
    init<ViewType>(
        store: WorkspaceStore<ViewType>,
        directory: (ViewType) -> String?
    ) where ViewType.ID == UUID {
        self.init(
            selectedWorkspace: store.selectedWorkspaceID.uuidString,
            workspaces: store.workspaces.map { workspace in
                WorkspacePersistedWorkspace(
                    id: workspace.id.uuidString,
                    name: workspace.name,
                    directory: workspace.directory.path,
                    isDefault: workspace.isDefault,
                    selectedTab: workspace.selectedTabID.uuidString,
                    tabs: workspace.tabs.map { tab in
                        let surfaces = Array(tab.tree)
                        let focused = surfaces.first { $0.id == tab.focusedSurfaceID } ?? surfaces.first
                        return WorkspacePersistedTab(
                            id: tab.id.uuidString,
                            titleOverride: tab.titleOverride,
                            directory: focused.flatMap(directory) ?? workspace.directory.path)
                    })
            })
    }

    func hasSameStructure(as other: WorkspacePersistedState) -> Bool {
        func withoutTabDirectories(_ state: WorkspacePersistedState) -> WorkspacePersistedState {
            var copy = state
            for workspace in copy.workspaces.indices {
                for tab in copy.workspaces[workspace].tabs.indices {
                    copy.workspaces[workspace].tabs[tab].directory = ""
                }
            }
            return copy
        }
        return withoutTabDirectories(self) == withoutTabDirectories(other)
    }

    func sharesWorkspace(with other: WorkspacePersistedState) -> Bool {
        let mine = Set(workspaces.map(\.id))
        return other.workspaces.contains { mine.contains($0.id) }
    }

    func sanitized() -> WorkspacePersistedState {
        var seenWorkspaces = Set<String>()
        var seenTabs = Set<String>()
        var kept: [WorkspacePersistedWorkspace] = []

        for workspace in workspaces {
            guard kept.count < Self.maxWorkspaces,
                  let workspaceID = UUID(uuidString: workspace.id),
                  seenWorkspaces.insert(workspaceID.uuidString).inserted else { continue }

            var tabs: [WorkspacePersistedTab] = []
            for tab in workspace.tabs {
                guard tabs.count < Self.maxTabsPerWorkspace,
                      let tabID = UUID(uuidString: tab.id),
                      seenTabs.insert(tabID.uuidString).inserted else { continue }
                tabs.append(tab)
            }

            var copy = workspace
            copy.tabs = tabs
            kept.append(copy)
        }

        let before = workspaces.count + workspaces.reduce(0) { $0 + $1.tabs.count }
        let after = kept.count + kept.reduce(0) { $0 + $1.tabs.count }
        if before != after {
            Ghostty.logger.debug("workspace state sanitized: dropped \(before - after, privacy: .public) entries")
        }

        var copy = self
        copy.workspaces = kept
        return copy
    }

    static func resolvedDirectory(
        tab: WorkspacePersistedTab,
        workspace: WorkspacePersistedWorkspace,
        isDirectory: (URL) -> Bool
    ) -> URL {
        let candidates = [tab.directory, workspace.directory].map { URL(fileURLWithPath: $0, isDirectory: true) }
        return candidates.first(where: isDirectory) ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func makeWorkspacesState<ViewType>(
        isDirectory: (URL) -> Bool = Self.directoryExists,
        makeTree: (URL) -> SplitTree<ViewType>
    ) -> WorkspacesState<ViewType> {
        let clean = sanitized()
        return WorkspacesState(
            selectedWorkspace: clean.selectedWorkspace,
            workspaces: clean.workspaces.map { workspace in
                WorkspaceState(
                    id: workspace.id,
                    name: workspace.name,
                    directory: workspace.directory,
                    isDefault: workspace.isDefault,
                    selectedTab: workspace.selectedTab,
                    tabs: workspace.tabs.map { tab in
                        WorkspaceTabState(
                            id: tab.id,
                            titleOverride: tab.titleOverride,
                            focusedSurface: nil,
                            surfaceTree: makeTree(Self.resolvedDirectory(
                                tab: tab,
                                workspace: workspace,
                                isDirectory: isDirectory)))
                    })
            })
    }

    static func directoryExists(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
