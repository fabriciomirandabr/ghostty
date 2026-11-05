import AppKit

enum WorkspaceSurfaceConfiguration {
    static func make(
        base: Ghostty.SurfaceConfiguration?,
        directory: URL
    ) -> Ghostty.SurfaceConfiguration {
        var config = base ?? Ghostty.SurfaceConfiguration()
        config.workingDirectory = directory.path
        return config
    }

    static func make<ViewType>(
        base: Ghostty.SurfaceConfiguration?,
        workspace: Workspace<ViewType>
    ) -> Ghostty.SurfaceConfiguration {
        make(base: base, directory: workspace.directory)
    }
}

enum WorkspaceDefaultDirectory {
    static func resolve(_ configured: String?) -> URL {
        guard let configured, !configured.isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: configured, isDirectory: true)
    }
}

protocol QuitConfirmable {
    var needsConfirmQuit: Bool { get }
}

extension Ghostty.SurfaceView: QuitConfirmable {}

enum WorkspaceWindowPolicy {
    @MainActor
    static func canCloseWithoutConfirmation<ViewType: NSView & Codable & Identifiable & QuitConfirmable>(
        _ store: WorkspaceStore<ViewType>
    ) -> Bool where ViewType.ID == UUID {
        !store.allSurfaces.contains { $0.needsConfirmQuit }
    }

    @MainActor
    static func workspaceID<ViewType: NSView & Codable & Identifiable>(
        containing surface: ViewType,
        in store: WorkspaceStore<ViewType>
    ) -> UUID? where ViewType.ID == UUID {
        store.workspace(containing: surface)?.id
    }

    @MainActor
    static func canCloseSelectedWorkspace<ViewType: NSView & Codable & Identifiable>(
        _ store: WorkspaceStore<ViewType>
    ) -> Bool where ViewType.ID == UUID {
        !(store.selectedWorkspace?.isDefault ?? true)
    }

    @MainActor
    static func tabsNeedingConfirmation<ViewType: NSView & Codable & Identifiable & QuitConfirmable>(
        workspaceID: UUID,
        in store: WorkspaceStore<ViewType>
    ) -> Set<UUID> where ViewType.ID == UUID {
        guard let workspace = store.workspace(id: workspaceID) else { return [] }
        return Set(workspace.tabs.filter { tab in
            tab.tree.contains { $0.needsConfirmQuit }
        }.map(\.id))
    }

    @MainActor
    static func owns<ViewType: NSView & Codable & Identifiable>(
        _ surface: ViewType,
        in store: WorkspaceStore<ViewType>
    ) -> Bool where ViewType.ID == UUID {
        store.contains(surface)
    }
}
