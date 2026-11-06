import AppKit
import Testing
@testable import Ghostty

private final class ConfirmingView: MockView, QuitConfirmable {
    var needsConfirmQuit = false
}

@MainActor
struct WorkspaceWindowPolicyTests {
    private func makeSplitStore(
        first: ConfirmingView,
        second: ConfirmingView
    ) throws -> WorkspaceStore<ConfirmingView> {
        func tab(_ views: [ConfirmingView]) -> WorkspaceTab<ConfirmingView> {
            var tree = SplitTree<ConfirmingView>(view: views[0])
            for view in views.dropFirst() {
                guard let inserted = try? tree.inserting(view: view, at: views[0], direction: .right) else {
                    preconditionFailure("failed to build test tree")
                }
                tree = inserted
            }
            guard let tab = WorkspaceTab(tree: tree) else {
                preconditionFailure("failed to build test tab")
            }
            return tab
        }

        let home = WorkspaceFixtures.home
        let store = WorkspaceStore<ConfirmingView>(defaultDirectory: home, makeTab: { tab([ConfirmingView()]) })
        _ = try store.addWorkspace(
            name: "Split",
            directory: URL(fileURLWithPath: "/tmp/ws-split"),
            makeTab: { tab([first, second]) })
        return store
    }

    @Test func surfacesNeedingConfirmationReturnsSurfaceIDs() throws {
        let first = ConfirmingView()
        let second = ConfirmingView()
        let store = try makeSplitStore(first: first, second: second)
        let workspace = try #require(store.workspaces.last)

        #expect(WorkspaceWindowPolicy.surfacesNeedingConfirmation(workspaceID: workspace.id, in: store).isEmpty)

        second.needsConfirmQuit = true
        #expect(WorkspaceWindowPolicy.surfacesNeedingConfirmation(workspaceID: workspace.id, in: store) == [second.id])

        first.needsConfirmQuit = true
        #expect(
            WorkspaceWindowPolicy.surfacesNeedingConfirmation(workspaceID: workspace.id, in: store)
                == [first.id, second.id])
    }
}
