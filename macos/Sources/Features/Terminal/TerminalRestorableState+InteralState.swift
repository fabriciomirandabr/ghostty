import AppKit

extension TerminalRestorableState {
    /// Internal State we use to perform unit tests
    ///
    /// Since we can't really change the type of `TerminalRestorableState`
    /// due to `CodableBridge<TerminalRestorableState>` supporting secure coding,
    /// we use an internal type to perform migration and tests
    struct InternalState<ViewType: NSView & Codable & Identifiable>: Codable {
        // MARK: - Version 5 (1.2.3)
        let focusedSurface: String?
        let surfaceTree: SplitTree<ViewType>

        // MARK: - Version 7 (1.3.0)
        let effectiveFullscreenMode: FullscreenMode?
        let tabColor: TerminalTabColor?
        let titleOverride: String?
        let workspaces: WorkspacesState<ViewType>?

        enum CodingKeys: String, CodingKey {
            case focusedSurface
            case surfaceTree
            case effectiveFullscreenMode
            case tabColor
            case titleOverride
            case workspaces
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(focusedSurface, forKey: .focusedSurface)
            try container.encode(workspaces == nil ? surfaceTree : SplitTree(), forKey: .surfaceTree)
            try container.encodeIfPresent(effectiveFullscreenMode, forKey: .effectiveFullscreenMode)
            try container.encodeIfPresent(tabColor, forKey: .tabColor)
            try container.encodeIfPresent(titleOverride, forKey: .titleOverride)
            try container.encodeIfPresent(workspaces, forKey: .workspaces)
        }

        var restoredSurfaceTree: SplitTree<ViewType> {
            guard surfaceTree.isEmpty, let workspaces else { return surfaceTree }
            let workspace = workspaces.workspaces.first { $0.id == workspaces.selectedWorkspace }
                ?? workspaces.workspaces.first
            let tab = workspace?.tabs.first { $0.id == workspace?.selectedTab }
                ?? workspace?.tabs.first
            return tab?.surfaceTree ?? surfaceTree
        }
    }
}

extension TerminalRestorableState.InternalState where ViewType == Ghostty.SurfaceView {
    init(from controller: TerminalController, workspaces: WorkspacesState<ViewType>? = nil) {
        self.init(
            focusedSurface: controller.focusedSurface?.id.uuidString,
            surfaceTree: controller.surfaceTree,
            effectiveFullscreenMode: controller.fullscreenStyle?.fullscreenMode,
            tabColor: (controller.window as? TerminalWindow)?.tabColor,
            titleOverride: controller.titleOverride,
            workspaces: workspaces
        )
    }
}
