import Foundation
import Testing
@testable import Ghostty

@MainActor
struct CloseWorkspaceConfirmationTests {
    private func busyWorkspace() -> WorkspaceSummary {
        OverlayFixtures.workspace("api", tabs: [
            TabSpec(title: "dev", state: .running),
            TabSpec(title: "agent", state: .needsAttention),
            TabSpec(title: "tests", state: .done),
            TabSpec(title: "shell", state: .idle),
        ])
    }

    @Test func listsOnlyBusyTabs() {
        let confirmation = CloseWorkspaceConfirmation.make(for: busyWorkspace(), foregroundProcessTabs: [])
        #expect(confirmation.rows.map(\.title) == ["dev", "agent"])
        #expect(confirmation.rows.map(\.state) == [.running, .needsAttention])
        #expect(confirmation.requiresConfirmation)
        #expect(confirmation.workspaceName == "api")
    }

    @Test func headlineCountsListedTabs() {
        let busy = CloseWorkspaceConfirmation.make(for: busyWorkspace(), foregroundProcessTabs: [])
        #expect(busy.headline == "2 terminals running. Close anyway?")

        let single = OverlayFixtures.workspace("web", tabs: [TabSpec(title: "dev", state: .running)])
        let one = CloseWorkspaceConfirmation.make(for: single, foregroundProcessTabs: [])
        #expect(one.headline == "1 terminal running. Close anyway?")
    }

    @Test func noConfirmationWhenNothingIsBusy() {
        let calm = OverlayFixtures.workspace("docs", tabs: [
            TabSpec(title: "a", state: .done),
            TabSpec(title: "b", state: .idle),
        ])
        let confirmation = CloseWorkspaceConfirmation.make(for: calm, foregroundProcessTabs: [])
        #expect(confirmation.rows.isEmpty)
        #expect(!confirmation.requiresConfirmation)
    }

    @Test func idleTabWithForegroundProcessRequiresConfirmation() {
        let workspace = OverlayFixtures.workspace("ops", tabs: [
            TabSpec(title: "vim", state: .idle),
            TabSpec(title: "build", state: .running),
            TabSpec(title: "shell", state: .idle),
        ])
        let vimTab = workspace.tabs[0].id

        let confirmation = CloseWorkspaceConfirmation.make(for: workspace, foregroundProcessTabs: [vimTab])
        #expect(confirmation.requiresConfirmation)
        #expect(confirmation.rows.map(\.title) == ["vim", "build"])
        #expect(confirmation.rows.map(\.suffix) == ["process running", "running"])
        #expect(confirmation.headline == "2 terminals running. Close anyway?")

        let alone = CloseWorkspaceConfirmation.make(
            for: OverlayFixtures.workspace("ssh", tabs: [TabSpec(title: "ssh", state: .idle)]),
            foregroundProcessTabs: [])
        #expect(!alone.requiresConfirmation)
    }

    @Test func requestCloseAsksForIdleTabWithForegroundProcess() {
        let workspace = OverlayFixtures.workspace("ops", tabs: [TabSpec(title: "vim", state: .idle)])
        let snapshot = OverlayFixtures.snapshot([OverlayFixtures.workspace("Default", isDefault: true), workspace])
        let state = WorkspaceOverlayState()
        var closed: [UUID] = []

        state.requestClose(workspaceID: workspace.id, anchor: .titlebar, in: snapshot) { closed.append($0) }
        #expect(closed == [workspace.id])

        state.foregroundProcessTabs = { id in id == workspace.id ? [workspace.tabs[0].id] : [] }
        closed = []
        state.requestClose(workspaceID: workspace.id, anchor: .titlebar, in: snapshot) { closed.append($0) }
        #expect(closed.isEmpty)
        #expect(state.closeConfirmation?.workspaceID == workspace.id)
    }

    @Test func defaultWorkspaceNeverResolves() {
        let def = OverlayFixtures.workspace("Default", isDefault: true, tabs: [TabSpec(title: "x", state: .running)])
        let snapshot = OverlayFixtures.snapshot([def])
        #expect(CloseWorkspaceConfirmation.resolve(workspaceID: def.id, in: snapshot, foregroundProcessTabs: []) == nil)
    }

    @Test func dismissesWhenWorkspaceGone() throws {
        let store = WorkspaceFixtures.makeStore()
        let workspace = try store.addWorkspace(name: "api", directory: URL(fileURLWithPath: "/tmp/ws-home/api")) {
            WorkspaceFixtures.makeTab()
        }
        let busy = WorkspaceSurfaceInfo(title: "dev", lastCommand: nil, state: .running)
        let state = WorkspaceOverlayState()

        let before = store.overlaySnapshot { _ in busy }
        #expect(CloseWorkspaceConfirmation.resolve(workspaceID: workspace.id, in: before, foregroundProcessTabs: []) != nil)
        state.present(.closeConfirmation(workspaceID: workspace.id, anchor: .titlebar))
        #expect(state.closeConfirmation?.workspaceID == workspace.id)

        #expect(store.closeWorkspace(id: workspace.id))

        let after = store.overlaySnapshot { _ in busy }
        #expect(CloseWorkspaceConfirmation.resolve(workspaceID: workspace.id, in: after, foregroundProcessTabs: []) == nil)
        state.reconcile(workspaceIDs: after.workspaceIDs)
        #expect(state.closeConfirmation == nil)
        #expect(!state.isAnyOpen)
    }

    @Test func requestCloseAsksOnlyWhenBusy() {
        let busy = busyWorkspace()
        let calm = OverlayFixtures.workspace("docs", tabs: [TabSpec(title: "a", state: .done)])
        let snapshot = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("Default", isDefault: true),
            busy,
            calm,
        ])
        let state = WorkspaceOverlayState()
        var closed: [UUID] = []

        state.requestClose(workspaceID: busy.id, anchor: .card, in: snapshot) { closed.append($0) }
        #expect(closed.isEmpty)
        #expect(state.closeConfirmation?.workspaceID == busy.id)
        #expect(state.closeConfirmation?.anchor == .card)

        state.dismiss(.closeConfirmation)
        state.requestClose(workspaceID: calm.id, anchor: .titlebar, in: snapshot) { closed.append($0) }
        #expect(closed == [calm.id])
        #expect(state.closeConfirmation == nil)
    }

    @Test func requestCloseIgnoresDefaultAndUnknown() {
        let def = OverlayFixtures.workspace("Default", isDefault: true, tabs: [TabSpec(title: "x", state: .running)])
        let snapshot = OverlayFixtures.snapshot([def])
        let state = WorkspaceOverlayState()
        var closed: [UUID] = []

        state.requestClose(workspaceID: def.id, anchor: .titlebar, in: snapshot) { closed.append($0) }
        state.requestClose(workspaceID: UUID(), anchor: .titlebar, in: snapshot) { closed.append($0) }
        #expect(closed.isEmpty)
        #expect(!state.isAnyOpen)
    }
}
