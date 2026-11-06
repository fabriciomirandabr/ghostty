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

    static func makePersisted(
        from store: MockStore,
        pwdOf view: MockView,
        resume: (MockView) -> ProgramResume? = { _ in nil }
    ) -> WorkspacePersistedState {
        WorkspacePersistedState(
            store: store,
            directory: { $0 === view ? "/tmp/ws-docs/notes" : nil },
            resume: resume)
    }

    static let sampleResume = ProgramResume(program: "claude", token: "0f8fad5b-d9cb-469f-a165-70867728950e")

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
            makeTree: { directory, _ -> SplitTree<MockView> in
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

    @Test func persistedStateIsVersionTwo() throws {
        #expect(WorkspacePersistedState.currentVersion == 2)
        let (store, docsView) = try Self.makePopulatedStore()
        #expect(Self.makePersisted(from: store, pwdOf: docsView).version == 2)
    }

    @Test func persistedTabsCarryTheResumeOfTheFocusedSurface() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let other = try #require(store.workspaces[1].tabs[0].tree.first { $0 !== docsView })
        let persisted = Self.makePersisted(from: store, pwdOf: docsView) { view in
            if view === docsView { return Self.sampleResume }
            if view === other { return ProgramResume(program: "claude", token: "1b4e28ba-2fa1-41d2-883f-0016d3cca427") }
            return nil
        }

        let tabs = persisted.workspaces[1].tabs
        #expect(tabs[0].resumeProgram == "claude")
        #expect(tabs[0].resumeToken == "0f8fad5b-d9cb-469f-a165-70867728950e")
        #expect(tabs[1].resumeProgram == nil)
        #expect(tabs[1].resumeToken == nil)
    }

    @Test func disabledConfigPersistsNoResume() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let persisted = Self.makePersisted(from: store, pwdOf: docsView, resume: { _ in nil })
        let data = try JSONEncoder().encode(persisted)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(persisted.workspaces.flatMap(\.tabs).allSatisfy { $0.resumeProgram == nil && $0.resumeToken == nil })
        #expect(!json.contains("resume"))
    }

    @Test func persistedTabsCarryNoResumeCommand() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let persisted = Self.makePersisted(from: store, pwdOf: docsView) { _ in Self.sampleResume }
        let data = try JSONEncoder().encode(persisted)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"resumeToken\":\"0f8fad5b-d9cb-469f-a165-70867728950e\""))
        #expect(!json.contains("--resume"))
    }

    @Test func resumeSurvivesTheFileRoundTrip() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let persisted = Self.makePersisted(from: store, pwdOf: docsView) { $0 === docsView ? Self.sampleResume : nil }
        let fileStore = WorkspaceStateStore(fileURL: Self.makeTemporaryFileURL())

        try fileStore.save(persisted)
        let loaded = try #require(try fileStore.load())

        #expect(loaded == persisted)
        #expect(loaded.workspaces[1].tabs[0].resumeToken == "0f8fad5b-d9cb-469f-a165-70867728950e")
    }

    @Test func aVersionOneFileLoadsWithoutResume() throws {
        let id = UUID().uuidString
        let tab = UUID().uuidString
        let json = """
        {"version":1,"selectedWorkspace":"\(id)","workspaces":[{"id":"\(id)","name":"Default","directory":"/tmp",\
        "isDefault":true,"selectedTab":"\(tab)","tabs":[{"id":"\(tab)","directory":"/tmp"}]}]}
        """
        let url = Self.makeTemporaryFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)

        let loaded = try #require(try WorkspaceStateStore(fileURL: url).load())

        #expect(loaded.version == 1)
        #expect(loaded.workspaces[0].tabs[0].resumeProgram == nil)
        #expect(loaded.workspaces[0].tabs[0].resumeToken == nil)
    }

    @Test(arguments: [
        ("sh", "0f8fad5b-d9cb-469f-a165-70867728950e"),
        ("claude", "a;b"),
        ("claude", "$(id)"),
        ("claude", ""),
        ("claude", "-x"),
        ("claude", "--dangerously-skip-permissions"),
        ("claude", "0F8FAD5B-D9CB-469F-A165-70867728950E"),
        ("claude", "0f8fad5b-d9cb-469f-a165-70867728950"),
        ("claude", "0f8fad5b-d9cb-469f-a165-70867728950ee"),
        ("claude", String(repeating: "a", count: 10_240)),
        ("Claude", "0f8fad5b-d9cb-469f-a165-70867728950e"),
    ])
    func sanitizedDropsInvalidResume(program: String, token: String) throws {
        let (store, docsView) = try Self.makePopulatedStore()
        var state = Self.makePersisted(from: store, pwdOf: docsView) { _ in Self.sampleResume }
        state.workspaces[1].tabs[0].resumeProgram = program
        state.workspaces[1].tabs[0].resumeToken = token

        let clean = state.sanitized()

        #expect(clean.workspaces[1].tabs[0].resumeProgram == nil)
        #expect(clean.workspaces[1].tabs[0].resumeToken == nil)
        #expect(clean.workspaces[1].tabs[1].resumeToken == "0f8fad5b-d9cb-469f-a165-70867728950e")
    }

    @Test func sanitizedDropsPartialResume() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        var state = Self.makePersisted(from: store, pwdOf: docsView)
        state.workspaces[1].tabs[0].resumeProgram = "claude"
        state.workspaces[1].tabs[1].resumeToken = "1b4e28ba-2fa1-41d2-883f-0016d3cca427"

        let clean = state.sanitized()

        #expect(clean.workspaces[1].tabs.allSatisfy { $0.resumeProgram == nil && $0.resumeToken == nil })
    }

    @Test func sanitizedKeepsValidResume() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let state = Self.makePersisted(from: store, pwdOf: docsView) { _ in Self.sampleResume }

        #expect(state.sanitized() == state)
    }

    @Test(arguments: ["-x", "--dangerously-skip-permissions", "abc-123"])
    func resolvedResumeRejectsAFileTokenThatIsNotASessionId(token: String) {
        var tab = WorkspacePersistedTab(id: "t", titleOverride: nil, directory: "/tmp")
        tab.resumeProgram = "claude"
        tab.resumeToken = token

        #expect(WorkspacePersistedState.resolvedResume(tab: tab, isDirectory: { _ in true }) == nil)

        tab.resumeToken = "0f8fad5b-d9cb-469f-a165-70867728950e"
        #expect(WorkspacePersistedState.resolvedResume(tab: tab, isDirectory: { _ in true }) == Self.sampleResume)
    }

    @Test func resumeAloneIsNotStructural() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let base = Self.makePersisted(from: store, pwdOf: docsView)
        var resumed = base
        resumed.workspaces[1].tabs[0].resumeProgram = "claude"
        resumed.workspaces[1].tabs[0].resumeToken = "0f8fad5b-d9cb-469f-a165-70867728950e"
        var moved = base
        moved.workspaces[1].tabs[0].directory = "/tmp/elsewhere"

        var renamed = base
        renamed.workspaces[1].tabs[0].titleOverride = "renamed"

        #expect(resumed.hasSameStructure(as: base))
        #expect(moved.hasSameStructure(as: base))
        #expect(!renamed.hasSameStructure(as: base))
    }

    @Test func aRestoredTabPersistsTheSameResumeOnItsFirstSnapshot() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let saved = Self.makePersisted(from: store, pwdOf: docsView) { $0 === docsView ? Self.sampleResume : nil }
        var seeded: [UUID: ProgramResume] = [:]
        let state = saved.makeWorkspacesState(
            isDirectory: { _ in true },
            makeTree: { _, resume -> SplitTree<MockView> in
                let view = MockView()
                if let resume { seeded[view.id] = resume }
                return SplitTree(view: view)
            })
        let restored = MockStore(restoring: state, defaultDirectory: WorkspaceFixtures.home) {
            WorkspaceFixtures.makeTab()
        }

        let again = WorkspacePersistedState(store: restored, directory: { _ in nil }, resume: { seeded[$0.id] })

        #expect(again.workspaces.flatMap(\.tabs).map(\.resumeToken) == saved.workspaces.flatMap(\.tabs).map(\.resumeToken))
        #expect(again.workspaces[1].tabs[0].resumeToken == Self.sampleResume?.token)
    }

    @Test func makeWorkspacesStatePassesResumeOnlyWhenTheTabDirectoryExists() throws {
        let (store, docsView) = try Self.makePopulatedStore()
        let persisted = Self.makePersisted(from: store, pwdOf: docsView) { $0 === docsView ? Self.sampleResume : nil }

        var onlyWorkspaceFolder: [ProgramResume?] = []
        _ = persisted.makeWorkspacesState(
            isDirectory: { $0.path == "/tmp/ws-docs" },
            makeTree: { _, resume -> SplitTree<MockView> in
                onlyWorkspaceFolder.append(resume)
                return SplitTree(view: MockView())
            })
        #expect(onlyWorkspaceFolder.allSatisfy { $0 == nil })

        var tabFolderExists: [ProgramResume?] = []
        _ = persisted.makeWorkspacesState(
            isDirectory: { _ in true },
            makeTree: { _, resume -> SplitTree<MockView> in
                tabFolderExists.append(resume)
                return SplitTree(view: MockView())
            })
        #expect(tabFolderExists.count == 3)
        #expect(tabFolderExists.compactMap { $0 } == [try #require(Self.sampleResume)])
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
