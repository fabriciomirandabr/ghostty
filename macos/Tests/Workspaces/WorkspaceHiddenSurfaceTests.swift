import AppKit
import Testing
@testable import Ghostty

private final class OcclusionDouble: NSView, OcclusionControlled, Identifiable {
    var isWindowVisible = true
    var canControlOcclusion = true
    private(set) var calls: [Bool] = []

    func applyOcclusion(_ visible: Bool) {
        calls.append(visible)
    }
}

@MainActor
struct WorkspaceHiddenSurfaceTests {
    private let projectDirectory = URL(fileURLWithPath: "/tmp/ws-project")

    private func makeStore(hidden: MockView) throws -> (MockStore, UUID) {
        let store = WorkspaceFixtures.makeStore()
        let workspace = try store.addWorkspace(name: "Other", directory: projectDirectory) {
            WorkspaceFixtures.makeTab(views: [hidden])
        }
        return (store, workspace.id)
    }

    @Test func lookupFindsSurfacesOfHiddenWorkspaces() throws {
        let hidden = MockView()
        let (store, hiddenWorkspaceID) = try makeStore(hidden: hidden)

        #expect(store.selectedWorkspace?.isDefault == true)
        #expect(store.allSurfaces.contains { $0 === hidden })
        #expect(WorkspaceWindowPolicy.workspaceID(containing: hidden, in: store) == hiddenWorkspaceID)
        #expect(WorkspaceWindowPolicy.workspaceID(containing: MockView(), in: store) == nil)
    }

    @Test func closeWorkspaceIsNotPerformableOnTheDefaultWorkspace() throws {
        let (store, hiddenWorkspaceID) = try makeStore(hidden: MockView())

        #expect(!WorkspaceWindowPolicy.canCloseSelectedWorkspace(store))

        store.select(workspaceID: hiddenWorkspaceID)
        #expect(WorkspaceWindowPolicy.canCloseSelectedWorkspace(store))
    }

    @Test func occlusionIsOffForSurfacesOutsideTheVisibleTree() {
        let visible = OcclusionDouble()
        let hidden = OcclusionDouble()

        SurfaceOcclusion.sync([visible, hidden], windowVisible: true) { $0 === visible }

        #expect(visible.calls.isEmpty)
        #expect(hidden.calls == [false])
        #expect(!hidden.isWindowVisible)
        #expect(visible.isWindowVisible)
    }

    @Test func occlusionResyncsWhenSurfacesReturnToTheVisibleTree() {
        let first = OcclusionDouble()
        let second = OcclusionDouble()

        SurfaceOcclusion.sync([first, second], windowVisible: true) { $0 === first }
        SurfaceOcclusion.sync([first, second], windowVisible: true) { $0 === second }

        #expect(first.calls == [false])
        #expect(second.calls == [false, true])
        #expect(!first.isWindowVisible)
        #expect(second.isWindowVisible)
    }

    @Test func hiddenWindowOccludesEverySurface() {
        let first = OcclusionDouble()
        let second = OcclusionDouble()

        SurfaceOcclusion.sync([first, second], windowVisible: false) { _ in true }

        #expect(first.calls == [false])
        #expect(second.calls == [false])
    }

    @Test func surfacesWithoutALiveHandleAreSkipped() {
        let dead = OcclusionDouble()
        dead.canControlOcclusion = false

        SurfaceOcclusion.sync([dead], windowVisible: false) { _ in false }

        #expect(dead.calls.isEmpty)
        #expect(dead.isWindowVisible)
    }
}
