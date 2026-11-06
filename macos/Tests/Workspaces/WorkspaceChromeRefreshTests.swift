import AppKit
import Combine
import Foundation
import Testing
@testable import Ghostty

@MainActor
private final class ManualClock {
    private(set) var time: TimeInterval = 0
    private var tasks: [(due: TimeInterval, work: @MainActor () -> Void)] = []

    func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        tasks.append((time + delay, work))
    }

    func advance(to target: TimeInterval) {
        while let index = tasks.indices
            .filter({ tasks[$0].due <= target })
            .min(by: { tasks[$0].due < tasks[$1].due }) {
            let task = tasks.remove(at: index)
            time = max(time, task.due)
            task.work()
        }
        time = target
    }
}

@MainActor
private final class FakeSurface {
    let activityState = CurrentValueSubject<SurfaceActivityState, Never>(.idle)
    let title = CurrentValueSubject<String, Never>("")
    let lastCommand = CurrentValueSubject<String?, Never>(nil)
    let pwd = CurrentValueSubject<String?, Never>(nil)

    var changes: AnyPublisher<Void, Never> {
        WorkspaceSurfaceChanges.merged(
            activityState: activityState,
            title: title,
            lastCommand: lastCommand,
            pwd: pwd)
    }
}

@MainActor
private final class ChromeHarness {
    let clock = ManualClock()
    let surface = FakeSurface()
    private(set) var refreshTimes: [TimeInterval] = []
    private(set) var persistCount = 0
    var persistedState = WorkspacePersistedState(selectedWorkspace: "default", workspaces: [])
    var mode = WorkspacePowerMode.performance
    var isPrimary = true
    var isOccluded = false
    private(set) var suspendedPersistChecks = 0
    var failWrites = false
    private(set) var writeCount = 0
    private(set) var fileState: WorkspacePersistedState?
    private var hasPendingSave = false
    private var gate = WorkspacePersistGate()
    private var throttle: WorkspaceChromeRefreshThrottle?
    private var cancellable: AnyCancellable?

    var refreshCount: Int { refreshTimes.count }
    var refreshMilliseconds: [Int] { refreshTimes.map { Int(($0 * 1000).rounded()) } }

    init() {
        let clock = clock
        let throttle = WorkspaceChromeRefreshThrottle(
            interval: { [unowned self] in self.mode.chromeThrottleInterval },
            now: { clock.time },
            schedule: { clock.schedule($0, $1) },
            isSuspended: { [unowned self] in self.isOccluded },
            performSuspended: { [unowned self] in
                self.suspendedPersistChecks += 1
                self.persistIfNeeded()
            },
            perform: { [unowned self] in self.refresh() }
        )
        self.throttle = throttle
        cancellable = surface.changes.sink { _ in throttle.request() }
    }

    func resume() {
        throttle?.resume()
    }

    private func refresh() {
        refreshTimes.append(clock.time)
        persistIfNeeded()
    }

    private func persistIfNeeded() {
        let state = persistedState
        let shouldPersist = gate.shouldPersist(
            state,
            enabled: true,
            isPrimary: isPrimary,
            writeCount: writeCount,
            hasPendingSave: hasPendingSave)
        guard shouldPersist else { return }
        persistCount += 1
        hasPendingSave = true
        clock.schedule(1.0) { [unowned self] in
            hasPendingSave = false
            guard !failWrites else { return }
            writeCount += 1
            fileState = state
        }
    }

    func handOff() {
        isPrimary = true
        gate.reset()
        request()
    }

    func urgentRefresh() {
        throttle?.noteRefreshed()
        refresh()
    }

    func request() {
        throttle?.request()
    }
}

@MainActor
struct WorkspaceChromeRefreshTests {
    @Test func fortyTitleChangesInOneSecondRefreshAtMostSixTimes() {
        let harness = ChromeHarness()

        for step in 1...40 {
            harness.clock.advance(to: Double(step) * 0.025)
            harness.surface.title.send("⠋ working \(step)")
        }
        harness.clock.advance(to: 1.5)

        #expect(harness.refreshCount >= 1)
        #expect(harness.refreshCount <= 6)
        #expect(harness.persistCount == 1)
    }

    @Test func theLastChangeOfABurstIsNeverStarved() throws {
        let harness = ChromeHarness()

        for step in 1...40 {
            harness.clock.advance(to: Double(step) * 0.025)
            harness.surface.title.send("⠋ working \(step)")
        }
        harness.clock.advance(to: 1.5)

        let last = try #require(harness.refreshTimes.last)
        #expect(last >= 1.0)
        #expect(last <= 1.0 + WorkspaceChromeRefreshThrottle.defaultInterval)
    }

    @Test func aSingleChangeRefreshesWithinTwoHundredMilliseconds() throws {
        let harness = ChromeHarness()

        harness.surface.title.send("api")
        harness.clock.advance(to: WorkspaceChromeRefreshThrottle.defaultInterval)

        #expect(harness.refreshCount == 1)
        let first = try #require(harness.refreshTimes.first)
        #expect(first <= WorkspaceChromeRefreshThrottle.defaultInterval)
    }

    @Test func aChangeAfterAQuietPeriodRefreshesAtOnce() {
        let harness = ChromeHarness()

        harness.surface.title.send("one")
        harness.clock.advance(to: 0.05)
        #expect(harness.refreshCount == 1)

        harness.clock.advance(to: 5)
        harness.surface.title.send("two")
        harness.clock.advance(to: 5)
        #expect(harness.refreshTimes == [0, 5])
    }

    @Test func changesInsideTheWindowCollapseIntoOneRefreshAtItsEnd() {
        let harness = ChromeHarness()

        harness.surface.title.send("one")
        harness.clock.advance(to: 0.01)
        harness.clock.advance(to: 0.05)
        harness.surface.title.send("two")
        harness.clock.advance(to: 0.1)
        harness.surface.title.send("three")
        harness.clock.advance(to: 0.19)
        #expect(harness.refreshCount == 1)

        harness.clock.advance(to: 0.2)
        #expect(harness.refreshCount == 2)
        harness.clock.advance(to: 1)
        #expect(harness.refreshCount == 2)
    }

    @Test func repeatedValuesNeverRefresh() {
        let harness = ChromeHarness()

        harness.surface.title.send("")
        harness.surface.activityState.send(.idle)
        harness.surface.lastCommand.send(nil)
        harness.surface.pwd.send(nil)
        harness.clock.advance(to: 1)

        #expect(harness.refreshCount == 0)

        harness.surface.title.send("api")
        harness.clock.advance(to: 2)
        harness.surface.title.send("api")
        harness.surface.title.send("api")
        harness.clock.advance(to: 3)
        #expect(harness.refreshCount == 1)
    }

    @Test func everyObservedFieldTriggersARefresh() {
        let harness = ChromeHarness()

        harness.surface.activityState.send(.running)
        harness.clock.advance(to: 1)
        harness.surface.lastCommand.send("make")
        harness.clock.advance(to: 2)
        harness.surface.pwd.send("/tmp/ws-project")
        harness.clock.advance(to: 3)
        harness.surface.title.send("api")
        harness.clock.advance(to: 4)

        #expect(harness.refreshCount == 4)
    }

    @Test func aRefreshDoneByAnotherPathAbsorbsThePendingOne() {
        let harness = ChromeHarness()

        harness.request()
        harness.urgentRefresh()
        harness.clock.advance(to: 1)

        #expect(harness.refreshCount == 1)
    }

    @Test func persistsAgainOnlyWhenThePersistedStateChanged() {
        let harness = ChromeHarness()

        harness.surface.title.send("one")
        harness.clock.advance(to: 1)
        harness.surface.title.send("two")
        harness.clock.advance(to: 2)
        #expect(harness.persistCount == 1)

        harness.persistedState.selectedWorkspace = "other"
        harness.surface.pwd.send("/tmp/ws-project")
        harness.clock.advance(to: 3)
        #expect(harness.persistCount == 2)

        harness.surface.title.send("three")
        harness.clock.advance(to: 4)
        #expect(harness.persistCount == 2)
    }

    @Test func throttleIntervalSwitchesWithPowerMode() {
        let harness = ChromeHarness()

        harness.surface.title.send("one")
        harness.clock.advance(to: 0)
        harness.surface.title.send("two")
        harness.clock.advance(to: 0.2)
        #expect(harness.refreshMilliseconds == [0, 200])

        harness.mode = .saver
        harness.clock.advance(to: 10)
        harness.surface.title.send("three")
        harness.clock.advance(to: 10)
        harness.surface.title.send("four")
        harness.clock.advance(to: 10.9)
        #expect(harness.refreshMilliseconds == [0, 200, 10_000])

        harness.clock.advance(to: 11)
        #expect(harness.refreshMilliseconds == [0, 200, 10_000, 11_000])

        harness.mode = .performance
        harness.surface.title.send("five")
        harness.clock.advance(to: 11.2)
        harness.surface.title.send("six")
        harness.clock.advance(to: 11.4)
        #expect(harness.refreshMilliseconds == [0, 200, 10_000, 11_000, 11_200, 11_400])
    }

    @Test func chromeRefreshesAreSkippedWhileTheWindowIsOccluded() {
        let harness = ChromeHarness()
        harness.isOccluded = true

        for step in 1...20 {
            harness.clock.advance(to: Double(step) * 0.1)
            harness.surface.title.send("⠋ working \(step)")
        }
        harness.clock.advance(to: 5)

        #expect(harness.refreshCount == 0)
        #expect(harness.suspendedPersistChecks >= 1)
    }

    @Test func persistenceKeepsRunningWhileTheWindowIsOccluded() {
        let harness = ChromeHarness()
        harness.isOccluded = true
        harness.persistedState = WorkspacePersistedState(selectedWorkspace: "hidden", workspaces: [])

        harness.surface.pwd.send("/tmp/ws-project")
        harness.clock.advance(to: 2)

        #expect(harness.refreshCount == 0)
        #expect(harness.persistCount == 1)
        #expect(harness.fileState == harness.persistedState)
    }

    @Test func becomingVisibleRunsExactlyOneRefreshAtOnce() {
        let harness = ChromeHarness()
        harness.isOccluded = true
        harness.surface.title.send("one")
        harness.clock.advance(to: 3)
        #expect(harness.refreshCount == 0)

        harness.isOccluded = false
        harness.resume()
        harness.clock.advance(to: 3)
        #expect(harness.refreshMilliseconds == [3_000])

        harness.clock.advance(to: 10)
        #expect(harness.refreshCount == 1)
    }

    @Test func resumeTwiceInTheSameTickRunsOneRefresh() {
        let harness = ChromeHarness()

        harness.resume()
        harness.resume()
        harness.clock.advance(to: 0)

        #expect(harness.refreshCount == 1)

        harness.resume()
        harness.resume()
        harness.clock.advance(to: 1)
        #expect(harness.refreshCount == 2)
    }

    @Test func resumeStaysSilentWhileTheWindowIsStillOccluded() {
        let harness = ChromeHarness()
        harness.isOccluded = true

        harness.resume()
        harness.clock.advance(to: 1)

        #expect(harness.refreshCount == 0)
    }

    @Test func becomingKeyRefreshesInsideASaverWindowWithoutWaiting() {
        let harness = ChromeHarness()
        harness.mode = .saver

        harness.surface.title.send("one")
        harness.clock.advance(to: 0)
        harness.surface.title.send("two")
        harness.clock.advance(to: 0.3)
        #expect(harness.refreshMilliseconds == [0])

        harness.mode = .performance
        harness.resume()
        harness.clock.advance(to: 0.3)
        #expect(harness.refreshMilliseconds == [0, 300])

        harness.clock.advance(to: 5)
        #expect(harness.refreshCount == 2)
    }

    @Test func persistGateRepeatsWhenPersistenceIsToggled() {
        var gate = WorkspacePersistGate()
        let state = WorkspacePersistedState(selectedWorkspace: "default", workspaces: [])

        let decisions = [
            gate.shouldPersist(state, enabled: true, isPrimary: true, writeCount: 0, hasPendingSave: false),
            gate.shouldPersist(state, enabled: true, isPrimary: true, writeCount: 0, hasPendingSave: true),
            gate.shouldPersist(state, enabled: true, isPrimary: true, writeCount: 1, hasPendingSave: false),
            gate.shouldPersist(state, enabled: false, isPrimary: true, writeCount: 1, hasPendingSave: false),
            gate.shouldPersist(state, enabled: false, isPrimary: true, writeCount: 1, hasPendingSave: false)
        ]

        #expect(decisions == [true, false, false, true, false])
    }

    @Test func aWindowThatIsNotPrimaryNeverRecordsItsState() {
        var gate = WorkspacePersistGate()
        let state = WorkspacePersistedState(selectedWorkspace: "default", workspaces: [])

        let decisions = [
            gate.shouldPersist(state, enabled: true, isPrimary: false, writeCount: 0, hasPendingSave: false),
            gate.shouldPersist(state, enabled: true, isPrimary: false, writeCount: 0, hasPendingSave: false),
            gate.shouldPersist(state, enabled: true, isPrimary: true, writeCount: 0, hasPendingSave: false)
        ]

        #expect(decisions == [false, false, true])
    }

    @Test func aHandOffPersistsTheNewPrimaryWithinTheThrottleWindow() throws {
        let harness = ChromeHarness()
        harness.isPrimary = false
        harness.persistedState = WorkspacePersistedState(selectedWorkspace: "second", workspaces: [])

        harness.surface.title.send("one")
        harness.clock.advance(to: 1)
        #expect(harness.refreshCount == 1)
        #expect(harness.persistCount == 0)
        #expect(harness.fileState == nil)

        let handedOffAt = harness.clock.time
        harness.handOff()
        harness.clock.advance(to: handedOffAt + WorkspaceChromeRefreshThrottle.defaultInterval)

        let last = try #require(harness.refreshTimes.last)
        #expect(harness.refreshCount == 2)
        #expect(last - handedOffAt <= WorkspaceChromeRefreshThrottle.defaultInterval)
        #expect(harness.persistCount == 1)

        harness.clock.advance(to: handedOffAt + 2)
        #expect(harness.fileState == harness.persistedState)
    }

    @Test func aFailedWriteIsRetriedByTheNextRefresh() {
        let harness = ChromeHarness()
        harness.failWrites = true

        harness.surface.title.send("one")
        harness.clock.advance(to: 2)
        #expect(harness.persistCount == 1)
        #expect(harness.writeCount == 0)

        harness.failWrites = false
        harness.surface.title.send("two")
        harness.clock.advance(to: 4)
        #expect(harness.persistCount == 2)
        #expect(harness.writeCount == 1)
        #expect(harness.fileState == harness.persistedState)

        harness.surface.title.send("three")
        harness.clock.advance(to: 6)
        #expect(harness.persistCount == 2)
    }
}

private final class PersistenceOwner {}

private final class FailingFileWriter {
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
struct WorkspacePersistGateIntegrationTests {
    private func makePersistence(writer: FailingFileWriter? = nil) -> WorkspacePersistence {
        let url = WorkspaceStateStoreTests.makeTemporaryFileURL()
        let store = WorkspaceStateStore(fileURL: url, debounceInterval: 60) {
            if let writer {
                try writer.write($0, to: $1)
            } else {
                try $0.write(to: $1, options: .atomic)
            }
        }
        return WorkspacePersistence(store: store)
    }

    private func state(_ name: String) -> WorkspacePersistedState {
        WorkspacePersistedState(selectedWorkspace: name, workspaces: [])
    }

    @Test func theNewPrimaryWritesItsStateRightAfterTheHandOff() throws {
        let persistence = makePersistence()
        let first = PersistenceOwner()
        let second = PersistenceOwner()
        var firstGate = WorkspacePersistGate()
        var secondGate = WorkspacePersistGate()
        persistence.register(first, origin: .restoredWorkspaces)
        persistence.register(second, origin: .restoredWorkspaces)

        firstGate.persistIfNeeded(state("first"), enabled: true, owner: first, persistence: persistence)
        try persistence.store.flush()
        secondGate.persistIfNeeded(state("second"), enabled: true, owner: second, persistence: persistence)
        #expect(!persistence.store.hasPendingSave)
        #expect(try persistence.store.load() == state("first"))

        persistence.unregister(first)
        secondGate.persistIfNeeded(state("second"), enabled: true, owner: second, persistence: persistence)
        try persistence.store.flush()

        #expect(try persistence.store.load() == state("second"))
        withExtendedLifetime((first, second)) {}
    }

    @Test func aFailedWriterIsRetriedByTheNextRefresh() throws {
        let writer = FailingFileWriter(failures: 1)
        let persistence = makePersistence(writer: writer)
        let owner = PersistenceOwner()
        var gate = WorkspacePersistGate()
        persistence.register(owner, origin: .fresh)

        gate.persistIfNeeded(state("one"), enabled: true, owner: owner, persistence: persistence)
        #expect(throws: CocoaError.self) { try persistence.store.flush() }
        #expect(persistence.store.writeCount == 0)
        #expect(try persistence.store.load() == nil)

        gate.persistIfNeeded(state("one"), enabled: true, owner: owner, persistence: persistence)
        #expect(persistence.store.hasPendingSave)
        try persistence.store.flush()
        #expect(persistence.store.writeCount == 1)
        #expect(try persistence.store.load() == state("one"))

        gate.persistIfNeeded(state("one"), enabled: true, owner: owner, persistence: persistence)
        #expect(!persistence.store.hasPendingSave)
        withExtendedLifetime(owner) {}
    }
}

@MainActor
struct WorkspaceSnapshotLifecycleTests {
    @Test func storeIsEmptyAfterClear() {
        let store = MockStore(defaultDirectory: WorkspaceFixtures.home, makeTab: { WorkspaceFixtures.makeTab() })
        store.snapshots.store(NSImage(), for: UUID())
        store.snapshots.store(NSImage(), for: UUID())
        #expect(store.snapshots.images.count == 2)

        store.snapshots.clear()

        #expect(store.snapshots.images.isEmpty)
    }

    @Test func clearingAnEmptyStorePublishesNothing() {
        let snapshots = WorkspaceSnapshotStore()
        var changes = 0
        let cancellable = snapshots.objectWillChange.sink { _ in changes += 1 }

        snapshots.clear()

        #expect(changes == 0)
        cancellable.cancel()
    }

    @Test func captureNeedsAKeyVisibleUnoccludedWindow() {
        #expect(WorkspaceSnapshotCapture.isAllowed(isKeyWindow: true, isVisible: true, isOccluded: false))
        #expect(!WorkspaceSnapshotCapture.isAllowed(isKeyWindow: false, isVisible: true, isOccluded: false))
        #expect(!WorkspaceSnapshotCapture.isAllowed(isKeyWindow: true, isVisible: false, isOccluded: false))
        #expect(!WorkspaceSnapshotCapture.isAllowed(isKeyWindow: true, isVisible: true, isOccluded: true))
    }
}

@MainActor
struct SurfaceMouseLocationTests {
    private let publish = Ghostty.SurfaceView.shouldPublishMouseLocation

    @Test func subPointMovesAreNotPublished() {
        #expect(!publish(CGPoint(x: 10, y: 10), CGPoint(x: 10.4, y: 10.9)))
        #expect(!publish(CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 10)))
    }

    @Test func movesOfOnePointOrMoreArePublished() {
        #expect(publish(CGPoint(x: 10, y: 10), CGPoint(x: 11, y: 10)))
        #expect(publish(CGPoint(x: 10, y: 10), CGPoint(x: 10, y: 8.5)))
    }

    @Test func enteringAndLeavingAlwaysPublish() {
        #expect(publish(nil, CGPoint(x: 0, y: 0)))
        #expect(publish(CGPoint(x: 0, y: 0), nil))
        #expect(!publish(nil, nil))
    }
}
