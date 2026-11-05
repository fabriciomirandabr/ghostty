import Foundation

enum WorkspaceActivityAggregator {
    struct Summary: Equatable {
        var runningCount: Int
        var needsAttention: Bool
    }

    static func tabState(_ surfaces: [SurfaceActivityState]) -> SurfaceActivityState {
        surfaces.max() ?? .idle
    }

    static func workspaceState(_ tabs: [[SurfaceActivityState]]) -> SurfaceActivityState {
        tabs.map(tabState).max() ?? .idle
    }

    static func summary(_ tabs: [[SurfaceActivityState]]) -> Summary {
        Summary(
            runningCount: tabs.filter { $0.contains(.running) }.count,
            needsAttention: tabs.contains { $0.contains(.needsAttention) }
        )
    }
}
