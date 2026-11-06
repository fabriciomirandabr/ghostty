import Foundation
import GhosttyKit
import Testing
@testable import Ghostty

private let t0 = Date(timeIntervalSinceReferenceDate: 3_000)

private func report(
    _ state: ProgramStatusReport.State,
    id: String = "",
    title: String? = nil,
    message: String? = nil,
    resume: String? = nil
) -> ProgramStatusReport {
    ProgramStatusReport(id: id, state: state, title: title, message: message, resume: resume)
}

extension SurfaceActivityStateTests {
    @Test(arguments: [
        (ProgramStatusReport.State.working, SurfaceActivityState.running),
        (.blocked, .needsAttention),
        (.error, .needsAttention),
        (.done, .done),
        (.idle, .idle),
    ])
    func programDerivationTable(state: ProgramStatusReport.State, expected: SurfaceActivityState) {
        let signals = Signals().applying(.programStatus(report(state)), at: t0)
        #expect(signals.state(at: t0) == expected)
    }

    @Test func clearReturnsToShellDerivation() {
        let signals = Signals()
            .applying(.commandStarted, at: t0)
            .applying(.programStatus(report(.done)), at: t0)
            .applying(.programStatus(report(.clear)), at: t0)
        #expect(signals.programRecords.isEmpty)
        #expect(signals.state(at: t0) == .running)
    }

    @Test func programStatusWinsOverBellAndRunningCommand() {
        let base = Signals()
            .applying(.commandStarted, at: t0)
            .applying(.bell, at: t0)
        #expect(base.state(at: t0) == .needsAttention)

        let working = base.applying(.programStatus(report(.working)), at: t0)
        #expect(working.state(at: t0) == .running)

        let idle = base.applying(.programStatus(report(.idle)), at: t0)
        #expect(idle.state(at: t0) == .idle)

        let done = base.applying(.programStatus(report(.done)), at: t0)
        #expect(done.state(at: t0) == .done)
    }

    @Test func doneExpiresAfterTenSecondsAndStaysIdleWhileProgramPresent() {
        let signals = Signals()
            .applying(.commandStarted, at: t0)
            .applying(.programStatus(report(.done)), at: t0)
        #expect(signals.state(at: t0.addingTimeInterval(9.9)) == .done)
        #expect(signals.state(at: t0.addingTimeInterval(10)) == .idle)
        #expect(signals.doneExpiry(at: t0) == 10)
        #expect(signals.doneExpiry(at: t0.addingTimeInterval(10)) == nil)
    }

    @Test func eachIdKeepsItsOwnRecord() {
        let signals = Signals()
            .applying(.programStatus(report(.working, id: "a")), at: t0)
            .applying(.programStatus(report(.blocked, id: "b")), at: t0)
        #expect(signals.state(at: t0) == .needsAttention)

        let cleared = signals.applying(.programStatus(report(.clear, id: "b")), at: t0)
        #expect(cleared.state(at: t0) == .running)

        let replaced = cleared.applying(.programStatus(report(.idle, id: "a")), at: t0)
        #expect(replaced.state(at: t0) == .idle)
    }

    @Test func clearWithIdRemovesChildrenAndClearWithoutIdRemovesAll() {
        let signals = Signals()
            .applying(.programStatus(report(.working, id: "deploy")), at: t0)
            .applying(.programStatus(report(.working, id: "deploy/us")), at: t0)
            .applying(.programStatus(report(.working, id: "deployer")), at: t0)
        let cleared = signals.applying(.programStatus(report(.clear, id: "deploy")), at: t0)
        #expect(Set(cleared.programRecords.keys) == ["deployer"])
        let all = signals.applying(.programStatus(report(.clear)), at: t0)
        #expect(all.programRecords.isEmpty)
    }

    @Test func childExitDropsProgramRecords() {
        let signals = Signals()
            .applying(.programStatus(report(.blocked)), at: t0)
            .applying(.childExited, at: t0)
        #expect(signals.programRecords.isEmpty)
        #expect(signals.state(at: t0) == .idle)
    }

    @Test func newShellCommandSupersedesProgramStatus() {
        let signals = Signals()
            .applying(.programStatus(report(.done)), at: t0)
            .applying(.commandStarted, at: t0)
        #expect(signals.programRecords.isEmpty)
        #expect(signals.state(at: t0) == .running)

        let idle = Signals()
            .applying(.programStatus(report(.idle)), at: t0)
            .applying(.commandStarted, at: t0)
            .applying(.bell, at: t0)
        #expect(idle.state(at: t0) == .needsAttention)
    }

    @Test func commandFinishedKeepsProgramStatus() {
        let signals = Signals()
            .applying(.commandStarted, at: t0)
            .applying(.programStatus(report(.working)), at: t0)
            .applying(.commandFinished, at: t0)
        #expect(signals.programRecords.count == 1)
        #expect(signals.state(at: t0) == .running)
    }

    @Test func recordsPerSurfaceAreCappedEvictingTheOldest() {
        var signals = Signals()
        let cap = SurfaceActivityState.maxProgramRecords
        for index in 0..<(cap + 10) {
            signals = signals.applying(.programStatus(report(.working, id: "id-\(index)")), at: t0)
        }
        #expect(signals.programRecords.count == cap)
        #expect(signals.programRecords["id-0"] == nil)
        #expect(signals.programRecords["id-9"] == nil)
        #expect(signals.programRecords["id-10"] != nil)
        #expect(signals.programRecords["id-\(cap + 9)"] != nil)

        let replaced = signals.applying(.programStatus(report(.blocked, id: "id-10")), at: t0)
        #expect(replaced.programRecords.count == cap)
        #expect(replaced.programRecords["id-11"] != nil)
    }

    @Test func detailPrefersMessageThenTitleOfTheMostUrgentRecord() {
        let titled = Signals()
            .applying(.programStatus(report(.working, title: "Build")), at: t0)
        #expect(titled.programDetail(at: t0) == "Build")

        let both = titled
            .applying(.programStatus(report(.working, title: "Build", message: "Compiling")), at: t0)
        #expect(both.programDetail(at: t0) == "Compiling")

        let blocked = both
            .applying(.programStatus(report(.blocked, id: "x", message: "Approve?")), at: t0)
        #expect(blocked.programDetail(at: t0) == "Approve?")

        let idle = Signals().applying(.programStatus(report(.idle, message: "Waiting")), at: t0)
        #expect(idle.programDetail(at: t0) == nil)
    }

    @Test func conversionFromTheCStruct() throws {
        let converted: ProgramStatusReport? = "a/b".withCString { id in
            "T".withCString { title in
                "M".withCString { msg in
                    ProgramStatusReport(c: ghostty_action_program_status_s(
                        state: GHOSTTY_PROGRAM_STATUS_STATE_BLOCKED,
                        kind: GHOSTTY_PROGRAM_STATUS_KIND_PERMISSION,
                        progress: 40,
                        id: id,
                        title: title,
                        msg: msg,
                        resume: nil
                    ))
                }
            }
        }
        let value = try #require(converted)
        #expect(value == ProgramStatusReport(
            id: "a/b",
            state: .blocked,
            kind: .permission,
            progress: 40,
            title: "T",
            message: "M"
        ))

        let bare = "".withCString { empty in
            ProgramStatusReport(c: ghostty_action_program_status_s(
                state: GHOSTTY_PROGRAM_STATUS_STATE_CLEAR,
                kind: GHOSTTY_PROGRAM_STATUS_KIND_NONE,
                progress: -1,
                id: empty,
                title: empty,
                msg: empty,
                resume: nil
            ))
        }
        #expect(bare == ProgramStatusReport(state: .clear))
    }

    @Test func conversionFromTheCStructCarriesResume() throws {
        func converted(resume: UnsafePointer<CChar>?) -> ProgramStatusReport? {
            "resume".withCString { id in
                "".withCString { empty in
                    ProgramStatusReport(c: ghostty_action_program_status_s(
                        state: GHOSTTY_PROGRAM_STATUS_STATE_CLEAR,
                        kind: GHOSTTY_PROGRAM_STATUS_KIND_NONE,
                        progress: -1,
                        id: id,
                        title: empty,
                        msg: empty,
                        resume: resume
                    ))
                }
            }
        }

        let set = try #require("claude/0f8fad5b-d9cb-469f-a165-70867728950e".withCString { converted(resume: $0) })
        #expect(set.resume == "claude/0f8fad5b-d9cb-469f-a165-70867728950e")
        let cleared = try #require("".withCString { converted(resume: $0) })
        #expect(cleared.resume == "")
        let absent = try #require(converted(resume: nil))
        #expect(absent.resume == nil)
    }

    @Test func resumeIsSetByAValidReport() {
        let signals = Signals().applying(.programStatus(report(.working, resume: "claude/0f8fad5b-d9cb-469f-a165-70867728950e")), at: t0)
        #expect(signals.programResume == ProgramResume(program: "claude", token: "0f8fad5b-d9cb-469f-a165-70867728950e"))
    }

    @Test func emptyResumeClears() {
        let signals = Signals()
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
            .applying(.programStatus(report(.clear, id: "resume", resume: "")), at: t0)
        #expect(signals.programResume == nil)
    }

    @Test func absentResumeKeeps() {
        let signals = Signals()
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
            .applying(.programStatus(report(.working)), at: t0)
        #expect(signals.programResume == ProgramResume(program: "claude", token: "1b4e28ba-2fa1-41d2-883f-0016d3cca427"))
    }

    @Test(arguments: [
        "sh/1b4e28ba-2fa1-41d2-883f-0016d3cca427",
        "claude/a;b",
        "claude/",
        "/1b4e28ba-2fa1-41d2-883f-0016d3cca427",
        "claude",
        "claude/a/b",
        "claude/../x",
        "claude/--dangerously-skip-permissions",
        "claude/-x",
        "claude/abc",
    ])
    func invalidResumeKeeps(raw: String) {
        let signals = Signals()
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
            .applying(.programStatus(report(.clear, id: "resume", resume: raw)), at: t0)
        #expect(signals.programResume == ProgramResume(program: "claude", token: "1b4e28ba-2fa1-41d2-883f-0016d3cca427"))
    }

    @Test func commandStartedClearsResume() {
        let signals = Signals()
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
            .applying(.commandStarted, at: t0)
        #expect(signals.programResume == nil)
    }

    @Test func commandFinishedClearsResume() {
        let signals = Signals()
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
            .applying(.commandFinished, at: t0)
        #expect(signals.programResume == nil)
    }

    @Test func childExitedClearsResume() {
        let signals = Signals()
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
            .applying(.childExited, at: t0)
        #expect(signals.programResume == nil)
    }

    @Test func bellAndProgressKeepResume() {
        let signals = Signals()
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
            .applying(.bell, at: t0)
            .applying(.notification, at: t0)
            .applying(.progress(.set), at: t0)
            .applying(.attentionCleared, at: t0)
        #expect(signals.programResume == ProgramResume(program: "claude", token: "1b4e28ba-2fa1-41d2-883f-0016d3cca427"))
    }

    private static let seededResume = ProgramResume(program: "claude", token: "0f8fad5b-d9cb-469f-a165-70867728950e")
    private static let otherResume = ProgramResume(program: "claude", token: "1b4e28ba-2fa1-41d2-883f-0016d3cca427")

    @Test func aSeededResumeIsPresentFromTheStart() throws {
        let resume = try #require(Self.seededResume)
        let signals = Signals().applying(.resumeSeeded(resume), at: t0)
        #expect(signals.programResume == resume)
        #expect(signals.resumeSeeded)
    }

    @Test func commandStartedKeepsASeededResume() throws {
        let resume = try #require(Self.seededResume)
        let signals = Signals()
            .applying(.resumeSeeded(resume), at: t0)
            .applying(.commandStarted, at: t0)
        #expect(signals.programResume == resume)
        #expect(signals.state(at: t0) == .running)
    }

    @Test func commandFinishedClearsASeededResume() throws {
        let resume = try #require(Self.seededResume)
        let signals = Signals()
            .applying(.resumeSeeded(resume), at: t0)
            .applying(.commandStarted, at: t0)
            .applying(.commandFinished, at: t0)
        #expect(signals.programResume == nil)
        #expect(!signals.resumeSeeded)
    }

    @Test func childExitedClearsASeededResume() throws {
        let signals = Signals()
            .applying(.resumeSeeded(try #require(Self.seededResume)), at: t0)
            .applying(.childExited, at: t0)
        #expect(signals.programResume == nil)
        #expect(!signals.resumeSeeded)
    }

    @Test func aReportReplacesASeededResumeAndDropsTheFlag() throws {
        let other = try #require(Self.otherResume)
        let replaced = Signals()
            .applying(.resumeSeeded(try #require(Self.seededResume)), at: t0)
            .applying(.commandStarted, at: t0)
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/\(other.token)")), at: t0)
        #expect(replaced.programResume == other)
        #expect(!replaced.resumeSeeded)
        #expect(replaced.applying(.commandStarted, at: t0).programResume == nil)

        let cleared = Signals()
            .applying(.resumeSeeded(try #require(Self.seededResume)), at: t0)
            .applying(.programStatus(report(.clear, id: "resume", resume: "")), at: t0)
        #expect(cleared.programResume == nil)
        #expect(!cleared.resumeSeeded)
    }

    @Test func anInvalidOrAbsentReportKeepsASeededResume() throws {
        let resume = try #require(Self.seededResume)
        let signals = Signals()
            .applying(.resumeSeeded(resume), at: t0)
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/--flag")), at: t0)
            .applying(.programStatus(report(.working)), at: t0)
        #expect(signals.programResume == resume)
        #expect(signals.resumeSeeded)
    }

    @Test func clearReportWithUnusedIdSetsResumeAndKeepsState() {
        let signals = Signals()
            .applying(.commandStarted, at: t0)
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/0f8fad5b-d9cb-469f-a165-70867728950e")), at: t0)
        #expect(signals.state(at: t0) == .running)
        #expect(signals.programRecords.isEmpty)
        #expect(signals.programResume == ProgramResume(program: "claude", token: "0f8fad5b-d9cb-469f-a165-70867728950e"))
    }

    @Test func resumeCarrierKeepsOtherProgramRecords() {
        let signals = Signals()
            .applying(.programStatus(report(.working, id: "")), at: t0)
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
        #expect(signals.programRecords.count == 1)
        #expect(signals.state(at: t0) == .running)
    }

    @Test func nativeClearWithoutResumeKeepsResume() {
        let signals = Signals()
            .applying(.programStatus(report(.working, id: "x")), at: t0)
            .applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
            .applying(.programStatus(report(.clear)), at: t0)
        #expect(signals.programRecords.isEmpty)
        #expect(signals.programResume == ProgramResume(program: "claude", token: "1b4e28ba-2fa1-41d2-883f-0016d3cca427"))
    }

    @Test func repeatedResumeDoesNotAccumulate() {
        var signals = Signals()
        for _ in 0..<50 {
            signals = signals.applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0)
        }
        #expect(signals == Signals().applying(.programStatus(report(.clear, id: "resume", resume: "claude/1b4e28ba-2fa1-41d2-883f-0016d3cca427")), at: t0))
    }
}
