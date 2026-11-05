import Foundation
import Testing
@testable import Ghostty

@MainActor
struct ActivityRowsTests {
    private func snapshot() -> WorkspaceOverlaySnapshot {
        OverlayFixtures.snapshot([
            OverlayFixtures.workspace("Default", isDefault: true, tabs: [TabSpec(title: "shell")]),
            OverlayFixtures.workspace("api", tabs: [
                TabSpec(title: "dev", state: .running, command: "pnpm dev"),
                TabSpec(title: "agent", state: .needsAttention, command: "claude"),
                TabSpec(title: "logs"),
            ]),
            OverlayFixtures.workspace("web", tabs: [
                TabSpec(title: "tests", state: .done, command: "pnpm test"),
                TabSpec(title: "agent", state: .running),
            ]),
        ])
    }

    @Test func orderedByPriorityWithLastCommand() {
        let rows = ActivityRows.make(from: snapshot())
        #expect(rows.map(\.title) == ["agent", "dev", "agent", "tests"])
        #expect(rows.map(\.state) == [.needsAttention, .running, .running, .done])
        #expect(rows.map(\.subtitle) == ["api · claude", "api · pnpm dev", "web", "web · pnpm test"])
    }

    @Test func idleTabsAreExcluded() {
        let rows = ActivityRows.make(from: snapshot())
        #expect(!rows.contains { $0.title == "logs" || $0.title == "shell" })
    }

    @Test func emptyWhenEverythingIsIdle() {
        let quiet = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("Default", isDefault: true),
            OverlayFixtures.workspace("api"),
        ])
        #expect(ActivityRows.make(from: quiet).isEmpty)
    }

    @Test func rowsPointAtTheirTab() {
        let snap = snapshot()
        let rows = ActivityRows.make(from: snap)
        for row in rows {
            let workspace = snap.workspace(id: row.workspaceID)
            let tab = workspace?.tabs.first { $0.id == row.tabID }
            #expect(tab?.title == row.title)
            #expect(tab?.busiestSurfaceID == row.surfaceID)
        }
    }

    @Test func timingMatchesTheSpec() {
        #expect(ActivityPopoverTiming.openDelay == 0.25)
        #expect(ActivityPopoverTiming.closeDelay == 0.18)
    }

    @Test func snapshotFromStoreAggregatesPerTab() throws {
        let store = WorkspaceFixtures.makeStore()
        let defaultView = try #require(store.allSurfaces.first)
        let first = MockView()
        let second = MockView()
        let workspace = try store.addWorkspace(name: "api", directory: URL(fileURLWithPath: "/tmp/ws-home/api")) {
            WorkspaceFixtures.makeTab(views: [first, second])
        }
        store.select(workspaceID: workspace.id)

        let infos: [UUID: WorkspaceSurfaceInfo] = [
            defaultView.id: WorkspaceSurfaceInfo(title: "👻", lastCommand: nil, state: .idle, pwd: "/tmp/ws-home/Code/web"),
            first.id: WorkspaceSurfaceInfo(title: "claude", lastCommand: "claude", state: .running),
            second.id: WorkspaceSurfaceInfo(title: "pnpm dev", lastCommand: "pnpm dev", state: .needsAttention),
        ]
        let snapshot = store.overlaySnapshot { infos[$0.id] ?? WorkspaceSurfaceInfo(title: "", lastCommand: nil, state: .idle) }

        #expect(snapshot.workspaces.map(\.name) == ["Default", "api"])
        #expect(snapshot.workspaces.map(\.isCurrent) == [false, true])
        #expect(snapshot.workspaces[0].state == .idle)
        #expect(snapshot.workspaces[0].tabs[0].title == "web")

        let api = snapshot.workspaces[1]
        #expect(api.state == .needsAttention)
        #expect(api.tabs.count == 1)
        #expect(api.tabs[0].state == .needsAttention)
        #expect(api.tabs[0].busiestSurfaceID == second.id)
        #expect(api.tabs[0].lastCommand == "pnpm dev")
        #expect(api.tabs[0].title == "claude")
        #expect(api.selectedTabID == api.tabs[0].id)
    }

    @Test func tabTitleOverrideWins() {
        let store = WorkspaceFixtures.makeStore()
        let workspaceID = store.workspaces[0].id
        let tabID = store.workspaces[0].tabs[0].id
        #expect(store.updateTab(workspaceID: workspaceID, tabID: tabID) { $0.titleOverride = "Renamed" })

        let snapshot = store.overlaySnapshot { _ in
            WorkspaceSurfaceInfo(title: "from terminal", lastCommand: nil, state: .done)
        }
        #expect(snapshot.workspaces[0].tabs[0].title == "Renamed")
    }

    @Test func folderLabelAbbreviatesHome() {
        #expect(WorkspaceFolderLabel.abbreviated(path: "/tmp/ws-home", home: "/tmp/ws-home") == "~")
        #expect(WorkspaceFolderLabel.abbreviated(path: "/tmp/ws-home/Code/api", home: "/tmp/ws-home") == "~/Code/api")
        #expect(WorkspaceFolderLabel.abbreviated(path: "/tmp/ws-home2/x", home: "/tmp/ws-home") == "/tmp/ws-home2/x")
        #expect(WorkspaceFolderLabel.abbreviated(path: "/srv/docs", home: "/tmp/ws-home/") == "/srv/docs")
    }
}
