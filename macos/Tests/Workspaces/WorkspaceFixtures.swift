import AppKit
@testable import Ghostty

typealias MockStore = WorkspaceStore<MockView>
typealias MockTab = WorkspaceTab<MockView>

@MainActor
enum WorkspaceFixtures {
    static let home = URL(fileURLWithPath: "/tmp/ws-home")

    static func makeTab(title: String? = nil, views: [MockView] = [MockView()]) -> MockTab {
        var tree = SplitTree<MockView>(view: views[0])
        for view in views.dropFirst() {
            guard let inserted = try? tree.inserting(view: view, at: views[0], direction: .right) else {
                preconditionFailure("failed to build test tree")
            }
            tree = inserted
        }
        guard let tab = MockTab(titleOverride: title, tree: tree, focusedSurfaceID: views[0].id) else {
            preconditionFailure("failed to build test tab")
        }
        return tab
    }

    static func makeStore() -> MockStore {
        MockStore(defaultDirectory: home, makeTab: { makeTab() })
    }
}
