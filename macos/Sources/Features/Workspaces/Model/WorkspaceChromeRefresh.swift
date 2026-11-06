import Combine
import Foundation

@MainActor
final class WorkspaceChromeRefreshThrottle {
    static let defaultInterval = WorkspacePowerMode.performance.chromeThrottleInterval

    typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> Void

    private static let tolerance: TimeInterval = 0.005

    private let interval: @MainActor () -> TimeInterval
    private let now: () -> TimeInterval
    private let schedule: Schedule
    private let isSuspended: @MainActor () -> Bool
    private let perform: () -> Void
    private let performSuspended: () -> Void
    private var lastRefresh: TimeInterval?
    private var isDirty = false
    private var isScheduled = false
    private var isResumePending = false

    init(
        interval: @escaping @MainActor () -> TimeInterval = { WorkspacePowerMonitor.shared.mode.chromeThrottleInterval },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping Schedule = WorkspaceChromeRefreshThrottle.dispatchSchedule,
        isSuspended: @escaping @MainActor () -> Bool = { false },
        performSuspended: @escaping () -> Void = {},
        perform: @escaping () -> Void
    ) {
        self.interval = interval
        self.now = now
        self.schedule = schedule
        self.isSuspended = isSuspended
        self.performSuspended = performSuspended
        self.perform = perform
    }

    nonisolated static func dispatchSchedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let run: @Sendable () -> Void = { MainActor.assumeIsolated { work() } }
        if delay <= 0 {
            DispatchQueue.main.async(execute: run)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
        }
    }

    func request() {
        isDirty = true
        guard !isScheduled else { return }
        scheduleNext()
    }

    func noteRefreshed() {
        isDirty = false
        lastRefresh = now()
    }

    func resume() {
        guard !isResumePending else { return }
        isResumePending = true
        schedule(0) { [weak self] in
            guard let self else { return }
            self.isResumePending = false
            guard !self.isSuspended() else { return }
            self.noteRefreshed()
            self.perform()
        }
    }

    private func scheduleNext() {
        isScheduled = true
        let wait = lastRefresh.map { max(0, interval() - (now() - $0)) } ?? 0
        schedule(wait) { [weak self] in self?.fire() }
    }

    private func fire() {
        isScheduled = false
        guard isDirty else { return }

        if let lastRefresh, now() - lastRefresh < interval() - Self.tolerance {
            scheduleNext()
            return
        }

        noteRefreshed()
        if isSuspended() {
            performSuspended()
        } else {
            perform()
        }
    }
}

struct WorkspacePersistGate {
    private var last: WorkspacePersistedState?
    private var lastEnabled: Bool?
    private var isOutstanding = false
    private var passedWriteCount = 0

    mutating func reset() {
        last = nil
        lastEnabled = nil
        isOutstanding = false
    }

    mutating func shouldPersist(
        _ state: WorkspacePersistedState,
        enabled: Bool,
        isPrimary: Bool,
        writeCount: Int,
        hasPendingSave: Bool
    ) -> Bool {
        guard isPrimary else {
            reset()
            return false
        }

        if state == last, enabled == lastEnabled {
            guard isOutstanding, !hasPendingSave else { return false }
            if writeCount > passedWriteCount {
                isOutstanding = false
                return false
            }
        }

        last = state
        lastEnabled = enabled
        isOutstanding = enabled
        passedWriteCount = writeCount
        return true
    }

    @MainActor
    mutating func persistIfNeeded(
        _ state: WorkspacePersistedState,
        enabled: Bool,
        owner: AnyObject,
        persistence: WorkspacePersistence
    ) {
        guard shouldPersist(
            state,
            enabled: enabled,
            isPrimary: persistence.isPrimary(owner),
            writeCount: persistence.store.writeCount,
            hasPendingSave: persistence.store.hasPendingSave
        ) else { return }
        persistence.stateDidChange(state, from: owner, enabled: enabled)
    }
}

enum WorkspaceSurfaceChanges {
    static func merged<A: Publisher, T: Publisher, C: Publisher, P: Publisher>(
        activityState: A,
        title: T,
        lastCommand: C,
        pwd: P
    ) -> AnyPublisher<Void, Never>
    where A.Output: Equatable, T.Output: Equatable, C.Output: Equatable, P.Output: Equatable,
          A.Failure == Never, T.Failure == Never, C.Failure == Never, P.Failure == Never {
        Publishers.Merge4(
            activityState.removeDuplicates().dropFirst().map { _ in () },
            title.removeDuplicates().dropFirst().map { _ in () },
            lastCommand.removeDuplicates().dropFirst().map { _ in () },
            pwd.removeDuplicates().dropFirst().map { _ in () }
        ).eraseToAnyPublisher()
    }
}

enum WorkspaceSnapshotCapture {
    static func isAllowed(isKeyWindow: Bool, isVisible: Bool, isOccluded: Bool) -> Bool {
        isKeyWindow && isVisible && !isOccluded
    }
}
