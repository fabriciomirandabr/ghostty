import Testing
import AppKit
@testable import Ghostty

@Suite
struct TerminalRestorableTests {
    @Test
    func areYouForgettingToAddMigrationTests() {
        #expect(TerminalRestorableState.version == 8)
        #expect(TerminalRestorableState.minimumVersion == 5)

        #expect(QuickTerminalRestorableState.version == 1)
        #expect(QuickTerminalRestorableState.minimumVersion == 1)
    }

    @MainActor
    @Test func quickTerminalRestorableFromV1() throws {
        /* v1
        let tree = try SplitTreeTests.makeHorizontalSplit()
        let state = DummyQuickTerminalRestorableState(
            focusedSurface: "123",
            surfaceTree: tree.0,
            screenStateEntries: [:],
        )
        let data = try archive(CodableBridge(state), className: "CodableBridge<QuickTerminal>")
        print(data.base64EncodedString())
        print(tree.1.id)
        print(tree.2.id)
        */

        let decoded: CodableBridge<DummyQuickTerminalRestorableState> = try unarchive(v1QTData, className: "CodableBridge<QuickTerminal>")
        let state = decoded.value.internalState

        #expect(state.focusedSurface == "123")
        #expect(state.screenStateEntries.isEmpty)
        #expect(state.surfaceTree.contains(where: { $0.id.uuidString == "2F2F2D93-944C-474A-83BA-4DC1868C3EB9" }))
        #expect(state.surfaceTree.contains(where: { $0.id.uuidString == "994C673F-B4C5-49EE-B044-65006652636D" }))
    }

    // To generate old data: created a dummy class, archive, and copy the printed result
    @MainActor
    @Test func restoreTerminal57() throws {

//        let tree = try SplitTreeTests.makeHorizontalSplit()
//        let state = DummyTerminalRestorableState(
//            focusedSurface: "v5",
//            surfaceTree: tree.0,
//        )
//        let data = try archive(CodableBridge(state), className: "CodableBridge<Terminal>")
//        print(data.base64EncodedString())
//        print()
//        print(tree.1.id)
//        print(tree.2.id)

        let v5 = try unarchive(v5Data, className: "CodableBridge<Terminal>", as: CodableBridge<DummyTerminalRestorableState>.self)
            .value.internalState
        #expect(v5.focusedSurface == "v5")
        #expect(v5.effectiveFullscreenMode == nil)
        #expect(v5.tabColor == nil)
        #expect(v5.titleOverride == nil)
        #expect(v5.workspaces == nil)
        #expect(v5.surfaceTree.contains(where: { $0.id.uuidString == "926F3F2A-824C-40C9-87CA-2CDCA4E11049" }))
        #expect(v5.surfaceTree.contains(where: { $0.id.uuidString == "AC5E829B-85FD-4C69-B196-2EE469C72A90" }))

//        let tree = try SplitTreeTests.makeHorizontalSplit()
//        let state = DummyTerminalRestorableState(
//            focusedSurface: "v7",
//            surfaceTree: tree.0,
//            effectiveFullscreenMode: .native,
//            tabColor: .green,
//            titleOverride: "1.3.0"
//        )
//        let data = try archive(CodableBridge(state), className: "CodableBridge<Terminal>")
//        print(data.base64EncodedString())
//        print()
//        print(tree.1.id)
//        print(tree.2.id)

        let v7 = try unarchive(v7Data, className: "CodableBridge<Terminal>", as: CodableBridge<DummyTerminalRestorableState>.self)
            .value.internalState
        #expect(v7.focusedSurface == "v7")
        #expect(v7.effectiveFullscreenMode == .native)
        #expect(v7.tabColor == .green)
        #expect(v7.titleOverride == "1.3.0")
        #expect(v7.workspaces == nil)
        #expect(v7.surfaceTree.contains(where: { $0.id.uuidString == "5D580A7A-81EA-47C6-BB9A-AD4B1783E478" }))
        #expect(v7.surfaceTree.contains(where: { $0.id.uuidString == "96EA1189-7482-41BC-A6CD-26E5190E4BFA" }))

//        let tree = try SplitTreeTests.makeHorizontalSplit()
//        let state = DummyTerminalRestorableState(
//            .init(
//                focusedSurface: "v7 generic",
//                surfaceTree: tree.0,
//                effectiveFullscreenMode: .native,
//                tabColor: .green,
//                titleOverride: "tip"
//            )
//        )
//        let data = try archive(CodableBridge(state), className: "CodableBridge<Terminal>")
//        print(data.base64EncodedString())
//        print()
//        print(tree.1.id)
//        print(tree.2.id)

        let v7Generic = try unarchive(v7GenericData, className: "CodableBridge<Terminal>", as: CodableBridge<DummyTerminalRestorableState>.self)
            .value.internalState
        #expect(v7Generic.focusedSurface == "v7 generic")
        #expect(v7Generic.effectiveFullscreenMode == .native)
        #expect(v7Generic.tabColor == .green)
        #expect(v7Generic.titleOverride == "tip")
        #expect(v7Generic.workspaces == nil)
        #expect(v7Generic.surfaceTree.contains(where: { $0.id.uuidString == "953CE952-D91D-4D36-AC72-9D0F1F6BCE73" }))
        #expect(v7Generic.surfaceTree.contains(where: { $0.id.uuidString == "D3223569-2E01-4BC5-9DB2-DBFC3AFF46D1" }))
    }

    @MainActor
    @Test func restoreTerminal8() throws {
        let v8 = try unarchive(terminalRestorableV8Data, className: "CodableBridge<Terminal>", as: CodableBridge<DummyTerminalRestorableState>.self)
            .value.internalState
        #expect(v8.focusedSurface == "v8")
        #expect(v8.effectiveFullscreenMode == nil)
        #expect(v8.tabColor == .green)
        #expect(v8.titleOverride == "workspaces")
        #expect(v8.surfaceTree.contains(where: { $0.id.uuidString == "6F1D2C3A-9B4E-4A7D-8C21-5E0F7A9B3D14" }))

        let workspaces = try #require(v8.workspaces)
        #expect(workspaces.selectedWorkspace == "3B7E9A12-5D40-4C8F-A6E1-9D2B7C0F4E58")
        #expect(workspaces.workspaces.map(\.name) == ["Default", "Docs"])
        #expect(workspaces.workspaces.map(\.directory) == ["/tmp/ws-home", "/tmp/ws-docs"])
        #expect(workspaces.workspaces.map(\.isDefault) == [true, false])
        #expect(workspaces.workspaces[1].selectedTab == "51C9E3A7-F280-4B6D-83A5-D7094E1B6C2F")

        let tab = workspaces.workspaces[0].tabs[0]
        #expect(tab.id == "E4A19C57-0B3D-4682-9F5A-7C18D2E6B403")
        #expect(tab.titleOverride == "build")
        #expect(tab.focusedSurface == "A83E5B90-12C7-4F6A-B3D8-0C4E9F716A25")
        #expect(tab.surfaceTree.map { $0.id.uuidString } == [
            "6F1D2C3A-9B4E-4A7D-8C21-5E0F7A9B3D14",
            "A83E5B90-12C7-4F6A-B3D8-0C4E9F716A25",
        ])

        let docsTab = workspaces.workspaces[1].tabs[0]
        #expect(docsTab.titleOverride == nil)
        #expect(docsTab.focusedSurface == nil)
    }

    @MainActor
    @Test func workspaceArchiveDecodesEverySurfaceOnce() throws {
        let selectedViews = [CountingView(), CountingView()]
        let otherViews = [CountingView()]
        let allIDs = Set((selectedViews + otherViews).map(\.id))

        let store = WorkspaceStore<CountingView>(
            defaultDirectory: WorkspaceFixtures.home,
            makeTab: { Self.makeCountingTab(selectedViews) })
        try store.addWorkspace(name: "Other", directory: WorkspaceFixtures.home, makeTab: {
            Self.makeCountingTab(otherViews)
        })

        let tree = try #require(store.selectedTab?.tree)
        let state = TerminalRestorableState.InternalState<CountingView>(
            focusedSurface: selectedViews[0].id.uuidString,
            surfaceTree: tree,
            effectiveFullscreenMode: nil,
            tabColor: nil,
            titleOverride: nil,
            workspaces: store.makeState())
        let data = try JSONEncoder().encode(state)

        CountingView.resetDecodes()
        let decoded = try JSONDecoder().decode(TerminalRestorableState.InternalState<CountingView>.self, from: data)

        let decodedIDs = CountingView.decodedIDs.filter { allIDs.contains($0) }
        #expect(decodedIDs.count == allIDs.count)
        #expect(Set(decodedIDs) == allIDs)
        #expect(decoded.restoredSurfaceTree.map(\.id) == selectedViews.map(\.id))
    }

    @MainActor
    @Test func workspacesSurviveTheWindowRestorationCoder() throws {
        let store = WorkspaceFixtures.makeStore()
        let docs = try store.addWorkspace(name: "Docs", directory: URL(fileURLWithPath: "/tmp/ws-docs"), makeTab: {
            WorkspaceFixtures.makeTab(title: "writing", views: [MockView(), MockView()])
        })
        store.select(workspaceID: docs.id)
        let tree = try #require(store.selectedTab?.tree)
        let state = DummyTerminalRestorableState(.init(
            focusedSurface: tree.first?.id.uuidString,
            surfaceTree: tree,
            effectiveFullscreenMode: nil,
            tabColor: nil,
            titleOverride: nil,
            workspaces: store.makeState()))

        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        state.encode(with: archiver)
        archiver.finishEncoding()

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        #expect(unarchiver.decodeInteger(forKey: DummyTerminalRestorableState.versionKey) == TerminalRestorableState.version)

        let restored = try #require(DummyTerminalRestorableState(coder: unarchiver))
        let workspaces = try #require(restored.internalState.workspaces)
        #expect(workspaces.selectedWorkspace == docs.id.uuidString)
        #expect(workspaces.workspaces.map(\.name) == ["Default", "Docs"])
        #expect(workspaces.workspaces[1].tabs[0].titleOverride == "writing")
        #expect(workspaces.workspaces[1].tabs[0].surfaceTree.map(\.id) == tree.map(\.id))
        #expect(restored.internalState.surfaceTree.isEmpty)
        #expect(restored.internalState.restoredSurfaceTree.map(\.id) == tree.map(\.id))
    }

    @MainActor
    @Test func coderWithoutSavedStateDecodesToNothing() throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode("unrelated", forKey: "other")
        archiver.finishEncoding()

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        #expect(unarchiver.decodeInteger(forKey: DummyQuickTerminalRestorableState.versionKey) == 0)
        #expect(DummyQuickTerminalRestorableState(coder: unarchiver) == nil)
        #expect(DummyTerminalRestorableState(coder: unarchiver) == nil)
    }

    @MainActor
    @Test func archiveWithoutWorkspacesKeepsSurfaceTree() throws {
        let views = [CountingView(), CountingView()]
        let tab = Self.makeCountingTab(views)
        let state = TerminalRestorableState.InternalState<CountingView>(
            focusedSurface: nil,
            surfaceTree: tab.tree,
            effectiveFullscreenMode: nil,
            tabColor: nil,
            titleOverride: nil,
            workspaces: nil)
        let data = try JSONEncoder().encode(state)

        let decoded = try JSONDecoder().decode(TerminalRestorableState.InternalState<CountingView>.self, from: data)
        #expect(decoded.surfaceTree.map(\.id) == views.map(\.id))
        #expect(decoded.restoredSurfaceTree.map(\.id) == views.map(\.id))
    }

    @MainActor
    private static func makeCountingTab(_ views: [CountingView]) -> WorkspaceTab<CountingView> {
        var tree = SplitTree<CountingView>(view: views[0])
        for view in views.dropFirst() {
            guard let inserted = try? tree.inserting(view: view, at: views[0], direction: .right) else {
                preconditionFailure("failed to build test tree")
            }
            tree = inserted
        }
        guard let tab = WorkspaceTab<CountingView>(tree: tree) else {
            preconditionFailure("failed to build test tab")
        }
        return tab
    }
}

final class CountingView: NSView, Codable, Identifiable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var decoded: [UUID] = []

    static var decodedIDs: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return decoded
    }

    static func resetDecodes() {
        lock.lock()
        decoded = []
        lock.unlock()
    }

    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    enum CodingKeys: CodingKey { case id }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        super.init(frame: .zero)
        Self.lock.lock()
        Self.decoded.append(id)
        Self.lock.unlock()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }
}

private extension TerminalRestorableTests {
    func archive<T: NSObject & NSSecureCoding>(_ obj: T, className: String?) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        defer { archiver.finishEncoding() }
        if let className {
            archiver.setClassName(className, for: T.self)
        }
        archiver.encode(obj, forKey: NSKeyedArchiveRootObjectKey)
        return archiver.encodedData
    }

    func unarchive<T: NSObject & NSSecureCoding>(_ data: Data, className: String?, as: T.Type = T.self) throws -> T {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        defer { unarchiver.finishDecoding()}
        if let className {
            unarchiver.setClass(T.self, forClassName: className)
        }
        unarchiver.requiresSecureCoding = true
        let result = unarchiver.decodeObject(of: T.self, forKey: NSKeyedArchiveRootObjectKey)
        return try #require(result)
    }
}

// MARK: - Dummy States

@MainActor
private final class DummyTerminalRestorableState: TerminalRestorable {
    static var version: Int {
        TerminalRestorableState.version
    }

    static var minimumVersion: Int {
        TerminalRestorableState.minimumVersion
    }

    required init(copy other: DummyTerminalRestorableState) {
        internalState = other.internalState
    }

    let internalState: TerminalRestorableState.InternalState<MockView>

    init(_ internalState: TerminalRestorableState.InternalState<MockView>) {
        self.internalState = internalState
    }

    required init(from decoder: any Decoder) throws {
        self.internalState = try TerminalRestorableState.InternalState<MockView>(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try internalState.encode(to: encoder)
    }
}

@MainActor
struct DummyQuickTerminalRestorableState: TerminalRestorable {
    static var version: Int = QuickTerminalRestorableState.version

    static var minimumVersion: Int = QuickTerminalRestorableState.minimumVersion

    init(copy other: DummyQuickTerminalRestorableState) {
        internalState = other.internalState
    }

    let internalState: QuickTerminalRestorableState.InternalState<MockView>

    init(_ internalState: QuickTerminalRestorableState.InternalState<MockView>) {
        self.internalState = internalState
    }

    init(from decoder: any Decoder) throws {
        self.internalState = try QuickTerminalRestorableState.InternalState<MockView>(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try internalState.encode(to: encoder)
    }
}

// MARK: - QuickTerminal V1 (1.3.0)

private let v1QTData = Data(base64Encoded: """
    YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGkCwwRElUkbnVsbNINDg8QVGRhdGFWJGNsYXNzgAKAA08RA6hicGxpc3QwMNQBAgMEBQYHClgkdmVyc2lvblkkYXJjaGl2ZXJUJHRvcFgkb2JqZWN0cxIAAYagXxAPTlNLZXllZEFyY2hpdmVy0QgJVXZhbHVlgAGvECALDBkaGxwfJicvMDEyODlFRkdISU9QVldYXF1jaWpwcVUkbnVsbNMNDg8QFBhXTlMua2V5c1pOUy5vYmplY3RzViRjbGFzc6MREhOAAoADgASjFRYXgAWAB4AIgBhfEBJzY3JlZW5TdGF0ZUVudHJpZXNeZm9jdXNlZFN1cmZhY2Vbc3VyZmFjZVRyZWXSDg8dHqCABtIgISIjWiRjbGFzc25hbWVYJGNsYXNzZXNeTlNNdXRhYmxlQXJyYXmjIiQlV05TQXJyYXlYTlNPYmplY3RTMTIz0w0ODygrGKIpKoAJgAqiLC2AC4AMgBhXdmVyc2lvblRyb290EAHTDQ4PMzUYoTSADaE2gA6AGFVzcGxpdNMNDg86PxikOzw9PoAPgBCAEYASpEBBQkOAE4AZgBqAHYAYVXJpZ2h0VXJhdGlvVGxlZnRZZGlyZWN0aW9u0w0OD0pMGKFLgBShTYAVgBhUdmlld9MNDg9RUxihUoAWoVSAF4AYUmlkXxAkOTk0QzY3M0YtQjRDNS00OUVFLUIwNDQtNjUwMDY2NTI2MzZE0iAhWVpfEBNOU011dGFibGVEaWN0aW9uYXJ5o1lbJVxOU0RpY3Rpb25hcnkjP+AAAAAAAADTDQ4PXmAYoUuAFKFhgBuAGNMNDg9kZhihUoAWoWeAHIAYXxAkMkYyRjJEOTMtOTQ0Qy00NzRBLTgzQkEtNERDMTg2OEMzRUI50w0OD2ttGKFsgB6hboAfgBhaaG9yaXpvbnRhbNMNDg9ycxigoIAYAAgAEQAaACQAKQAyADcASQBMAFIAVAB3AH0AhACMAJcAngCiAKQApgCoAKwArgCwALIAtADJANgA5ADpAOoA7ADxAPwBBQEUARgBIAEpAS0BNAE3ATkBOwE+AUABQgFEAUwBUQFTAVoBXAFeAWABYgFkAWoBcQF2AXgBegF8AX4BgwGFAYcBiQGLAY0BkwGZAZ4BqAGvAbEBswG1AbcBuQG+AcUBxwHJAcsBzQHPAdIB+QH+AhQCGAIlAi4CNQI3AjkCOwI9Aj8CRgJIAkoCTAJOAlACdwJ+AoACggKEAoYCiAKTApoCmwKcAAAAAAAAAgEAAAAAAAAAdQAAAAAAAAAAAAAAAAAAAp7RExRaJGNsYXNzbmFtZV8QHENvZGFibGVCcmlkZ2U8UXVpY2tUZXJtaW5hbD4ACAARABoAJAApADIANwBJAEwAUQBTAFgAXgBjAGgAbwBxAHMEHwQiBC0AAAAAAAACAQAAAAAAAAAVAAAAAAAAAAAAAAAAAAAETA==
    """)!

// MARK: - Terminal V5 (1.2.3)

private let v5Data = Data(base64Encoded: """
    YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGkCwwRElUkbnVsbNINDg8QVGRhdGFWJGNsYXNzgAKAA08RA01icGxpc3QwMNQBAgMEBQYHClgkdmVyc2lvblkkYXJjaGl2ZXJUJHRvcFgkb2JqZWN0cxIAAYagXxAPTlNLZXllZEFyY2hpdmVy0QgJVXZhbHVlgAGvEB0LDBcYGRoiIyQlKyw4OTo7PEJDSUpLUlNZX2BmZ1UkbnVsbNMNDg8QExZXTlMua2V5c1pOUy5vYmplY3RzViRjbGFzc6IREoACgAOiFBWABIAFgBVeZm9jdXNlZFN1cmZhY2Vbc3VyZmFjZVRyZWVSdjXTDQ4PGx4WohwdgAaAB6IfIIAIgAmAFVd2ZXJzaW9uVHJvb3QQAdMNDg8mKBahJ4AKoSmAC4AVVXNwbGl00w0ODy0yFqQuLzAxgAyADYAOgA+kMzQ1NoAQgBaAF4AagBVVcmlnaHRVcmF0aW9UbGVmdFlkaXJlY3Rpb27TDQ4PPT8WoT6AEaFAgBKAFVR2aWV30w0OD0RGFqFFgBOhR4AUgBVSaWRfECRBQzVFODI5Qi04NUZELTRDNjktQjE5Ni0yRUU0NjlDNzJBOTDSTE1OT1okY2xhc3NuYW1lWCRjbGFzc2VzXxATTlNNdXRhYmxlRGljdGlvbmFyeaNOUFFcTlNEaWN0aW9uYXJ5WE5TT2JqZWN0Iz/gAAAAAAAA0w0OD1RWFqE+gBGhV4AYgBXTDQ4PWlwWoUWAE6FdgBmAFV8QJDkyNkYzRjJBLTgyNEMtNDBDOS04N0NBLTJDRENBNEUxMTA0OdMNDg9hYxahYoAboWSAHIAVWmhvcml6b250YWzTDQ4PaGkWoKCAFQAIABEAGgAkACkAMgA3AEkATABSAFQAdAB6AIEAiQCUAJsAngCgAKIApQCnAKkAqwC6AMYAyQDQANMA1QDXANoA3ADeAOAA6ADtAO8A9gD4APoA/AD+AQABBgENARIBFAEWARgBGgEfASEBIwElAScBKQEvATUBOgFEAUsBTQFPAVEBUwFVAVoBYQFjAWUBZwFpAWsBbgGVAZoBpQGuAcQByAHVAd4B5wHuAfAB8gH0AfYB+AH/AgECAwIFAgcCCQIwAjcCOQI7Aj0CPwJBAkwCUwJUAlUAAAAAAAACAQAAAAAAAABrAAAAAAAAAAAAAAAAAAACV9ETFFokY2xhc3NuYW1lXxAXQ29kYWJsZUJyaWRnZTxUZXJtaW5hbD4ACAARABoAJAApADIANwBJAEwAUQBTAFgAXgBjAGgAbwBxAHMDxAPHA9IAAAAAAAACAQAAAAAAAAAVAAAAAAAAAAAAAAAAAAAD7A==
    """)!

// MARK: - Terminal V7 (1.3.0)

private let v7Data = Data(base64Encoded: """
    YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGkCwwRElUkbnVsbNINDg8QVGRhdGFWJGNsYXNzgAKAA08RA71icGxpc3QwMNQBAgMEBQYHClgkdmVyc2lvblkkYXJjaGl2ZXJUJHRvcFgkb2JqZWN0cxIAAYagXxAPTlNLZXllZEFyY2hpdmVy0QgJVXZhbHVlgAGvECMLDB0eHyAhIiMkLC0uLzU2QkNERUZMTVNUVVxdY2lqcHF1dlUkbnVsbNMNDg8QFhxXTlMua2V5c1pOUy5vYmplY3RzViRjbGFzc6UREhMUFYACgAOABIAFgAalFxgZGhuAB4AIgAmAIYAigBlfEBdlZmZlY3RpdmVGdWxsc2NyZWVuTW9kZV5mb2N1c2VkU3VyZmFjZVtzdXJmYWNlVHJlZVh0YWJDb2xvcl10aXRsZU92ZXJyaWRlVm5hdGl2ZVJ2N9MNDg8lKByiJieACoALoikqgAyADYAZV3ZlcnNpb25Ucm9vdBAB0w0ODzAyHKExgA6hM4APgBlVc3BsaXTTDQ4PNzwcpDg5OjuAEIARgBKAE6Q9Pj9AgBSAGoAbgB6AGVVyaWdodFVyYXRpb1RsZWZ0WWRpcmVjdGlvbtMNDg9HSRyhSIAVoUqAFoAZVHZpZXfTDQ4PTlAcoU+AF6FRgBiAGVJpZF8QJDk2RUExMTg5LTc0ODItNDFCQy1BNkNELTI2RTUxOTBFNEJGQdJWV1hZWiRjbGFzc25hbWVYJGNsYXNzZXNfEBNOU011dGFibGVEaWN0aW9uYXJ5o1haW1xOU0RpY3Rpb25hcnlYTlNPYmplY3QjP+AAAAAAAADTDQ4PXmAcoUiAFaFhgByAGdMNDg9kZhyhT4AXoWeAHYAZXxAkNUQ1ODBBN0EtODFFQS00N0M2LUJCOUEtQUQ0QjE3ODNFNDc40w0OD2ttHKFsgB+hboAggBlaaG9yaXpvbnRhbNMNDg9ycxygoIAZEAdVMS4zLjAACAARABoAJAApADIANwBJAEwAUgBUAHoAgACHAI8AmgChAKcAqQCrAK0ArwCxALcAuQC7AL0AvwDBAMMA3QDsAPgBAQEPARYBGQEgASMBJQEnASoBLAEuATABOAE9AT8BRgFIAUoBTAFOAVABVgFdAWIBZAFmAWgBagFvAXEBcwF1AXcBeQF/AYUBigGUAZsBnQGfAaEBowGlAaoBsQGzAbUBtwG5AbsBvgHlAeoB9QH+AhQCGAIlAi4CNwI+AkACQgJEAkYCSAJPAlECUwJVAlcCWQKAAocCiQKLAo0CjwKRApwCowKkAqUCpwKpAAAAAAAAAgEAAAAAAAAAdwAAAAAAAAAAAAAAAAAAAq/RExRaJGNsYXNzbmFtZV8QF0NvZGFibGVCcmlkZ2U8VGVybWluYWw+AAgAEQAaACQAKQAyADcASQBMAFEAUwBYAF4AYwBoAG8AcQBzBDQENwRCAAAAAAAAAgEAAAAAAAAAFQAAAAAAAAAAAAAAAAAABFw=
    """)!

// MARK: - Terminal V7 Generic (tip)

private let v7GenericData = Data(base64Encoded: """
    YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGkCwwRElUkbnVsbNINDg8QVGRhdGFWJGNsYXNzgAKAA08RA8NicGxpc3QwMNQBAgMEBQYHClgkdmVyc2lvblkkYXJjaGl2ZXJUJHRvcFgkb2JqZWN0cxIAAYagXxAPTlNLZXllZEFyY2hpdmVy0QgJVXZhbHVlgAGvECMLDB0eHyAhIiMkLC0uLzU2QkNERUZMTVNUVVxdY2lqcHF1dlUkbnVsbNMNDg8QFhxXTlMua2V5c1pOUy5vYmplY3RzViRjbGFzc6UREhMUFYACgAOABIAFgAalFxgZGhuAB4AIgAmAIYAigBlfEBdlZmZlY3RpdmVGdWxsc2NyZWVuTW9kZV5mb2N1c2VkU3VyZmFjZVtzdXJmYWNlVHJlZVh0YWJDb2xvcl10aXRsZU92ZXJyaWRlVm5hdGl2ZVp2NyBnZW5lcmlj0w0ODyUoHKImJ4AKgAuiKSqADIANgBlXdmVyc2lvblRyb290EAHTDQ4PMDIcoTGADqEzgA+AGVVzcGxpdNMNDg83PBykODk6O4AQgBGAEoATpD0+P0CAFIAagBuAHoAZVXJpZ2h0VXJhdGlvVGxlZnRZZGlyZWN0aW9u0w0OD0dJHKFIgBWhSoAWgBlUdmlld9MNDg9OUByhT4AXoVGAGIAZUmlkXxAkRDMyMjM1NjktMkUwMS00QkM1LTlEQjItREJGQzNBRkY0NkQx0lZXWFlaJGNsYXNzbmFtZVgkY2xhc3Nlc18QE05TTXV0YWJsZURpY3Rpb25hcnmjWFpbXE5TRGljdGlvbmFyeVhOU09iamVjdCM/4AAAAAAAANMNDg9eYByhSIAVoWGAHIAZ0w0OD2RmHKFPgBehZ4AdgBlfECQ5NTNDRTk1Mi1EOTFELTREMzYtQUM3Mi05RDBGMUY2QkNFNzPTDQ4Pa20coWyAH6FugCCAGVpob3Jpem9udGFs0w0OD3JzHKCggBkQB1N0aXAACAARABoAJAApADIANwBJAEwAUgBUAHoAgACHAI8AmgChAKcAqQCrAK0ArwCxALcAuQC7AL0AvwDBAMMA3QDsAPgBAQEPARYBIQEoASsBLQEvATIBNAE2ATgBQAFFAUcBTgFQAVIBVAFWAVgBXgFlAWoBbAFuAXABcgF3AXkBewF9AX8BgQGHAY0BkgGcAaMBpQGnAakBqwGtAbIBuQG7Ab0BvwHBAcMBxgHtAfIB/QIGAhwCIAItAjYCPwJGAkgCSgJMAk4CUAJXAlkCWwJdAl8CYQKIAo8CkQKTApUClwKZAqQCqwKsAq0CrwKxAAAAAAAAAgEAAAAAAAAAdwAAAAAAAAAAAAAAAAAAArXRExRaJGNsYXNzbmFtZV8QF0NvZGFibGVCcmlkZ2U8VGVybWluYWw+AAgAEQAaACQAKQAyADcASQBMAFEAUwBYAF4AYwBoAG8AcQBzBDoEPQRIAAAAAAAAAgEAAAAAAAAAFQAAAAAAAAAAAAAAAAAABGI=
    """)!
