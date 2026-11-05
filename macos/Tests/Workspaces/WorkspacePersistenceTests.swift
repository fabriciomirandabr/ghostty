import AppKit
import Testing
@testable import Ghostty

private final class Owner {}

private final class FailingWriter {
    var failuresLeft: Int

    init(failures: Int) {
        failuresLeft = failures
    }

    func write(_ data: Data, to url: URL) throws {
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
struct WorkspacePersistenceTests {
    private func makePersistence(
        debounce: TimeInterval = 60,
        writer: FailingWriter? = nil
    ) -> WorkspacePersistence {
        let url = WorkspaceStateStoreTests.makeTemporaryFileURL()
        let store: WorkspaceStateStore
        if let writer {
            store = WorkspaceStateStore(fileURL: url, debounceInterval: debounce) { try writer.write($0, to: $1) }
        } else {
            store = WorkspaceStateStore(fileURL: url, debounceInterval: debounce)
        }
        return WorkspacePersistence(store: store)
    }

    private func makeState(name: String = "Docs") throws -> WorkspacePersistedState {
        let (store, view) = try WorkspaceStateStoreTests.makePopulatedStore()
        var state = WorkspaceStateStoreTests.makePersisted(from: store, pwdOf: view)
        state.workspaces[1].name = name
        return state
    }

    @Test func aWindowClaimsPrimaryOnlyWhenAloneOrRestored() {
        let persistence = makePersistence()
        let alone = Owner()
        let second = Owner()
        let restored = Owner()

        #expect(persistence.primaryWindow == nil)
        #expect(persistence.register(alone, origin: .fresh))
        #expect(!persistence.register(second, origin: .fresh))
        #expect(!persistence.register(restored, origin: .restoredWorkspaces))
        #expect(persistence.isPrimary(alone))
        #expect(!persistence.isPrimary(second))
        #expect(!persistence.isPrimary(restored))

        withExtendedLifetime((alone, second, restored)) {}
    }

    @Test func aRestoredWindowClaimsEvenWhenOthersExistWithoutAPrimary() {
        let persistence = makePersistence()
        let legacy = Owner()
        let restored = Owner()

        #expect(!persistence.register(legacy, origin: .restoredWithoutWorkspaces))
        #expect(persistence.primaryWindow == nil)
        #expect(persistence.register(restored, origin: .restoredWorkspaces))
        #expect(persistence.isPrimary(restored))

        withExtendedLifetime((legacy, restored)) {}
    }

    @Test func aWindowRestoredWithoutWorkspacesNeverClaims() throws {
        let persistence = makePersistence()
        let legacy = Owner()
        let later = Owner()
        let state = try makeState()
        try persistence.store.save(state)

        #expect(!persistence.register(legacy, origin: .restoredWithoutWorkspaces))
        #expect(persistence.primaryWindow == nil)
        #expect(persistence.hasWindows)
        #expect(persistence.loadForNewWindow(enabled: true) == nil)
        #expect(!persistence.register(later, origin: .fresh))

        persistence.flush(try makeState(name: "Legacy"), from: legacy, enabled: true)
        persistence.flush(try makeState(name: "Later"), from: later, enabled: true)
        #expect(try persistence.store.load() == state)

        persistence.unregister(later)
        #expect(persistence.primaryWindow == nil)
        persistence.stateDidChange(try makeState(name: "Legacy"), from: legacy, enabled: true)
        persistence.flush(try makeState(name: "Legacy"), from: legacy, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        #expect(try persistence.store.load() == state)

        withExtendedLifetime((legacy, later)) {}
    }

    @Test func aWindowThatCouldNeverClaimNeverInheritsWhenAnotherWindowCloses() throws {
        let persistence = makePersistence()
        let legacy = Owner()
        let fresh = Owner()
        let state = try makeState()
        try persistence.store.save(state)
        persistence.register(legacy, origin: .restoredWithoutWorkspaces)
        persistence.register(fresh, origin: .fresh)

        persistence.unregister(fresh)
        #expect(persistence.primaryWindow == nil)
        persistence.flush(try makeState(name: "Legacy"), from: legacy, enabled: true)
        #expect(try persistence.store.load() == state)
        persistence.unregister(legacy)

        let secondLegacy = Owner()
        let secondFresh = Owner()
        persistence.register(secondLegacy, origin: .restoredWithoutWorkspaces)
        persistence.register(secondFresh, origin: .fresh)
        persistence.unregister(secondLegacy)
        #expect(persistence.primaryWindow == nil)
        persistence.flush(try makeState(name: "Fresh"), from: secondFresh, enabled: true)
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == state)

        withExtendedLifetime((legacy, fresh, secondLegacy, secondFresh)) {}
    }

    @Test func aRestoredWindowThatSharesNoWorkspaceWithTheFileNeverClaims() throws {
        let persistence = makePersistence()
        let fileState = try makeState(name: "A")
        try persistence.store.save(fileState)
        let writes = persistence.store.writeCount
        let windowB = Owner()
        let windowA = Owner()
        let stateB = try makeState(name: "B")

        #expect(!persistence.register(windowB, origin: .restoredWorkspaces, state: stateB))
        persistence.stateDidChange(try makeState(name: "B changed"), from: windowB, enabled: true)
        #expect(!persistence.store.hasPendingSave)

        #expect(persistence.register(windowA, origin: .restoredWorkspaces, state: fileState))
        #expect(persistence.isPrimary(windowA))
        #expect(!persistence.isPrimary(windowB))

        persistence.stateDidChange(fileState, from: windowA, enabled: true)
        persistence.flush(stateB, from: windowB, enabled: true)
        persistence.flush(fileState, from: windowA, enabled: true)
        persistence.unregister(windowA)
        #expect(persistence.primaryWindow == nil)
        persistence.flush(stateB, from: windowB, enabled: true)
        #expect(persistence.store.writeCount == writes)
        #expect(try persistence.store.load() == fileState)

        withExtendedLifetime((windowA, windowB)) {}
    }

    @Test func aRestoredWindowThatChangedWithinTheLastSecondStillMatchesTheFile() throws {
        let persistence = makePersistence()
        let fileState = try makeState(name: "A")
        try persistence.store.save(fileState)
        var edited = fileState
        edited.workspaces[1].name = "A edited"
        var added = fileState.workspaces[0]
        added.id = UUID().uuidString
        edited.workspaces.append(added)
        let owner = Owner()

        #expect(persistence.register(owner, origin: .restoredWorkspaces, state: edited))
        withExtendedLifetime(owner) {}
    }

    @Test func aRestoredWindowThatDoesNotMatchTheFileNeverInheritsTheRole() throws {
        let persistence = makePersistence()
        let fileState = try makeState(name: "A")
        try persistence.store.save(fileState)
        let windowA = Owner()
        let windowB = Owner()

        #expect(persistence.register(windowA, origin: .restoredWorkspaces, state: fileState))
        #expect(!persistence.register(windowB, origin: .restoredWorkspaces, state: try makeState(name: "B")))
        persistence.unregister(windowA)
        #expect(persistence.primaryWindow == nil)
        persistence.flush(try makeState(name: "B"), from: windowB, enabled: true)
        #expect(try persistence.store.load() == fileState)

        withExtendedLifetime((windowA, windowB)) {}
    }

    @Test func withoutAReadableFileOnlyTheFirstRestoredWindowMayInherit() throws {
        let persistence = makePersistence()
        let first = Owner()
        let second = Owner()

        #expect(persistence.register(first, origin: .restoredWorkspaces, state: try makeState(name: "One")))
        #expect(!persistence.register(second, origin: .restoredWorkspaces, state: try makeState(name: "Two")))
        persistence.unregister(first)
        #expect(persistence.primaryWindow == nil)

        withExtendedLifetime((first, second)) {}
    }

    @Test func theLaunchFileDecidesTheMatchEvenAfterTheFileWasOverwritten() throws {
        let persistence = makePersistence()
        let fileState = try makeState(name: "A")
        try persistence.store.save(fileState)
        let writes = persistence.store.writeCount
        let windowB = Owner()
        let windowA = Owner()
        let scratch = try makeState(name: "B")

        #expect(!persistence.register(windowB, origin: .restoredWorkspaces, state: scratch))
        try persistence.store.save(scratch)

        #expect(persistence.register(windowA, origin: .restoredWorkspaces, state: fileState))
        #expect(persistence.isPrimary(windowA))
        #expect(persistence.store.writeCount == writes + 1)

        withExtendedLifetime((windowA, windowB)) {}
    }

    @Test func withoutAReadableFileTheFirstRestoredWindowClaims() throws {
        let persistence = makePersistence()
        let first = Owner()
        let second = Owner()

        #expect(persistence.register(first, origin: .restoredWorkspaces, state: try makeState(name: "One")))
        #expect(!persistence.register(second, origin: .restoredWorkspaces, state: try makeState(name: "Two")))
        #expect(persistence.isPrimary(first))

        withExtendedLifetime((first, second)) {}
    }

    @Test func launchRecoveryOffersTheFileWhenNoRestoredWindowMatchesIt() throws {
        let persistence = makePersistence()
        let fileState = try makeState(name: "A")
        try persistence.store.save(fileState)
        let writes = persistence.store.writeCount
        let windowB = Owner()
        let windowC = Owner()
        let recovered = Owner()

        persistence.register(windowB, origin: .restoredWorkspaces, state: try makeState(name: "B"))
        persistence.register(windowC, origin: .restoredWorkspaces, state: try makeState(name: "C"))
        #expect(persistence.primaryWindow == nil)
        #expect(persistence.loadForRecovery(enabled: false) == nil)
        #expect(persistence.loadForRecovery(enabled: true) == fileState)

        #expect(persistence.register(recovered, origin: .restoredWorkspaces, state: fileState))
        #expect(persistence.isPrimary(recovered))
        persistence.stateDidChange(fileState, from: recovered, enabled: true)
        persistence.flush(fileState, from: recovered, enabled: true)
        persistence.flush(try makeState(name: "B"), from: windowB, enabled: true)
        #expect(persistence.store.writeCount == writes)
        #expect(try persistence.store.load() == fileState)
        #expect(persistence.loadForRecovery(enabled: true) == nil)

        persistence.unregister(recovered)
        #expect(persistence.primaryWindow == nil)

        withExtendedLifetime((windowB, windowC, recovered)) {}
    }

    @Test func launchRecoveryNeverRunsWithoutAFileOrWhenAMatchingWindowIsPrimary() throws {
        let persistence = makePersistence()
        let scratch = Owner()
        persistence.register(scratch, origin: .restoredWorkspaces, state: try makeState(name: "B"))
        #expect(persistence.loadForRecovery(enabled: true) == nil)

        let fileState = try makeState(name: "A")
        try persistence.store.save(fileState)
        let matching = Owner()
        let other = Owner()
        persistence.unregister(scratch)
        persistence.register(other, origin: .restoredWorkspaces, state: try makeState(name: "B"))
        persistence.register(matching, origin: .restoredWorkspaces, state: fileState)
        #expect(persistence.isPrimary(matching))
        #expect(persistence.loadForRecovery(enabled: true) == nil)

        withExtendedLifetime((scratch, matching, other)) {}
    }

    @Test func aNewerFileIsNotReplacedByTheFirstChangeOfARestoredWindow() throws {
        let persistence = makePersistence()
        var newer = try makeState(name: "From the future")
        newer.version = WorkspacePersistedState.currentVersion + 1
        try persistence.store.save(newer)
        let owner = Owner()
        let restored = try makeState(name: "Restored")

        #expect(persistence.register(owner, origin: .restoredWorkspaces, state: restored))
        persistence.stateDidChange(restored, from: owner, enabled: true)
        for report in 1...3 {
            var reported = restored
            reported.workspaces[0].tabs[0].directory = "/tmp/pwd-report-\(report)"
            persistence.stateDidChange(reported, from: owner, enabled: true)
            #expect(!persistence.store.hasPendingSave)
            persistence.flush(reported, from: owner, enabled: true)
        }
        #expect(throws: WorkspaceStateStoreError.newerVersion(newer.version)) {
            try persistence.store.load()
        }

        var renamed = restored
        renamed.workspaces[1].name = "Renamed"
        persistence.stateDidChange(renamed, from: owner, enabled: true)
        #expect(persistence.store.hasPendingSave)
        persistence.flush(renamed, from: owner, enabled: true)
        #expect(try persistence.store.load() == renamed)

        withExtendedLifetime(owner) {}
    }

    @Test func aFreshWindowKeepsANewerFileThroughDirectoryReportsToo() throws {
        let persistence = makePersistence()
        var newer = try makeState(name: "From the future")
        newer.version = WorkspacePersistedState.currentVersion + 1
        try persistence.store.save(newer)
        let owner = Owner()
        let first = try makeState(name: "First")

        #expect(persistence.loadForNewWindow(enabled: true) == nil)
        #expect(persistence.register(owner, origin: .fresh))
        persistence.stateDidChange(first, from: owner, enabled: true)
        var reported = first
        reported.workspaces[0].tabs[0].directory = "/tmp/pwd-report"
        persistence.stateDidChange(reported, from: owner, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        persistence.flush(reported, from: owner, enabled: true)
        #expect(persistence.store.writeCount == 1)

        reported.workspaces[0].tabs[0].titleOverride = "Build"
        persistence.stateDidChange(reported, from: owner, enabled: true)
        #expect(persistence.store.hasPendingSave)

        withExtendedLifetime(owner) {}
    }

    @Test func aNewerFileSurvivesAFreshWindowReplacingAClosedPrimary() throws {
        let persistence = makePersistence()
        var newer = try makeState(name: "From the future")
        newer.version = WorkspacePersistedState.currentVersion + 1
        try persistence.store.save(newer)
        let windowA = Owner()
        let windowC = Owner()
        let stateA = try makeState(name: "A")
        let stateC = try makeState(name: "C")

        #expect(persistence.loadForNewWindow(enabled: true) == nil)
        #expect(persistence.register(windowA, origin: .fresh))
        persistence.stateDidChange(stateA, from: windowA, enabled: true)
        var reportedA = stateA
        reportedA.workspaces[0].tabs[0].directory = "/tmp/pwd-report"
        persistence.stateDidChange(reportedA, from: windowA, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        persistence.unregister(windowA)

        #expect(persistence.register(windowC, origin: .fresh))
        persistence.stateDidChange(stateC, from: windowC, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        persistence.flush(stateC, from: windowC, enabled: true)
        #expect(persistence.store.writeCount == 1)
        #expect(throws: WorkspaceStateStoreError.newerVersion(newer.version)) {
            try persistence.store.load()
        }

        var renamed = stateC
        renamed.workspaces[1].name = "Renamed"
        persistence.stateDidChange(renamed, from: windowC, enabled: true)
        #expect(persistence.store.hasPendingSave)

        withExtendedLifetime((windowA, windowC)) {}
    }

    @Test func aRestoredWindowWithoutAReadableFileWritesItsBaselineRightAway() throws {
        let persistence = makePersistence()
        let owner = Owner()
        let restored = try makeState(name: "Restored")

        #expect(persistence.register(owner, origin: .restoredWorkspaces, state: restored))
        #expect(persistence.store.hasPendingSave)
        persistence.flush(restored, from: owner, enabled: true)
        #expect(try persistence.store.load() == restored)
        #expect(persistence.store.writeCount == 1)

        withExtendedLifetime(owner) {}
    }

    @Test func aRestoredWindowDoesNotReplaceANewerFileWithItsBaseline() throws {
        let persistence = makePersistence()
        var newer = try makeState(name: "From the future")
        newer.version = WorkspacePersistedState.currentVersion + 1
        try persistence.store.save(newer)
        let owner = Owner()

        #expect(persistence.register(owner, origin: .restoredWorkspaces, state: try makeState(name: "Restored")))
        #expect(!persistence.store.hasPendingSave)

        withExtendedLifetime(owner) {}
    }

    @Test func aRestoredWindowDoesNotWriteUntilItChangesSomething() throws {
        let persistence = makePersistence()
        let file = try makeState(name: "File")
        try persistence.store.save(file)
        let writes = persistence.store.writeCount
        let owner = Owner()
        var restored = file
        restored.workspaces[1].name = "Restored"

        #expect(persistence.register(owner, origin: .restoredWorkspaces, state: restored))
        persistence.stateDidChange(restored, from: owner, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        persistence.flush(restored, from: owner, enabled: true)
        #expect(persistence.store.writeCount == writes)

        let changed = try makeState(name: "Changed")
        persistence.stateDidChange(changed, from: owner, enabled: true)
        #expect(persistence.store.hasPendingSave)
        persistence.flush(changed, from: owner, enabled: true)
        #expect(try persistence.store.load() == changed)

        withExtendedLifetime(owner) {}
    }

    @Test func goingBackToThePersistedStateDropsThePendingWrite() throws {
        let persistence = makePersistence()
        let owner = Owner()
        persistence.register(owner, origin: .fresh)
        let original = try makeState(name: "S0")
        let intermediate = try makeState(name: "S1")
        persistence.flush(original, from: owner, enabled: true)

        persistence.stateDidChange(intermediate, from: owner, enabled: true)
        #expect(persistence.store.hasPendingSave)
        persistence.stateDidChange(original, from: owner, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        persistence.flush(original, from: owner, enabled: true)
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == original)
    }

    @Test func aFlushWithThePersistedStateDropsAStalePendingWrite() throws {
        let persistence = makePersistence()
        let owner = Owner()
        persistence.register(owner, origin: .fresh)
        let original = try makeState(name: "S0")
        persistence.flush(original, from: owner, enabled: true)

        persistence.stateDidChange(try makeState(name: "S1"), from: owner, enabled: true)
        persistence.flush(original, from: owner, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == original)
    }

    @Test func theTimerWritesNothingAfterTheStateWentBack() async throws {
        let persistence = makePersistence(debounce: 0.05)
        let owner = Owner()
        persistence.register(owner, origin: .fresh)
        let original = try makeState(name: "S0")
        persistence.flush(original, from: owner, enabled: true)

        persistence.stateDidChange(try makeState(name: "S1"), from: owner, enabled: true)
        persistence.stateDidChange(original, from: owner, enabled: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == original)
    }

    @Test func aSecondWindowNeverSavesNorDeletes() throws {
        let persistence = makePersistence()
        let first = Owner()
        let second = Owner()
        persistence.register(first, origin: .fresh)
        persistence.register(second, origin: .fresh)
        let state = try makeState()

        persistence.stateDidChange(state, from: second, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        persistence.flush(state, from: second, enabled: true)
        #expect(persistence.store.writeCount == 0)
        #expect(try persistence.store.load() == nil)

        persistence.flush(state, from: first, enabled: true)
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == state)

        persistence.flush(state, from: second, enabled: false)
        #expect(try persistence.store.load() == state)

        persistence.flush(state, from: first, enabled: false)
        #expect(try persistence.store.load() == nil)
    }

    @Test func closingThePrimaryHandsTheRoleToTheOldestWindowAndAFreshWindowNeverOverwrites() throws {
        let persistence = makePersistence()
        let windowA = Owner()
        let windowB = Owner()
        let windowC = Owner()
        let stateA = try makeState(name: "A")
        let stateB = try makeState(name: "B")
        let stateC = try makeState(name: "C")

        persistence.register(windowA, origin: .fresh)
        persistence.register(windowB, origin: .fresh)
        persistence.flush(stateA, from: windowA, enabled: true)
        persistence.unregister(windowA)
        #expect(persistence.primaryWindow == nil)
        #expect(!persistence.isPrimary(windowB))

        #expect(persistence.loadForNewWindow(enabled: true) == nil)
        #expect(!persistence.register(windowC, origin: .fresh))
        persistence.stateDidChange(stateC, from: windowC, enabled: true)
        persistence.flush(stateC, from: windowC, enabled: true)
        persistence.stateDidChange(stateB, from: windowB, enabled: true)
        persistence.flush(stateB, from: windowB, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == stateA)

        persistence.unregister(windowB)
        persistence.unregister(windowC)
        #expect(!persistence.hasWindows)
        #expect(persistence.loadForNewWindow(enabled: true) == stateA)
    }

    @Test func closingTheWindowsInAnyOrderKeepsThePrimaryWindowsProjects() throws {
        let stateA = try makeState(name: "A")
        let stateB = try makeState(name: "B")

        for closeOrder in [["A", "B"], ["B", "A"]] {
            let persistence = makePersistence()
            let windowA = Owner()
            let windowB = Owner()
            let windows = ["A": windowA, "B": windowB]
            persistence.register(windowA, origin: .fresh)
            persistence.register(windowB, origin: .fresh)
            persistence.flush(stateA, from: windowA, enabled: true)

            for name in closeOrder {
                let window = try #require(windows[name])
                persistence.flush(name == "A" ? stateA : stateB, from: window, enabled: true)
                persistence.unregister(window)
            }

            #expect(persistence.store.writeCount == 1)
            #expect(try persistence.store.load() == stateA)
            #expect(persistence.loadForNewWindow(enabled: true) == stateA)
        }
    }

    @Test func theRoleOnlyPassesBetweenWindowsRestoredWithTheirWorkspaces() throws {
        let persistence = makePersistence()
        let first = Owner()
        let second = Owner()
        let fresh = Owner()
        let stateSecond = try makeState(name: "Second")

        persistence.register(first, origin: .restoredWorkspaces)
        persistence.register(fresh, origin: .fresh)
        persistence.register(second, origin: .restoredWorkspaces)
        persistence.unregister(first)
        #expect(persistence.isPrimary(second))
        persistence.flush(stateSecond, from: second, enabled: true)
        persistence.unregister(second)
        #expect(persistence.primaryWindow == nil)
        persistence.flush(try makeState(name: "Fresh"), from: fresh, enabled: true)
        #expect(try persistence.store.load() == stateSecond)

        withExtendedLifetime((first, second, fresh)) {}
    }

    @Test func aNewWindowRestoresTheFileOnlyWhenNoWindowExists() throws {
        let persistence = makePersistence()
        let state = try makeState()
        try persistence.store.save(state)
        let writes = persistence.store.writeCount

        #expect(persistence.loadForNewWindow(enabled: false) == nil)
        #expect(persistence.loadForNewWindow(enabled: true) == state)

        let owner = Owner()
        persistence.register(owner, origin: .fresh)
        withExtendedLifetime(owner) {
            #expect(persistence.loadForNewWindow(enabled: true) == nil)
        }
        #expect(persistence.store.writeCount == writes)
        #expect(try persistence.store.load() == state)
    }

    @Test func anIdenticalStateIsNotWrittenAgain() throws {
        let persistence = makePersistence()
        let owner = Owner()
        persistence.register(owner, origin: .fresh)
        let state = try makeState()

        persistence.flush(state, from: owner, enabled: true)
        persistence.flush(state, from: owner, enabled: true)
        persistence.stateDidChange(state, from: owner, enabled: true)
        #expect(persistence.store.writeCount == 1)
        #expect(!persistence.store.hasPendingSave)

        persistence.flush(try makeState(name: "Docs renamed"), from: owner, enabled: true)
        #expect(persistence.store.writeCount == 2)
    }

    @Test func aFailedWriteIsRetriedByTheNextFlush() throws {
        let writer = FailingWriter(failures: 1)
        let persistence = makePersistence(writer: writer)
        let owner = Owner()
        persistence.register(owner, origin: .fresh)
        let state = try makeState()

        persistence.flush(state, from: owner, enabled: true)
        #expect(persistence.store.writeCount == 0)
        #expect(try persistence.store.load() == nil)

        persistence.flush(state, from: owner, enabled: true)
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == state)

        persistence.flush(state, from: owner, enabled: true)
        #expect(persistence.store.writeCount == 1)
    }

    @Test func aFailedScheduledWriteIsRetriedOnTheNextChange() async throws {
        let writer = FailingWriter(failures: 1)
        let persistence = makePersistence(debounce: 0.05, writer: writer)
        let owner = Owner()
        persistence.register(owner, origin: .fresh)
        let state = try makeState()

        persistence.stateDidChange(state, from: owner, enabled: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(persistence.store.writeCount == 0)

        persistence.stateDidChange(state, from: owner, enabled: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == state)
    }

    @Test func flushWritesAPendingChangeEvenWhenTheStateDidNotMoveSince() throws {
        let persistence = makePersistence()
        let owner = Owner()
        persistence.register(owner, origin: .fresh)
        let state = try makeState()

        persistence.stateDidChange(state, from: owner, enabled: true)
        #expect(persistence.store.hasPendingSave)
        persistence.flush(state, from: owner, enabled: true)
        #expect(!persistence.store.hasPendingSave)
        #expect(try persistence.store.load() == state)
    }

    @Test func aNewerFileIsKeptUntilTheUserChangesSomething() throws {
        let persistence = makePersistence()
        var newer = try makeState(name: "From the future")
        newer.version = WorkspacePersistedState.currentVersion + 1
        try persistence.store.save(newer)
        let owner = Owner()

        #expect(persistence.loadForNewWindow(enabled: true) == nil)
        persistence.register(owner, origin: .fresh)

        let fresh = try makeState(name: "Fresh")
        persistence.stateDidChange(fresh, from: owner, enabled: true)
        persistence.flush(fresh, from: owner, enabled: true)
        #expect(persistence.store.writeCount == 1)
        #expect(throws: WorkspaceStateStoreError.newerVersion(newer.version)) {
            try persistence.store.load()
        }

        let changed = try makeState(name: "Changed")
        persistence.flush(changed, from: owner, enabled: true)
        #expect(try persistence.store.load() == changed)
    }
}
