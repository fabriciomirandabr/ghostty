import Foundation
import Testing
@testable import Ghostty

@MainActor
struct WorkspaceOverlaySnapshotTests {
    private static let apiDirectory = URL(fileURLWithPath: "/tmp/ws-home/api")

    private static func info(
        _ title: String,
        state: SurfaceActivityState = .running,
        pwd: String? = nil,
        command: String? = nil
    ) -> WorkspaceSurfaceInfo {
        WorkspaceSurfaceInfo(title: title, lastCommand: command, state: state, pwd: pwd)
    }

    private func apiStore(
        views: [MockView],
        override: String? = nil,
        focusedIndex: Int = 0
    ) throws -> (store: MockStore, workspaceID: UUID, tabID: UUID) {
        let store = WorkspaceFixtures.makeStore()
        let workspace = try store.addWorkspace(name: "api", directory: Self.apiDirectory) {
            WorkspaceFixtures.makeTab(title: override, views: views)
        }
        let tabID = workspace.tabs[0].id
        #expect(store.updateTab(workspaceID: workspace.id, tabID: tabID) {
            $0.focusedSurfaceID = views[focusedIndex].id
        })
        return (store, workspace.id, tabID)
    }

    @Test func splitTabCarriesOnePaneEachInTreeOrder() throws {
        let views = [MockView(), MockView(), MockView()]
        let fixture = try apiStore(views: views)
        let infos: [UUID: WorkspaceSurfaceInfo] = [
            views[0].id: Self.info("claude", state: .running, pwd: "/tmp/ws-home/api", command: "claude"),
            views[1].id: Self.info("pnpm dev", state: .needsAttention, pwd: "/tmp/ws-home/api/web", command: "pnpm dev"),
            views[2].id: Self.info("", state: .idle, pwd: "/tmp/ws-home/api/docs", command: ""),
        ]
        let snapshot = fixture.store.overlaySnapshot { infos[$0.id] ?? Self.info("", state: .idle) }

        let tab = try #require(snapshot.workspace(id: fixture.workspaceID)?.tabs.first)
        let treeOrder = try #require(fixture.store.workspaces.first { $0.id == fixture.workspaceID }?.tabs.first)
            .tree.map(\.id)
        #expect(Set(treeOrder) == Set(views.map(\.id)))
        #expect(tab.panes.map(\.id) == treeOrder)
        let ordered = treeOrder.map { id in infos[id] ?? Self.info("") }
        #expect(tab.panes.map(\.state) == ordered.map(\.state))
        #expect(tab.panes.map(\.pwd) == ordered.map(\.pwd))
        #expect(tab.panes.map(\.lastCommand) == ordered.map { $0.lastCommand.flatMap { $0.isEmpty ? nil : $0 } })
        #expect(Set(tab.panes.map(\.title)) == ["claude", "pnpm dev", "docs"])
        #expect(tab.state == .needsAttention)
        #expect(tab.lastCommand == "pnpm dev")
        #expect(tab.runningPaneCount == 1)
        #expect(tab.isSplit)
    }

    @Test func singlePaneTabIsNotSplit() throws {
        let view = MockView()
        let fixture = try apiStore(views: [view])
        let snapshot = fixture.store.overlaySnapshot { _ in Self.info("claude", state: .running) }

        let tab = try #require(snapshot.workspace(id: fixture.workspaceID)?.tabs.first)
        #expect(tab.panes.map(\.id) == [view.id])
        #expect(tab.panes[0].label == tab.title)
        #expect(tab.runningPaneCount == 1)
        #expect(!tab.isSplit)
    }

    @Test func workspaceRunningPaneCountSumsPanesAcrossTabs() throws {
        let views = [MockView(), MockView()]
        let fixture = try apiStore(views: views)
        let extra = MockView()
        #expect(fixture.store.addTab(WorkspaceFixtures.makeTab(views: [extra]), to: fixture.workspaceID))
        let snapshot = fixture.store.overlaySnapshot { _ in Self.info("task", state: .running) }

        let api = try #require(snapshot.workspace(id: fixture.workspaceID))
        #expect(api.tabs.count == 2)
        #expect(api.runningPaneCount == 3)

        let onlySplit = fixture.store.overlaySnapshot { $0.id == extra.id ? Self.info("task", state: .done) : Self.info("task") }
        #expect(onlySplit.workspace(id: fixture.workspaceID)?.runningPaneCount == 2)
    }

    @Test func tabTitleStaysFocusedPaneOrOverride() throws {
        let views = [MockView(), MockView()]
        let infos: [UUID: WorkspaceSurfaceInfo] = [
            views[0].id: Self.info("claude"),
            views[1].id: Self.info("pnpm dev"),
        ]

        let focusedSecond = try apiStore(views: views, focusedIndex: 1)
        let second = focusedSecond.store.overlaySnapshot { infos[$0.id] ?? Self.info("") }
        #expect(second.workspace(id: focusedSecond.workspaceID)?.tabs[0].title == "pnpm dev")

        let renamed = try apiStore(views: views, override: "agent", focusedIndex: 1)
        let overridden = renamed.store.overlaySnapshot { infos[$0.id] ?? Self.info("") }
        #expect(overridden.workspace(id: renamed.workspaceID)?.tabs[0].title == "agent")
    }

    @Test func paneLabelsUseOverridePrefix() throws {
        let views = [MockView(), MockView()]
        let infos: [UUID: WorkspaceSurfaceInfo] = [
            views[0].id: Self.info("claude"),
            views[1].id: Self.info("pnpm dev"),
        ]

        let plain = try apiStore(views: views)
        let plainSnapshot = plain.store.overlaySnapshot { infos[$0.id] ?? Self.info("") }
        #expect(plainSnapshot.workspace(id: plain.workspaceID)?.tabs[0].panes.map(\.label) == ["claude", "pnpm dev"])

        let renamed = try apiStore(views: views, override: "agent")
        let renamedSnapshot = renamed.store.overlaySnapshot { infos[$0.id] ?? Self.info("") }
        #expect(renamedSnapshot.workspace(id: renamed.workspaceID)?.tabs[0].panes.map(\.label)
            == ["agent › claude", "agent › pnpm dev"])
    }
}
