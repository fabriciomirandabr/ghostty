import AppKit
import Testing
@testable import Ghostty

@MainActor
private final class RecordingDelegate: WorkspaceStoreDelegate {
    var entered: [MockView] = []
    var left: [MockView] = []

    func surfacesDidEnter(_ surfaces: [MockView]) {
        entered.append(contentsOf: surfaces)
    }

    func surfacesDidLeave(_ surfaces: [MockView]) {
        left.append(contentsOf: surfaces)
    }
}

@MainActor
struct WorkspaceStoreTests {
    private let home = WorkspaceFixtures.home

    private func makeTab(title: String? = nil, views: [MockView] = [MockView()]) -> MockTab {
        WorkspaceFixtures.makeTab(title: title, views: views)
    }

    private func makeStore() -> MockStore {
        WorkspaceFixtures.makeStore()
    }

    @Test func startsWithOnlyTheDefaultWorkspace() throws {
        let store = makeStore()
        #expect(store.workspaces.count == 1)
        #expect(store.workspaces[0].isDefault)
        #expect(store.workspaces[0].name == "Default")
        #expect(store.workspaces[0].directory == home)
        #expect(store.workspaces[0].tabs.count == 1)
        #expect(store.selectedWorkspaceID == store.workspaces[0].id)
        #expect(store.selectedTab?.id == store.workspaces[0].selectedTabID)
    }

    @Test func defaultWorkspaceCannotClose() throws {
        let store = makeStore()
        _ = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        #expect(store.closeWorkspace(id: store.workspaces[0].id) == false)
        #expect(store.workspaces.count == 2)
        #expect(store.workspaces.map(\.isDefault) == [true, false])
    }

    @Test func closeUnknownWorkspaceReturnsFalse() {
        let store = makeStore()
        #expect(store.closeWorkspace(id: UUID()) == false)
        #expect(store.workspaces.count == 1)
    }

    @Test func duplicateNameRejected() throws {
        let store = makeStore()
        _ = try store.addWorkspace(name: "Alpha", directory: home, makeTab: { makeTab() })

        #expect(throws: WorkspaceError.duplicateName) {
            try store.addWorkspace(name: "alpha", directory: home, makeTab: { makeTab() })
        }
        #expect(throws: WorkspaceError.duplicateName) {
            try store.addWorkspace(name: "  ALPHA  ", directory: home, makeTab: { makeTab() })
        }
        #expect(throws: WorkspaceError.duplicateName) {
            try store.addWorkspace(name: "default", directory: home, makeTab: { makeTab() })
        }
        #expect(store.workspaces.count == 2)
    }

    @Test func rejectedAddDoesNotBuildATab() {
        let store = makeStore()
        var calls = 0
        #expect(throws: WorkspaceError.duplicateName) {
            try store.addWorkspace(name: "Default", directory: home, makeTab: {
                calls += 1
                return makeTab()
            })
        }
        #expect(calls == 0)
    }

    @Test func nameNormalized() throws {
        let store = makeStore()
        let long = String(repeating: "x", count: 10_000)
        let added = try store.addWorkspace(name: "  \n" + long + "  ", directory: home, makeTab: { makeTab() })
        #expect(added.name.count == 40)
        #expect(added.name == String(repeating: "x", count: 40))

        #expect(throws: WorkspaceError.emptyName) {
            try store.addWorkspace(name: " \t\n ", directory: home, makeTab: { makeTab() })
        }
    }

    @Test func addWorkspaceKeepsSelectionAndOrder() throws {
        let store = makeStore()
        let first = store.selectedWorkspaceID
        let a = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        let b = try store.addWorkspace(name: "B", directory: home, makeTab: { makeTab() })
        #expect(store.workspaces.map(\.name) == ["Default", "A", "B"])
        #expect(store.workspaces.map(\.id) == [first, a.id, b.id])
        #expect(store.selectedWorkspaceID == first)
    }

    @Test func closeSelectsPrevious() throws {
        let store = makeStore()
        let a = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        let b = try store.addWorkspace(name: "B", directory: home, makeTab: { makeTab() })
        #expect(store.select(workspaceID: b.id))

        #expect(store.closeWorkspace(id: b.id))
        #expect(store.selectedWorkspaceID == a.id)
        #expect(store.closeWorkspace(id: a.id))
        #expect(store.selectedWorkspaceID == store.workspaces[0].id)
    }

    @Test func closingAnotherWorkspaceKeepsSelection() throws {
        let store = makeStore()
        let a = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        let b = try store.addWorkspace(name: "B", directory: home, makeTab: { makeTab() })
        #expect(store.select(workspaceID: b.id))
        #expect(store.closeWorkspace(id: a.id))
        #expect(store.selectedWorkspaceID == b.id)
    }

    @Test func closeDropsSnapshotsOfClosedTabs() throws {
        let store = makeStore()
        let a = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        let keep = store.workspaces[0].tabs[0].id
        let drop = a.tabs[0].id
        store.snapshots.store(NSImage(), for: keep)
        store.snapshots.store(NSImage(), for: drop)

        #expect(store.closeWorkspace(id: a.id))
        #expect(store.snapshots.image(for: keep) != nil)
        #expect(store.snapshots.image(for: drop) == nil)
    }

    @Test func selectChangesWorkspaceAndTab() throws {
        let store = makeStore()
        let a = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        let extra = makeTab()
        #expect(store.addTab(extra, to: a.id))
        let firstTabID = a.tabs[0].id

        #expect(store.select(workspaceID: a.id, tabID: firstTabID))
        #expect(store.selectedWorkspaceID == a.id)
        #expect(store.selectedTab?.id == firstTabID)
    }

    @Test func selectRejectsUnknownIDs() throws {
        let store = makeStore()
        let a = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        let before = store.selectedWorkspaceID

        #expect(store.select(workspaceID: UUID()) == false)
        #expect(store.select(workspaceID: a.id, tabID: UUID()) == false)
        #expect(store.selectedWorkspaceID == before)
    }

    @Test func previousAndNextAreCyclic() throws {
        let store = makeStore()
        let a = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        let b = try store.addWorkspace(name: "B", directory: home, makeTab: { makeTab() })
        let first = store.workspaces[0].id

        store.selectPrevious()
        #expect(store.selectedWorkspaceID == b.id)
        store.selectNext()
        #expect(store.selectedWorkspaceID == first)
        store.selectNext()
        #expect(store.selectedWorkspaceID == a.id)
        store.selectNext()
        store.selectNext()
        #expect(store.selectedWorkspaceID == first)
    }

    @Test func previousAndNextWithSingleWorkspaceStay() {
        let store = makeStore()
        let only = store.selectedWorkspaceID
        store.selectNext()
        #expect(store.selectedWorkspaceID == only)
        store.selectPrevious()
        #expect(store.selectedWorkspaceID == only)
    }

    @Test func gotoIsOneBasedAndIgnoresOutOfRange() throws {
        let store = makeStore()
        let a = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab() })
        let b = try store.addWorkspace(name: "B", directory: home, makeTab: { makeTab() })

        #expect(store.goto(index: 3))
        #expect(store.selectedWorkspaceID == b.id)
        #expect(store.goto(index: 2))
        #expect(store.selectedWorkspaceID == a.id)
        #expect(store.goto(index: 1))
        #expect(store.selectedWorkspaceID == store.workspaces[0].id)

        #expect(store.goto(index: 3))
        #expect(store.goto(index: 0) == false)
        #expect(store.goto(index: 4) == false)
        #expect(store.goto(index: -1) == false)
        #expect(store.selectedWorkspaceID == b.id)
    }

    @Test func removingLastTabCreatesReplacement() {
        let store = makeStore()
        let workspaceID = store.workspaces[0].id
        let original = store.workspaces[0].tabs[0]
        store.snapshots.store(NSImage(), for: original.id)

        var calls = 0
        let replacement = makeTab(title: "replacement")
        let removed = store.removeTab(workspaceID: workspaceID, tabID: original.id) {
            calls += 1
            return replacement
        }

        #expect(removed?.id == original.id)
        #expect(calls == 1)
        #expect(store.workspaces[0].tabs.count == 1)
        #expect(store.workspaces[0].tabs[0].id == replacement.id)
        #expect(store.workspaces[0].selectedTabID == replacement.id)
        #expect(store.snapshots.image(for: original.id) == nil)
    }

    @Test func removingTabSelectsNeighbor() {
        let store = makeStore()
        let workspaceID = store.workspaces[0].id
        let t0 = store.workspaces[0].tabs[0]
        let t1 = makeTab()
        let t2 = makeTab()
        let t3 = makeTab()
        store.addTab(t1, to: workspaceID)
        store.addTab(t2, to: workspaceID)
        store.addTab(t3, to: workspaceID)
        #expect(store.select(workspaceID: workspaceID, tabID: t1.id))

        var calls = 0
        let spare = {
            calls += 1
            return makeTab()
        }

        store.removeTab(workspaceID: workspaceID, tabID: t1.id, makeReplacement: spare)
        #expect(store.workspaces[0].selectedTabID == t2.id)

        store.removeTab(workspaceID: workspaceID, tabID: t0.id, makeReplacement: spare)
        #expect(store.workspaces[0].selectedTabID == t2.id)

        #expect(store.select(workspaceID: workspaceID, tabID: t3.id))
        store.removeTab(workspaceID: workspaceID, tabID: t3.id, makeReplacement: spare)
        #expect(store.workspaces[0].selectedTabID == t2.id)

        #expect(calls == 0)
        #expect(store.workspaces[0].tabs.map(\.id) == [t2.id])
    }

    @Test func removingUnknownTabChangesNothing() {
        let store = makeStore()
        var calls = 0
        let removed = store.removeTab(workspaceID: store.workspaces[0].id, tabID: UUID()) {
            calls += 1
            return makeTab()
        }
        #expect(removed == nil)
        #expect(calls == 0)
        #expect(store.workspaces[0].tabs.count == 1)
    }

    @Test func workspaceNeverHasZeroTabs() {
        let store = makeStore()
        let workspaceID = store.workspaces[0].id
        for _ in 0..<5 {
            let id = store.workspaces[0].selectedTabID
            store.removeTab(workspaceID: workspaceID, tabID: id, makeReplacement: { makeTab() })
            #expect(store.workspaces[0].tabs.count == 1)
        }
    }

    @Test func emptyTreeIsRejected() {
        #expect(MockTab(tree: SplitTree<MockView>()) == nil)

        var tab = makeTab()
        let before = tab.tree.map(\.id)
        #expect(tab.setTree(SplitTree<MockView>()) == false)
        #expect(tab.tree.map(\.id) == before)
    }

    @Test func updateTabAppliesTreeAndFocus() throws {
        let store = makeStore()
        let workspaceID = store.workspaces[0].id
        let tabID = store.workspaces[0].tabs[0].id
        let views = [MockView(), MockView()]
        let tree = makeTab(views: views).tree

        let applied = store.updateTab(workspaceID: workspaceID, tabID: tabID) { tab in
            tab.setTree(tree)
            tab.focusedSurfaceID = views[1].id
            tab.titleOverride = "build"
        }

        #expect(applied)
        let tab = try #require(store.workspaces[0].tab(id: tabID))
        #expect(tab.tree.map(\.id) == views.map(\.id))
        #expect(tab.focusedSurfaceID == views[1].id)
        #expect(tab.titleOverride == "build")
        #expect(store.updateTab(workspaceID: workspaceID, tabID: UUID()) { _ in } == false)
    }

    @Test func inactiveWorkspacesKeepTheirSurfaces() throws {
        let store = makeStore()
        let activeViews = [MockView(), MockView()]
        let inactiveView = MockView()

        let defaultID = store.workspaces[0].id
        store.addTab(makeTab(views: activeViews), to: defaultID)
        let other = try store.addWorkspace(name: "Other", directory: home, makeTab: { makeTab(views: [inactiveView]) })

        #expect(store.selectedWorkspaceID == defaultID)
        let ids = Set(store.allSurfaces.map(\.id))
        #expect(ids.contains(inactiveView.id))
        #expect(ids.isSuperset(of: activeViews.map(\.id)))
        #expect(store.workspace(id: other.id)?.surfaces.map(\.id) == [inactiveView.id])
        #expect(store.allSurfaces.count == 4)
    }

    @Test func containsFindsSurfacesInEveryWorkspace() throws {
        let store = makeStore()
        let hidden = MockView()
        let visible = MockView()
        store.addTab(makeTab(views: [visible]), to: store.workspaces[0].id)
        let other = try store.addWorkspace(name: "Other", directory: home, makeTab: { makeTab(views: [hidden]) })

        #expect(store.contains(visible))
        #expect(store.contains(hidden))
        #expect(store.contains(MockView()) == false)
        #expect(store.workspace(containing: hidden)?.id == other.id)
        #expect(store.workspace(containing: visible)?.id == store.workspaces[0].id)
        #expect(store.tab(containing: hidden)?.id == other.tabs[0].id)
        #expect(store.tab(containing: MockView()) == nil)
        #expect(store.workspace(containing: MockView()) == nil)
    }

    @Test func insertSplitsTheTabHoldingTheSurface() throws {
        let store = makeStore()
        let anchor = MockView()
        let other = try store.addWorkspace(name: "Other", directory: home, makeTab: { makeTab(views: [anchor]) })
        let added = MockView()
        let delegate = RecordingDelegate()
        store.delegate = delegate

        try store.insert(view: added, at: anchor, direction: .right)

        let tab = try #require(store.tab(containing: added))
        #expect(tab.id == other.tabs[0].id)
        #expect(tab.tree.map(\.id) == [anchor.id, added.id])
        #expect(delegate.entered.map(\.id) == [added.id])
        #expect(delegate.left.isEmpty)
        #expect(store.selectedWorkspaceID == store.workspaces[0].id)
    }

    @Test func insertAtUnknownSurfaceThrows() {
        let store = makeStore()
        #expect(throws: WorkspaceError.surfaceNotFound) {
            try store.insert(view: MockView(), at: MockView(), direction: .right)
        }
    }

    @Test func removeSurfaceShrinksTheTree() throws {
        let store = makeStore()
        let views = [MockView(), MockView()]
        let workspaceID = store.workspaces[0].id
        let tab = makeTab(views: views)
        store.addTab(tab, to: workspaceID)
        store.updateTab(workspaceID: workspaceID, tabID: tab.id) { $0.focusedSurfaceID = views[1].id }
        let delegate = RecordingDelegate()
        store.delegate = delegate

        var calls = 0
        #expect(store.remove(surface: views[1], makeReplacement: {
            calls += 1
            return makeTab()
        }))

        let shrunk = try #require(store.workspaces[0].tab(id: tab.id))
        #expect(shrunk.tree.map(\.id) == [views[0].id])
        #expect(shrunk.focusedSurfaceID == nil)
        #expect(store.contains(views[1]) == false)
        #expect(delegate.left.map(\.id) == [views[1].id])
        #expect(calls == 0)
    }

    @Test func removingTheLastSurfaceOfTheLastTabCreatesReplacement() {
        let store = makeStore()
        let only = store.workspaces[0].tabs[0].tree.map { $0 }[0]
        let replacement = makeTab(title: "replacement")
        let delegate = RecordingDelegate()
        store.delegate = delegate

        var calls = 0
        #expect(store.remove(surface: only, makeReplacement: {
            calls += 1
            return replacement
        }))

        #expect(calls == 1)
        #expect(store.workspaces[0].tabs.map(\.id) == [replacement.id])
        #expect(delegate.left.map(\.id) == [only.id])
        #expect(delegate.entered.map(\.id) == replacement.tree.map(\.id))
    }

    @Test func removeUnknownSurfaceReturnsFalse() {
        let store = makeStore()
        #expect(store.remove(surface: MockView(), makeReplacement: { makeTab() }) == false)
        #expect(store.workspaces[0].tabs.count == 1)
    }

    @Test func delegateSeesSurfacesEnteringAndLeaving() throws {
        let store = makeStore()
        let delegate = RecordingDelegate()
        store.delegate = delegate

        let wsView = MockView()
        let ws = try store.addWorkspace(name: "A", directory: home, makeTab: { makeTab(views: [wsView]) })
        #expect(delegate.entered.map(\.id) == [wsView.id])

        let tabViews = [MockView(), MockView()]
        let tab = makeTab(views: tabViews)
        store.addTab(tab, to: ws.id)
        #expect(delegate.entered.map(\.id) == [wsView.id] + tabViews.map(\.id))

        store.removeTab(workspaceID: ws.id, tabID: tab.id, makeReplacement: { makeTab() })
        #expect(delegate.left.map(\.id) == tabViews.map(\.id))

        #expect(store.closeWorkspace(id: ws.id))
        #expect(delegate.left.map(\.id) == tabViews.map(\.id) + [wsView.id])
    }

    @Test func delegateIsNotRetained() {
        let store = makeStore()
        var delegate: RecordingDelegate? = RecordingDelegate()
        store.delegate = delegate
        delegate = nil
        #expect(store.delegate == nil)
    }
}
