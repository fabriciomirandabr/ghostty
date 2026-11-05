import Foundation

enum SurfaceActivityState: Int, Comparable, Equatable, Sendable {
    case idle
    case done
    case running
    case needsAttention

    static let doneLifetime: TimeInterval = 10

    static func < (lhs: SurfaceActivityState, rhs: SurfaceActivityState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    enum Event: Equatable {
        case commandStarted
        case commandFinished
        case bell
        case notification
        case progress(Ghostty.Action.ProgressReport.State)
        case childExited
        case attentionCleared
        case programStatus(ProgramStatusReport)
    }

    struct Signals: Equatable {
        var bell: Bool = false
        var notificationPending: Bool = false
        var progress: Ghostty.Action.ProgressReport.State?
        var commandRunning: Bool = false
        var doneUntil: Date?
        var programRecords: [String: ProgramRecord] = [:]
        var programOrder: Int = 0

        func applying(_ event: Event, at now: Date) -> Signals {
            var next = self
            switch event {
            case .commandStarted:
                next.commandRunning = true
                next.doneUntil = nil
                next.programRecords.removeAll()

            case .commandFinished:
                next.commandRunning = false
                next.doneUntil = now.addingTimeInterval(SurfaceActivityState.doneLifetime)

            case .bell:
                next.bell = true

            case .notification:
                next.notificationPending = true

            case .progress(let state):
                next.progress = state == .remove ? nil : state

            case .childExited:
                next.commandRunning = false
                next.progress = nil
                next.doneUntil = nil
                next.programRecords.removeAll()

            case .attentionCleared:
                next.bell = false
                next.notificationPending = false

            case .programStatus(let report):
                next.applyProgramStatus(report, at: now)
            }
            return next
        }

        func state(at now: Date) -> SurfaceActivityState {
            if let program = programState(at: now) { return program }
            if bell || notificationPending { return .needsAttention }
            if let progress, progress == .error || progress == .pause { return .needsAttention }
            if commandRunning { return .running }
            if let progress, progress == .set || progress == .indeterminate { return .running }
            if let doneUntil, doneUntil > now { return .done }
            return .idle
        }

        func attentionIsOnlyDesktopNotification(at now: Date) -> Bool {
            guard state(at: now) == .needsAttention, notificationPending, !bell else { return false }
            if programState(at: now) != nil { return false }
            guard let progress else { return true }
            return progress != .error && progress != .pause
        }

        func doneExpiry(at now: Date) -> TimeInterval? {
            if !programRecords.isEmpty { return programDoneExpiry(at: now) }
            guard let doneUntil, doneUntil > now else { return nil }
            return doneUntil.timeIntervalSince(now)
        }
    }
}
