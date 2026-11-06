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

    private func splitSnapshot() -> WorkspaceOverlaySnapshot {
        OverlayFixtures.snapshot([
            OverlayFixtures.workspace("Default", isDefault: true),
            OverlayFixtures.workspace("api", tabs: [
                TabSpec(title: "agent", panes: [
                    PaneSpec(title: "claude", state: .running, pwd: "\(OverlayFixtures.home)/code/api", command: "claude"),
                    PaneSpec(title: "pnpm dev", state: .running, pwd: "\(OverlayFixtures.home)/code/api/web", command: "pnpm dev"),
                ]),
            ]),
            OverlayFixtures.workspace("web", tabs: [TabSpec(title: "tests", state: .running)]),
        ])
    }

    private func rows(_ snapshot: WorkspaceOverlaySnapshot) -> [ActivityRow] {
        ActivityRows.sections(from: snapshot, home: OverlayFixtures.home).flatMap(\.rows)
    }

    @Test func singlePaneTabsKeepOneRowWithoutHeader() {
        let sections = ActivityRows.sections(from: snapshot(), home: OverlayFixtures.home)
        #expect(sections.allSatisfy { $0.header == nil && $0.rows.count == 1 })
        let rows = sections.flatMap(\.rows)
        #expect(rows.map(\.title) == ["agent", "dev", "agent", "tests"])
        #expect(rows.map(\.state) == [.needsAttention, .running, .running, .done])
        #expect(rows.map(\.subtitle) == ["api · claude", "api · pnpm dev", "web", "web · pnpm test"])
    }

    @Test func splitTabGetsHeaderAndOnePaneRowEach() throws {
        let snap = splitSnapshot()
        let sections = ActivityRows.sections(from: snap, home: OverlayFixtures.home)
        let split = try #require(sections.first { $0.header != nil })
        #expect(sections.count == 2)
        #expect(split.header == "agent · api")
        #expect(split.rows.map(\.title) == ["claude", "pnpm dev"])
        let panes = try #require(snap.workspaces[1].tabs.first?.panes)
        #expect(split.rows.map(\.surfaceID) == panes.map(\.id))
    }

    @Test func idlePanesOfASplitTabAreOmitted() throws {
        let snap = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("api", tabs: [
                TabSpec(title: "agent", panes: [
                    PaneSpec(title: "claude", state: .running),
                    PaneSpec(title: "shell"),
                ]),
            ]),
        ])
        let sections = ActivityRows.sections(from: snap, home: OverlayFixtures.home)
        #expect(sections.count == 1)
        #expect(sections[0].header == "agent · api")
        #expect(sections[0].rows.map(\.title) == ["claude"])
    }

    @Test func splitTabWithAllPanesIdleIsOmitted() {
        let snap = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("api", tabs: [
                TabSpec(title: "agent", panes: [PaneSpec(title: "a"), PaneSpec(title: "b")]),
            ]),
        ])
        #expect(ActivityRows.sections(from: snap, home: OverlayFixtures.home).isEmpty)
    }

    @Test func paneRowSubtitleShowsFolderAndCommand() {
        let snap = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("api", tabs: [
                TabSpec(title: "agent", panes: [
                    PaneSpec(title: "claude", state: .running, pwd: "\(OverlayFixtures.home)/code/api", command: "claude"),
                    PaneSpec(title: "serve", state: .running, pwd: "\(OverlayFixtures.home)/code/api/web"),
                    PaneSpec(title: "bare", state: .running, command: "make"),
                    PaneSpec(title: "empty", state: .running),
                ]),
            ]),
        ])
        #expect(rows(snap).map(\.subtitle) == ["~/code/api · claude", "~/code/api/web", "make", ""])
    }

    @Test func sectionsAndRowsSortedByPriority() throws {
        let snap = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("api", tabs: [
                TabSpec(title: "agent", panes: [
                    PaneSpec(title: "first", state: .running),
                    PaneSpec(title: "second", state: .done),
                    PaneSpec(title: "third", state: .running),
                ]),
                TabSpec(title: "single", state: .running),
            ]),
            OverlayFixtures.workspace("web", tabs: [
                TabSpec(title: "pair", panes: [
                    PaneSpec(title: "left", state: .running),
                    PaneSpec(title: "right", state: .needsAttention),
                ]),
            ]),
        ])
        let sections = ActivityRows.sections(from: snap, home: OverlayFixtures.home)
        #expect(sections.map(\.id) == [
            snap.workspaces[1].tabs[0].id,
            snap.workspaces[0].tabs[0].id,
            snap.workspaces[0].tabs[1].id,
        ])
        #expect(sections[0].rows.map(\.title) == ["right", "left"])
        #expect(sections[1].rows.map(\.title) == ["first", "third", "second"])
    }

    @Test func rowsPointAtTheirPane() throws {
        let snap = splitSnapshot()
        let all = rows(snap)
        #expect(Set(all.map(\.surfaceID)).count == all.count)
        for row in all {
            let workspace = try #require(snap.workspace(id: row.workspaceID))
            let tab = try #require(workspace.tabs.first { $0.id == row.tabID })
            #expect(tab.panes.contains { $0.id == row.surfaceID })
        }
    }

    @Test func samePaneTitlesStayDistinctRows() {
        let snap = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("api", tabs: [
                TabSpec(title: "agent", panes: [
                    PaneSpec(title: "claude", state: .running),
                    PaneSpec(title: "claude", state: .running),
                ]),
            ]),
        ])
        let all = rows(snap)
        #expect(all.count == 2)
        #expect(Set(all.map(\.id)).count == 2)
    }

    @Test func selectingARowSendsItsPaneToTheFocusPath() throws {
        let snap = splitSnapshot()
        let second = try #require(rows(snap).first { $0.title == "pnpm dev" })
        var requests: [(UUID, UUID, UUID?)] = []
        let actions = WorkspaceOverlayActions(
            selectWorkspace: { _ in },
            selectTab: { requests.append(($0, $1, $2)) },
            closeWorkspace: { _ in },
            createWorkspace: { _, _ in nil }
        )
        actions.selectTab(second.workspaceID, second.tabID, second.surfaceID)
        #expect(requests.count == 1)
        #expect(requests[0].0 == snap.workspaces[1].id)
        #expect(requests[0].1 == snap.workspaces[1].tabs[0].id)
        #expect(requests[0].2 == snap.workspaces[1].tabs[0].panes[1].id)
    }

    @Test func emptyWhenEverythingIsIdle() {
        let quiet = OverlayFixtures.snapshot([
            OverlayFixtures.workspace("Default", isDefault: true),
            OverlayFixtures.workspace("api"),
        ])
        #expect(ActivityRows.sections(from: quiet).isEmpty)
    }

    @Test func idleTabsAreExcluded() {
        #expect(!rows(snapshot()).contains { $0.title == "logs" || $0.title == "shell" })
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
        #expect(api.tabs[0].panes.map(\.id) == [first.id, second.id])
        #expect(api.tabs[0].panes.map(\.state) == [.running, .needsAttention])
        #expect(api.tabs[0].runningPaneCount == 1)
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
