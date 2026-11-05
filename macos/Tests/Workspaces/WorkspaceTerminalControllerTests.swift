import AppKit
import GhosttyKit
import Testing
@testable import Ghostty

private final class ConfirmingView: MockView, QuitConfirmable {
    var needsConfirmQuit = false
}

@MainActor
struct WorkspaceTerminalControllerTests {
    private let home = WorkspaceFixtures.home
    private let projectDirectory = URL(fileURLWithPath: "/tmp/ws-project")

    private func makeWorkspace(views: [MockView] = [MockView()]) -> Workspace<MockView> {
        Workspace(
            name: "Project",
            directory: projectDirectory,
            tab: WorkspaceFixtures.makeTab(views: views))
    }

    private func makeConfirmingStore(
        defaultView: ConfirmingView,
        otherView: ConfirmingView
    ) throws -> WorkspaceStore<ConfirmingView> {
        func tab(_ view: ConfirmingView) -> WorkspaceTab<ConfirmingView> {
            guard let tab = WorkspaceTab(tree: SplitTree(view: view)) else {
                preconditionFailure("failed to build test tab")
            }
            return tab
        }

        let store = WorkspaceStore<ConfirmingView>(defaultDirectory: home, makeTab: { tab(defaultView) })
        _ = try store.addWorkspace(name: "Other", directory: projectDirectory, makeTab: { tab(otherView) })
        return store
    }

    @Test func newTabUsesWorkspaceDirectory() {
        var inherited = Ghostty.SurfaceConfiguration()
        inherited.workingDirectory = "/tmp/inherited-from-surface"
        inherited.context = GHOSTTY_SURFACE_CONTEXT_TAB

        let config = WorkspaceSurfaceConfiguration.make(base: inherited, workspace: makeWorkspace())

        #expect(config.workingDirectory == projectDirectory.path)
        #expect(config.context == GHOSTTY_SURFACE_CONTEXT_TAB)
    }

    @Test func newSplitUsesWorkspaceDirectory() {
        var inherited = Ghostty.SurfaceConfiguration()
        inherited.workingDirectory = "/tmp/inherited-from-surface"
        inherited.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

        let config = WorkspaceSurfaceConfiguration.make(base: inherited, workspace: makeWorkspace())

        #expect(config.workingDirectory == projectDirectory.path)
        #expect(config.context == GHOSTTY_SURFACE_CONTEXT_SPLIT)
    }

    @Test func configurationWithoutBaseGetsWorkspaceDirectory() {
        let config = WorkspaceSurfaceConfiguration.make(base: nil, workspace: makeWorkspace())
        #expect(config.workingDirectory == projectDirectory.path)
    }

    @Test func configurationKeepsOtherInheritedFields() {
        var inherited = Ghostty.SurfaceConfiguration()
        inherited.workingDirectory = "/tmp/inherited-from-surface"
        inherited.fontSize = 17
        inherited.environmentVariables = ["KEY": "value"]

        let config = WorkspaceSurfaceConfiguration.make(base: inherited, directory: projectDirectory)

        #expect(config.fontSize == 17)
        #expect(config.environmentVariables == ["KEY": "value"])
    }

    @Test func ownsSurfacesOfInactiveWorkspaces() throws {
        let store = WorkspaceFixtures.makeStore()
        let hidden = MockView()
        let visible = try #require(store.selectedTab?.tree.first)
        _ = try store.addWorkspace(
            name: "Other",
            directory: projectDirectory,
            makeTab: { WorkspaceFixtures.makeTab(views: [hidden]) })

        #expect(store.selectedTab?.tree.contains(hidden) == false)
        #expect(WorkspaceWindowPolicy.owns(hidden, in: store))
        #expect(WorkspaceWindowPolicy.owns(visible, in: store))
        #expect(!WorkspaceWindowPolicy.owns(MockView(), in: store))
    }

    @Test func stopsOwningSurfacesOfClosedWorkspace() throws {
        let store = WorkspaceFixtures.makeStore()
        let hidden = MockView()
        let workspace = try store.addWorkspace(
            name: "Other",
            directory: projectDirectory,
            makeTab: { WorkspaceFixtures.makeTab(views: [hidden]) })

        #expect(store.closeWorkspace(id: workspace.id))
        #expect(!WorkspaceWindowPolicy.owns(hidden, in: store))
    }

    @Test func windowCloseConsidersAllWorkspaces() throws {
        let visible = ConfirmingView()
        let hidden = ConfirmingView()
        let store = try makeConfirmingStore(defaultView: visible, otherView: hidden)

        #expect(store.selectedWorkspace?.isDefault == true)
        #expect(WorkspaceWindowPolicy.canCloseWithoutConfirmation(store))

        hidden.needsConfirmQuit = true
        #expect(!WorkspaceWindowPolicy.canCloseWithoutConfirmation(store))

        hidden.needsConfirmQuit = false
        visible.needsConfirmQuit = true
        #expect(!WorkspaceWindowPolicy.canCloseWithoutConfirmation(store))
    }

    @Test func tabsNeedingConfirmationFollowTheQuitPredicate() throws {
        let visible = ConfirmingView()
        let hidden = ConfirmingView()
        let store = try makeConfirmingStore(defaultView: visible, otherView: hidden)
        let other = try #require(store.workspaces.last)
        let defaultWorkspace = try #require(store.workspaces.first)

        #expect(WorkspaceWindowPolicy.tabsNeedingConfirmation(workspaceID: other.id, in: store).isEmpty)

        hidden.needsConfirmQuit = true
        #expect(WorkspaceWindowPolicy.tabsNeedingConfirmation(workspaceID: other.id, in: store) == [other.tabs[0].id])
        #expect(WorkspaceWindowPolicy.tabsNeedingConfirmation(workspaceID: defaultWorkspace.id, in: store).isEmpty)
        #expect(WorkspaceWindowPolicy.tabsNeedingConfirmation(workspaceID: UUID(), in: store).isEmpty)
    }

    @Test func tabNavigationResolvesIndexes() {
        let navigate = WorkspaceTabNavigation.targetIndex

        #expect(navigate(2, 0, 5) == 1)
        #expect(navigate(9, 0, 3) == 2)
        #expect(navigate(GHOSTTY_GOTO_TAB_PREVIOUS.rawValue, 0, 3) == 2)
        #expect(navigate(GHOSTTY_GOTO_TAB_NEXT.rawValue, 2, 3) == 0)
        #expect(navigate(GHOSTTY_GOTO_TAB_LAST.rawValue, 0, 4) == 3)
        #expect(navigate(2, 0, 0) == nil)
        #expect(navigate(-9, 0, 3) == nil)
    }
}
