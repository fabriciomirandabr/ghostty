import Foundation
import Testing
@testable import Ghostty

typealias Signals = SurfaceActivityState.Signals

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

struct SurfaceActivityStateTests {
    @Test(arguments: [
        (Signals(bell: true), SurfaceActivityState.needsAttention),
        (Signals(notificationPending: true), .needsAttention),
        (Signals(progress: .error), .needsAttention),
        (Signals(progress: .pause), .needsAttention),
        (Signals(commandRunning: true), .running),
        (Signals(progress: .set), .running),
        (Signals(progress: .indeterminate), .running),
        (Signals(doneUntil: t0.addingTimeInterval(5)), .done),
        (Signals(doneUntil: t0.addingTimeInterval(-1)), .idle),
        (Signals(), .idle),
        (Signals(bell: true, commandRunning: true), .needsAttention),
        (Signals(progress: .error, commandRunning: true), .needsAttention),
        (Signals(commandRunning: true, doneUntil: t0.addingTimeInterval(5)), .running),
    ])
    func derivationTable(signals: Signals, expected: SurfaceActivityState) {
        #expect(signals.state(at: t0) == expected)
    }

    @Test func commandStartedSetsRunning() {
        let signals = Signals().applying(.commandStarted, at: t0)
        #expect(signals.state(at: t0) == .running)
    }

    @Test func commandFinishedClearsRunningAndSetsDone() {
        let signals = Signals()
            .applying(.commandStarted, at: t0)
            .applying(.commandFinished, at: t0)
        #expect(signals.commandRunning == false)
        #expect(signals.state(at: t0) == .done)
    }

    @Test func doneExpiresAfterTenSeconds() {
        let signals = Signals().applying(.commandFinished, at: t0)
        #expect(signals.state(at: t0.addingTimeInterval(9.9)) == .done)
        #expect(signals.state(at: t0.addingTimeInterval(10)) == .idle)
        #expect(signals.state(at: t0.addingTimeInterval(60)) == .idle)
    }

    @Test func newStartCancelsDone() {
        let signals = Signals()
            .applying(.commandFinished, at: t0)
            .applying(.commandStarted, at: t0.addingTimeInterval(1))
        #expect(signals.doneUntil == nil)
        #expect(signals.state(at: t0.addingTimeInterval(2)) == .running)
        let finished = signals.applying(.commandFinished, at: t0.addingTimeInterval(3))
        #expect(finished.state(at: t0.addingTimeInterval(12)) == .done)
        #expect(finished.state(at: t0.addingTimeInterval(13)) == .idle)
    }

    @Test func focusClearsAttention() {
        let signals = Signals()
            .applying(.bell, at: t0)
            .applying(.notification, at: t0)
            .applying(.commandStarted, at: t0)
        #expect(signals.state(at: t0) == .needsAttention)
        let cleared = signals.applying(.attentionCleared, at: t0)
        #expect(cleared.state(at: t0) == .running)
    }

    @Test func attentionClearDoesNotClearProgressError() {
        let signals = Signals()
            .applying(.progress(.error), at: t0)
            .applying(.attentionCleared, at: t0)
        #expect(signals.state(at: t0) == .needsAttention)
    }

    @Test func progressRemoveClearsRunning() {
        let running = Signals().applying(.progress(.indeterminate), at: t0)
        #expect(running.state(at: t0) == .running)
        let removed = running.applying(.progress(.remove), at: t0)
        #expect(removed.progress == nil)
        #expect(removed.state(at: t0) == .idle)
    }

    @Test func progressRemoveKeepsCommandRunning() {
        let signals = Signals()
            .applying(.commandStarted, at: t0)
            .applying(.progress(.set), at: t0)
            .applying(.progress(.remove), at: t0)
        #expect(signals.state(at: t0) == .running)
    }

    @Test func childExitedClearsRunning() {
        let signals = Signals()
            .applying(.commandStarted, at: t0)
            .applying(.progress(.set), at: t0)
            .applying(.childExited, at: t0)
        #expect(signals.state(at: t0) == .idle)
    }

    @Test func repeatedStartsNoTimerLeak() {
        var signals = Signals()
        for index in 0..<1000 {
            signals = signals.applying(.commandStarted, at: t0.addingTimeInterval(Double(index)))
        }
        #expect(signals == Signals().applying(.commandStarted, at: t0))
        #expect(signals.doneExpiry(at: t0) == nil)
        #expect(signals.state(at: t0) == .running)
    }

    @Test func doneExpiryReportsRemainingTime() {
        let signals = Signals().applying(.commandFinished, at: t0)
        #expect(signals.doneExpiry(at: t0.addingTimeInterval(4)) == 6)
        #expect(signals.doneExpiry(at: t0.addingTimeInterval(10)) == nil)
    }

    @Test func priorityOrder() {
        #expect(SurfaceActivityState.idle < .done)
        #expect(SurfaceActivityState.done < .running)
        #expect(SurfaceActivityState.running < .needsAttention)
    }
}
