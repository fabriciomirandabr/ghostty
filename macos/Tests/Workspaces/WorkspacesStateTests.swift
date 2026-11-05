import AppKit
import Testing
@testable import Ghostty

@MainActor
struct WorkspacesStateTests {
    private let home = WorkspaceFixtures.home

    private func makeTab(title: String? = nil, views: [MockView] = [MockView()]) -> MockTab {
        WorkspaceFixtures.makeTab(title: title, views: views)
    }

    private func populatedStore() throws -> MockStore {
        let store = WorkspaceFixtures.makeStore()
        let views = [MockView(), MockView()]
        let docs = URL(fileURLWithPath: "/tmp/ws-docs")
        let added = try store.addWorkspace(name: "Docs", directory: docs, makeTab: {
            makeTab(title: "writing", views: views)
        })
        store.addTab(makeTab(title: "second"), to: added.id)
        store.select(workspaceID: added.id, tabID: added.tabs[0].id)
        return store
    }

    private func assertRestored(_ restored: MockStore, from store: MockStore) {
        #expect(restored.workspaces.map(\.id) == store.workspaces.map(\.id))
        #expect(restored.workspaces.map(\.name) == ["Default", "Docs"])
        #expect(restored.workspaces.map(\.isDefault) == [true, false])
        #expect(restored.workspaces[1].directory.path == "/tmp/ws-docs")
        #expect(restored.selectedWorkspaceID == store.selectedWorkspaceID)
        #expect(restored.workspaces[1].selectedTabID == store.workspaces[1].selectedTabID)
        #expect(restored.workspaces[1].tabs.map(\.titleOverride) == ["writing", "second"])
        #expect(restored.workspaces[1].tabs[0].focusedSurfaceID == store.workspaces[1].tabs[0].focusedSurfaceID)
        #expect(restored.allSurfaces.map(\.id) == store.allSurfaces.map(\.id))
    }

    @Test func roundTripJSON() throws {
        let store = try populatedStore()
        let data = try JSONEncoder().encode(store.makeState())
        let decoded = try JSONDecoder().decode(WorkspacesState<MockView>.self, from: data)

        let restored = MockStore(restoring: decoded, defaultDirectory: home, makeTab: { makeTab() })
        assertRestored(restored, from: store)
    }

    @Test func roundTripKeyedArchiver() throws {
        let store = try populatedStore()

        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(CodableBridge(store.makeState()), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        let bridge = try #require(
            unarchiver.decodeObject(
                of: CodableBridge<WorkspacesState<MockView>>.self,
                forKey: NSKeyedArchiveRootObjectKey
            )
        )
        unarchiver.finishDecoding()

        let restored = MockStore(restoring: bridge.value, defaultDirectory: home, makeTab: { makeTab() })
        assertRestored(restored, from: store)
    }

    @Test func invalidSelectionFallsToDefault() throws {
        let state = try populatedStore().makeState()
        let broken = WorkspacesState(selectedWorkspace: UUID().uuidString, workspaces: state.workspaces)

        let restored = MockStore(restoring: broken, defaultDirectory: home, makeTab: { makeTab() })
        #expect(restored.selectedWorkspaceID == restored.workspaces[0].id)
        #expect(restored.workspaces[0].isDefault)
    }

    @Test func invalidTabSelectionFallsToFirstTab() throws {
        let state = try populatedStore().makeState()
        let docs = state.workspaces[1]
        let broken = WorkspacesState(
            selectedWorkspace: state.selectedWorkspace,
            workspaces: [
                state.workspaces[0],
                WorkspaceState(
                    id: docs.id,
                    name: docs.name,
                    directory: docs.directory,
                    isDefault: docs.isDefault,
                    selectedTab: UUID().uuidString,
                    tabs: docs.tabs
                ),
            ]
        )

        let restored = MockStore(restoring: broken, defaultDirectory: home, makeTab: { makeTab() })
        #expect(restored.workspaces[1].selectedTabID == restored.workspaces[1].tabs[0].id)
    }

    @Test func emptyListCreatesDefault() {
        let empty = WorkspacesState<MockView>(selectedWorkspace: UUID().uuidString, workspaces: [])
        var calls = 0
        let restored = MockStore(restoring: empty, defaultDirectory: home, makeTab: {
            calls += 1
            return makeTab()
        })

        #expect(calls == 1)
        #expect(restored.workspaces.count == 1)
        #expect(restored.workspaces[0].isDefault)
        #expect(restored.workspaces[0].name == "Default")
        #expect(restored.workspaces[0].directory == home)
        #expect(restored.selectedWorkspaceID == restored.workspaces[0].id)
    }

    @Test func missingDefaultIsInsertedFirst() throws {
        let store = try populatedStore()
        let state = store.makeState()
        let withoutDefault = WorkspacesState(
            selectedWorkspace: state.selectedWorkspace,
            workspaces: [state.workspaces[1]]
        )

        let restored = MockStore(restoring: withoutDefault, defaultDirectory: home, makeTab: { makeTab() })
        #expect(restored.workspaces.map(\.name) == ["Default", "Docs"])
        #expect(restored.workspaces.map(\.isDefault) == [true, false])
        #expect(restored.selectedWorkspaceID == store.selectedWorkspaceID)
    }

    @Test func onlyOneDefaultSurvivesRestore() throws {
        let state = try populatedStore().makeState()
        let docs = state.workspaces[1]
        let twoDefaults = WorkspacesState(
            selectedWorkspace: state.selectedWorkspace,
            workspaces: [
                state.workspaces[0],
                WorkspaceState(
                    id: docs.id,
                    name: docs.name,
                    directory: docs.directory,
                    isDefault: true,
                    selectedTab: docs.selectedTab,
                    tabs: docs.tabs
                ),
            ]
        )

        let restored = MockStore(restoring: twoDefaults, defaultDirectory: home, makeTab: { makeTab() })
        #expect(restored.workspaces.map(\.isDefault) == [true, false])
        #expect(restored.workspaces[0].name == "Default")
    }

    @Test func workspaceWithoutValidTabsGetsReplacement() throws {
        let state = try populatedStore().makeState()
        let docs = state.workspaces[1]
        let hollow = WorkspacesState(
            selectedWorkspace: state.selectedWorkspace,
            workspaces: [
                state.workspaces[0],
                WorkspaceState(
                    id: docs.id,
                    name: docs.name,
                    directory: docs.directory,
                    isDefault: false,
                    selectedTab: docs.selectedTab,
                    tabs: []
                ),
            ]
        )

        var calls = 0
        let restored = MockStore(restoring: hollow, defaultDirectory: home, makeTab: {
            calls += 1
            return makeTab()
        })
        #expect(calls == 1)
        #expect(restored.workspaces[1].name == "Docs")
        #expect(restored.workspaces[1].tabs.count == 1)
    }
}
