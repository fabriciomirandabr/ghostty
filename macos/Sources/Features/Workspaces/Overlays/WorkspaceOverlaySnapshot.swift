import AppKit

struct WorkspaceSurfaceInfo: Equatable {
    var title: String
    var lastCommand: String?
    var state: SurfaceActivityState
    var pwd: String?
}

struct WorkspaceTabSummary: Identifiable, Equatable {
    let id: UUID
    let workspaceID: UUID
    var title: String
    var state: SurfaceActivityState
    var lastCommand: String?
    var busiestSurfaceID: UUID?
}

struct WorkspaceSummary: Identifiable, Equatable {
    let id: UUID
    var name: String
    var directory: URL
    var isDefault: Bool
    var isCurrent: Bool
    var state: SurfaceActivityState
    var selectedTabID: UUID
    var tabs: [WorkspaceTabSummary]

    var runningTabCount: Int {
        tabs.filter { $0.state == .running }.count
    }
}

struct WorkspaceOverlaySnapshot: Equatable {
    var workspaces: [WorkspaceSummary]

    func workspace(id: UUID) -> WorkspaceSummary? {
        workspaces.first { $0.id == id }
    }

    var workspaceIDs: Set<UUID> {
        Set(workspaces.map(\.id))
    }

    var names: [String] {
        workspaces.map(\.name)
    }
}

enum WorkspaceFolderLabel {
    static func abbreviated(_ url: URL, home: String = NSHomeDirectory()) -> String {
        abbreviated(path: url.path, home: home)
    }

    static func abbreviated(path: String, home: String = NSHomeDirectory()) -> String {
        let normalizedHome = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == normalizedHome { return "~" }
        if path.hasPrefix(normalizedHome + "/") {
            return "~" + path.dropFirst(normalizedHome.count)
        }
        return path
    }
}

extension WorkspaceStore {
    func overlaySnapshot(info: (ViewType) -> WorkspaceSurfaceInfo) -> WorkspaceOverlaySnapshot {
        WorkspaceOverlaySnapshot(workspaces: workspaces.map { workspace in
            var surfaceStatesPerTab: [[SurfaceActivityState]] = []
            let tabs = workspace.tabs.map { tab -> WorkspaceTabSummary in
                let surfaces = Array(tab.tree)
                let infos = surfaces.map { (surface: $0, info: info($0)) }
                surfaceStatesPerTab.append(infos.map(\.info.state))

                var busiest = infos.first
                for entry in infos where entry.info.state > (busiest?.info.state ?? .idle) {
                    busiest = entry
                }

                let focused = infos.first { $0.surface.id == tab.focusedSurfaceID } ?? infos.first
                let override = WorkspaceTabTitle.override(tab.titleOverride)
                let command = busiest?.info.lastCommand.flatMap { $0.isEmpty ? nil : $0 }

                return WorkspaceTabSummary(
                    id: tab.id,
                    workspaceID: workspace.id,
                    title: override ?? WorkspaceTabTitle.resolve(
                        title: focused?.info.title ?? "",
                        pwd: focused?.info.pwd),
                    state: WorkspaceActivityAggregator.tabState(infos.map(\.info.state)),
                    lastCommand: command,
                    busiestSurfaceID: busiest?.surface.id
                )
            }

            return WorkspaceSummary(
                id: workspace.id,
                name: workspace.name,
                directory: workspace.directory,
                isDefault: workspace.isDefault,
                isCurrent: workspace.id == selectedWorkspaceID,
                state: WorkspaceActivityAggregator.workspaceState(surfaceStatesPerTab),
                selectedTabID: workspace.selectedTabID,
                tabs: tabs
            )
        })
    }
}
