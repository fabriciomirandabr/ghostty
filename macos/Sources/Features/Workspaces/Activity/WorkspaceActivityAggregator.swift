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

    static func runningPaneCount(_ surfaces: [SurfaceActivityState]) -> Int {
        surfaces.filter { $0 == .running }.count
    }

    static func summary(_ tabs: [[SurfaceActivityState]]) -> Summary {
        Summary(
            runningCount: tabs.map(runningPaneCount).reduce(0, +),
            needsAttention: tabs.contains { $0.contains(.needsAttention) }
        )
    }
}
