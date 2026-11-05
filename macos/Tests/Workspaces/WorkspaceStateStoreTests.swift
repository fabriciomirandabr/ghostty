import AppKit
import Testing
@testable import Ghostty

@MainActor
struct WorkspaceStateStoreTests {
    static func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(WorkspaceStateStore.fileName, isDirectory: false)
    }

    static func makePopulatedStore() throws -> (MockStore, MockView) {
        let store = WorkspaceFixtures.makeStore()
        let docsView = MockView()
        let docs = URL(fileURLWithPath: "/tmp/ws-docs")
        let added = try store.addWorkspace(name: "Docs", directory: docs, makeTab: {
            WorkspaceFixtures.makeTab(title: "writing", views: [docsView, MockView()])
        })
        store.addTab(WorkspaceFixtures.makeTab(title: "second"), to: added.id)
        store.select(workspaceID: added.id, tabID: added.tabs[0].id)
        return (store, docsView)
    }

    static func makePersisted(from store: MockStore, pwdOf view: MockView) -> WorkspacePersistedState {
        WorkspacePersistedState(store: store, directory: { $0 === view ? "/tmp/ws-docs/notes" : nil })
    }

    @Test func persistedStateCapturesWorkspacesTabsAndSelection() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let persisted = Self.makePersisted(from: store, pwdOf: docsView)

        #expect(persisted.version == WorkspacePersistedState.currentVersion)
        #expect(persisted.selectedWorkspace == store.selectedWorkspaceID.uuidString)
        #expect(persisted.workspaces.map(\.name) == ["Default", "Docs"])
        #expect(persisted.workspaces.map(\.isDefault) == [true, false])
        #expect(persisted.workspaces[1].directory == "/tmp/ws-docs")
        #expect(persisted.workspaces[1].selectedTab == store.workspaces[1].selectedTabID.uuidString)
        #expect(persisted.workspaces[1].tabs.map(\.titleOverride) == ["writing", "second"])
        #expect(persisted.workspaces[1].tabs.map(\.directory) == ["/tmp/ws-docs/notes", "/tmp/ws-docs"])
        #expect(persisted.workspaces[0].tabs[0].directory == WorkspaceFixtures.home.path)
    }

    @Test func persistedTabsCarryNoProgramTitle() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let data = try JSONEncoder().encode(Self.makePersisted(from: store, pwdOf: docsView))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("titleOverride"))
        #expect(!json.contains("\"title\""))
    }

    @Test func saveThenLoadRoundTripsThroughTheFile() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let persisted = Self.makePersisted(from: store, pwdOf: docsView)
        let fileStore = WorkspaceStateStore(fileURL: Self.makeTemporaryFileURL())

        #expect(try fileStore.load() == nil)
        try fileStore.save(persisted)
        let loaded = try #require(try fileStore.load())
        #expect(loaded == persisted)

        var created: [URL] = []
        let state = loaded.makeWorkspacesState(
            isDirectory: { _ in true },
            makeTree: { directory -> SplitTree<MockView> in
                created.append(directory)
                return SplitTree(view: MockView())
            })
        let restored = MockStore(restoring: state, defaultDirectory: WorkspaceFixtures.home) {
            WorkspaceFixtures.makeTab()
        }

        #expect(restored.workspaces.map(\.id) == store.workspaces.map(\.id))
        #expect(restored.workspaces.map(\.name) == ["Default", "Docs"])
        #expect(restored.workspaces[1].directory.path == "/tmp/ws-docs")
        #expect(restored.selectedWorkspaceID == store.selectedWorkspaceID)
        #expect(restored.workspaces[1].selectedTabID == store.workspaces[1].selectedTabID)
        #expect(restored.workspaces[1].tabs.map(\.id) == store.workspaces[1].tabs.map(\.id))
        #expect(restored.workspaces[1].tabs.map(\.titleOverride) == ["writing", "second"])
        #expect(created.map(\.path) == [WorkspaceFixtures.home.path, "/tmp/ws-docs/notes", "/tmp/ws-docs"])
        #expect(restored.allSurfaces.count == 3)
    }

    @Test func loadRejectsAFileWrittenByANewerVersion() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        var newer = Self.makePersisted(from: store, pwdOf: docsView)
        newer.version = WorkspacePersistedState.currentVersion + 1
        let fileStore = WorkspaceStateStore(fileURL: Self.makeTemporaryFileURL())
        try fileStore.save(newer)

        #expect(throws: WorkspaceStateStoreError.newerVersion(newer.version)) {
            try fileStore.load()
        }
    }

    @Test func sanitizedDropsBadAndDuplicateIDsAndCapsTheLists() {
        func tab(_ id: String) -> WorkspacePersistedTab {
            WorkspacePersistedTab(id: id, titleOverride: nil, directory: "/tmp")
        }
        func workspace(_ id: String, tabs: [WorkspacePersistedTab]) -> WorkspacePersistedWorkspace {
            WorkspacePersistedWorkspace(id: id, name: id, directory: "/tmp", isDefault: false, selectedTab: "", tabs: tabs)
        }
        let valid = UUID().uuidString
        let lowercase = valid.lowercased()
        let many = (0..<(WorkspacePersistedState.maxTabsPerWorkspace + 5)).map { _ in tab(UUID().uuidString) }
        let state = WorkspacePersistedState(selectedWorkspace: valid, workspaces: [
            workspace(valid, tabs: [tab("not-a-uuid"), tab(valid), tab(lowercase), tab(UUID().uuidString)]),
            workspace(lowercase, tabs: []),
            workspace("broken", tabs: []),
            workspace(UUID().uuidString, tabs: many),
        ] + (0..<WorkspacePersistedState.maxWorkspaces).map { _ in workspace(UUID().uuidString, tabs: []) })

        let clean = state.sanitized()

        #expect(clean.workspaces.count == WorkspacePersistedState.maxWorkspaces)
        #expect(clean.workspaces[0].id == valid)
        #expect(clean.workspaces[0].tabs.map(\.id) == [valid, state.workspaces[0].tabs[3].id])
        #expect(clean.workspaces[1].tabs.count == WorkspacePersistedState.maxTabsPerWorkspace)
        #expect(!clean.workspaces.contains { $0.id == lowercase || $0.id == "broken" })
    }

    @Test func missingDirectoriesFallBackToTheWorkspaceFolderThenHome() {
        let tab = WorkspacePersistedTab(id: "t", titleOverride: nil, directory: "/gone/project/sub")
        let workspace = WorkspacePersistedWorkspace(
            id: "w", name: "Project", directory: "/gone/project", isDefault: false, selectedTab: "t", tabs: [tab])

        let fromTab = WorkspacePersistedState.resolvedDirectory(tab: tab, workspace: workspace, isDirectory: { _ in true })
        #expect(fromTab.path == "/gone/project/sub")

        let fromWorkspace = WorkspacePersistedState.resolvedDirectory(tab: tab, workspace: workspace) {
            $0.path == "/gone/project"
        }
        #expect(fromWorkspace.path == "/gone/project")

        let home = WorkspacePersistedState.resolvedDirectory(tab: tab, workspace: workspace, isDirectory: { _ in false })
        #expect(home == FileManager.default.homeDirectoryForCurrentUser)
    }

    @Test func scheduledSavesAreThrottledToOneWriteKeepingTheLatestState() async throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let base = Self.makePersisted(from: store, pwdOf: docsView)
        let fileStore = WorkspaceStateStore(fileURL: Self.makeTemporaryFileURL(), debounceInterval: 0.2)

        var last = base
        for index in 0..<100 {
            last = base
            last.workspaces[1].name = "Docs \(index)"
            fileStore.scheduleSave(last)
        }
        #expect(fileStore.hasPendingSave)
        #expect(fileStore.writeCount == 0)
        #expect(try fileStore.load() == nil)

        try await Task.sleep(for: .milliseconds(600))

        #expect(!fileStore.hasPendingSave)
        #expect(fileStore.writeCount == 1)
        #expect(try fileStore.load() == last)
    }

    @Test func aPendingSaveIsNotPushedBackByLaterChanges() async throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let base = Self.makePersisted(from: store, pwdOf: docsView)
        let fileStore = WorkspaceStateStore(fileURL: Self.makeTemporaryFileURL(), debounceInterval: 0.3)

        fileStore.scheduleSave(base)
        let started = Date()
        while Date().timeIntervalSince(started) < 0.6, fileStore.writeCount == 0 {
            var churn = base
            churn.workspaces[1].name = "Docs \(Date().timeIntervalSinceReferenceDate)"
            fileStore.scheduleSave(churn)
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(fileStore.writeCount == 1)
        #expect(Date().timeIntervalSince(started) < 0.6)
    }

    @Test func flushWritesThePendingStateImmediately() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let persisted = Self.makePersisted(from: store, pwdOf: docsView)
        let fileStore = WorkspaceStateStore(fileURL: Self.makeTemporaryFileURL(), debounceInterval: 60)

        fileStore.scheduleSave(persisted)
        #expect(try fileStore.load() == nil)
        try fileStore.flush()
        #expect(!fileStore.hasPendingSave)
        #expect(try fileStore.load() == persisted)
    }

    @Test func deleteRemovesTheFileAndCancelsPendingSaves() async throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let persisted = Self.makePersisted(from: store, pwdOf: docsView)
        let fileStore = WorkspaceStateStore(fileURL: Self.makeTemporaryFileURL(), debounceInterval: 0.05)

        try fileStore.save(persisted)
        #expect(try fileStore.load() != nil)
        fileStore.scheduleSave(persisted)
        try fileStore.delete()

        #expect(!fileStore.hasPendingSave)
        #expect(!FileManager.default.fileExists(atPath: fileStore.fileURL.path))
        try await Task.sleep(for: .milliseconds(400))
        #expect(!FileManager.default.fileExists(atPath: fileStore.fileURL.path))
        try fileStore.delete()
    }

    @Test func defaultFileLivesInApplicationSupportScopedByBundleID() {
        let url = WorkspaceStateStore.defaultFileURL(bundleIdentifier: "com.example.terminal")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        #expect(url.lastPathComponent == "workspaces.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == "com.example.terminal")
        #expect(url.path.hasPrefix(support.path))
    }
}
