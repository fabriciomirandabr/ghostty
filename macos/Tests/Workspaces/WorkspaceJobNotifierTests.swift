import Foundation
import Testing
@testable import Ghostty

@MainActor
private final class RecordingSink: WorkspaceJobNotificationSink {
    var posted: [WorkspaceJobNotification] = []
    var retracted: [String] = []

    func post(_ notification: WorkspaceJobNotification) {
        posted.append(notification)
    }

    func retract(identifiers: [String]) {
        retracted.append(contentsOf: identifiers)
    }
}

@MainActor
private final class Clock {
    var current = Date(timeIntervalSinceReferenceDate: 5_000)

    func advance(_ seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

@MainActor
private struct Harness {
    let sink = RecordingSink()
    let clock = Clock()
    let flag: EnabledFlag
    let notifier: WorkspaceJobNotifier
    let surface = UUID()
    let workspace = UUID()

    init(enabled: Bool = true) {
        let clock = clock
        let flag = EnabledFlag(enabled)
        let sink = sink
        self.flag = flag
        notifier = WorkspaceJobNotifier(
            sink: sink,
            isEnabled: { flag.value },
            now: { clock.current })
    }

    static let hidden = WorkspaceJobVisibility(
        windowIsKey: true, appIsActive: false, workspaceIsSelected: true, tabIsSelected: true, surfaceIsFocused: true)

    func context(
        tab: String = "build",
        workspaceName: String = "api",
        visibility: WorkspaceJobVisibility = Harness.hidden
    ) -> WorkspaceJobContext {
        WorkspaceJobContext(
            tabName: tab, workspaceName: workspaceName, workspaceID: workspace, visibility: visibility)
    }

    func send(
        _ state: SurfaceActivityState,
        detail: String? = nil,
        desktop: Bool = false,
        context: WorkspaceJobContext? = nil
    ) {
        let resolved = context ?? self.context()
        notifier.activityDidChange(
            surfaceID: surface,
            activity: WorkspaceJobActivity(state: state, detail: detail, attentionIsDesktopNotification: desktop),
            context: { resolved })
    }
}

private final class EnabledFlag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

@MainActor
struct WorkspaceJobNotifierTests {
    @Test func runningToDonePostsDoneNotification() throws {
        let h = Harness()
        h.send(.idle)
        h.send(.running)
        h.send(.done)

        let note = try #require(h.sink.posted.first)
        #expect(h.sink.posted.count == 1)
        #expect(note.body == "Done")
        #expect(note.title == "build · api")
        #expect(note.threadIdentifier == h.workspace.uuidString)
        #expect(note.surfaceID == h.surface)
        #expect(note.workspaceID == h.workspace)
    }

    @Test(arguments: [SurfaceActivityState.idle, .running, .done])
    func anyStateToNeedsAttentionPostsNeedsYou(previous: SurfaceActivityState) {
        let h = Harness()
        h.send(previous)
        h.send(.needsAttention)

        #expect(h.sink.posted.map(\.body) == ["Needs you"])
    }

    @Test func firstObservationOnlySeedsState() {
        let h = Harness()
        h.send(.done)
        #expect(h.sink.posted.isEmpty)

        let seeded = Harness()
        seeded.send(.needsAttention)
        #expect(seeded.sink.posted.isEmpty)
    }

    @Test(arguments: [
        (SurfaceActivityState.idle, SurfaceActivityState.done),
        (.idle, .running),
        (.running, .idle),
        (.needsAttention, .running),
        (.needsAttention, .done),
        (.done, .idle),
    ])
    func otherTransitionsStaySilent(from: SurfaceActivityState, to: SurfaceActivityState) {
        let h = Harness()
        h.send(from)
        h.send(to)
        #expect(h.sink.posted.isEmpty)
    }

    @Test func repeatedStateDoesNotPostAgain() {
        let h = Harness()
        h.send(.running)
        h.send(.done)
        h.send(.done)
        h.send(.done)
        #expect(h.sink.posted.count == 1)
    }

    @Test func desktopNotificationAttentionIsLeftToTheTerminalPath() {
        let h = Harness()
        h.send(.idle)
        h.send(.needsAttention, desktop: true)
        #expect(h.sink.posted.isEmpty)
    }

    @Test func disabledConfigSuppressesNotifications() {
        let h = Harness(enabled: false)
        h.send(.running)
        h.send(.done)
        h.send(.needsAttention)
        #expect(h.sink.posted.isEmpty)

        h.flag.value = true
        h.send(.running)
        h.send(.done)
        #expect(h.sink.posted.count == 1)
    }

    @Test func attentionAndDoneKeepAdvancingStateWhileDisabled() {
        let h = Harness(enabled: false)
        h.send(.running)
        h.flag.value = true
        h.send(.done)
        #expect(h.sink.posted.map(\.body) == ["Done"])
    }
}

@MainActor
struct WorkspaceJobNotifierSuppressionTests {
    private func visibility(
        key: Bool = true,
        active: Bool = true,
        workspace: Bool = true,
        tab: Bool = true,
        focused: Bool = true
    ) -> WorkspaceJobVisibility {
        WorkspaceJobVisibility(
            windowIsKey: key,
            appIsActive: active,
            workspaceIsSelected: workspace,
            tabIsSelected: tab,
            surfaceIsFocused: focused)
    }

    @Test func visibleAndFocusedSurfaceSuppresses() {
        let h = Harness()
        let context = h.context(visibility: visibility())
        h.send(.running, context: context)
        h.send(.done, context: context)
        h.send(.needsAttention, context: context)
        #expect(h.sink.posted.isEmpty)
    }

    @Test(arguments: [
        (false, true, true, true, true),
        (true, false, true, true, true),
        (true, true, false, true, true),
        (true, true, true, false, true),
        (true, true, true, true, false),
    ])
    func anyMissingConditionPosts(key: Bool, active: Bool, workspace: Bool, tab: Bool, focused: Bool) {
        let h = Harness()
        let context = h.context(
            visibility: visibility(key: key, active: active, workspace: workspace, tab: tab, focused: focused))
        h.send(.running, context: context)
        h.send(.done, context: context)
        #expect(h.sink.posted.map(\.body) == ["Done"])
    }

    @Test func missingContextPostsNothing() {
        let h = Harness()
        h.notifier.activityDidChange(
            surfaceID: h.surface,
            activity: WorkspaceJobActivity(state: .running),
            context: { nil })
        h.notifier.activityDidChange(
            surfaceID: h.surface,
            activity: WorkspaceJobActivity(state: .done),
            context: { nil })
        #expect(h.sink.posted.isEmpty)
    }
}

@MainActor
struct WorkspaceJobNotifierDedupeTests {
    @Test func repeatedDoneInsideCoalesceWindowPostsOnce() {
        let h = Harness()
        h.send(.running)
        h.send(.done)
        h.clock.advance(1)
        h.send(.running)
        h.send(.done)
        #expect(h.sink.posted.count == 1)
    }

    @Test func doneAfterCoalesceWindowPostsAgain() {
        let h = Harness()
        h.send(.running)
        h.send(.done)
        h.clock.advance(WorkspaceJobNotifier.coalesceWindow)
        h.send(.running)
        h.send(.done)
        #expect(h.sink.posted.count == 2)
    }

    @Test func attentionAndDoneAreIndependentlyCoalesced() {
        let h = Harness()
        h.send(.running)
        h.send(.needsAttention)
        h.clock.advance(0.5)
        h.send(.running)
        h.send(.done)
        #expect(h.sink.posted.map(\.body) == ["Needs you", "Done"])
    }

    @Test func notificationsFromDifferentSurfacesDoNotCoalesce() {
        let h = Harness()
        let other = UUID()
        h.send(.running)
        h.send(.done)
        h.notifier.activityDidChange(
            surfaceID: other,
            activity: WorkspaceJobActivity(state: .running),
            context: { h.context() })
        h.notifier.activityDidChange(
            surfaceID: other,
            activity: WorkspaceJobActivity(state: .done),
            context: { h.context() })
        #expect(h.sink.posted.count == 2)
        #expect(Set(h.sink.posted.map(\.identifier)).count == 2)
    }

    @Test func identifierIsStablePerSurfaceAndKind() {
        let h = Harness()
        h.send(.running)
        h.send(.done)
        h.clock.advance(5)
        h.send(.running)
        h.send(.done)
        #expect(h.sink.posted.count == 2)
        #expect(h.sink.posted[0].identifier == h.sink.posted[1].identifier)
        #expect(h.sink.posted[0].identifier == WorkspaceJobNotifier.identifier(h.surface, .done))
    }

    @Test func leavingNeedsAttentionRetractsItsNotification() {
        let h = Harness()
        h.send(.idle)
        h.send(.needsAttention)
        h.send(.idle)
        #expect(h.sink.retracted == [WorkspaceJobNotifier.identifier(h.surface, .needsAttention)])
    }

    @Test func retractionResetsTheCoalescingWindow() {
        let h = Harness()
        h.send(.idle)
        h.send(.needsAttention)
        h.clock.advance(0.5)
        h.send(.running)
        h.clock.advance(0.5)
        h.send(.needsAttention)
        #expect(h.sink.posted.map(\.body) == ["Needs you", "Needs you"])
        #expect(h.sink.retracted == [WorkspaceJobNotifier.identifier(h.surface, .needsAttention)])
    }

    @Test(arguments: [(true, true, true), (true, false, false), (false, true, false), (false, false, false)])
    func enabledNeedsBothWorkspaceAndDesktopNotifications(workspace: Bool, desktop: Bool, expected: Bool) {
        #expect(
            WorkspaceJobNotifier.isEnabled(workspaceNotifications: workspace, desktopNotifications: desktop)
                == expected)
    }

    @Test func forgettingASurfaceReseedsItsState() {
        let h = Harness()
        h.send(.running)
        h.notifier.forget(surfaceID: h.surface)
        h.send(.done)
        #expect(h.sink.posted.isEmpty)
    }
}

@MainActor
struct WorkspaceJobNotificationPayloadTests {
    @Test func bodyHeadlines() {
        #expect(WorkspaceJobNotifier.body(.done, detail: nil) == "Done")
        #expect(WorkspaceJobNotifier.body(.needsAttention, detail: nil) == "Needs you")
    }

    @Test func bodyAppendsProgramText() {
        #expect(WorkspaceJobNotifier.body(.done, detail: "Refactor finished") == "Done: Refactor finished")
        #expect(WorkspaceJobNotifier.body(.needsAttention, detail: "Allow edit?") == "Needs you: Allow edit?")
    }

    @Test func emptyDetailIsIgnored() {
        #expect(WorkspaceJobNotifier.body(.done, detail: "") == "Done")
        #expect(WorkspaceJobNotifier.body(.done, detail: " \n\t ") == "Done")
    }

    @Test func detailWhitespaceIsCollapsed() {
        #expect(WorkspaceJobNotifier.truncated("a\n  b\tc") == "a b c")
    }

    @Test func detailAtLimitIsKept() {
        let text = String(repeating: "x", count: WorkspaceJobNotifier.maxDetailLength)
        #expect(WorkspaceJobNotifier.truncated(text) == text)
    }

    @Test func longDetailIsTruncatedWithEllipsis() throws {
        let text = String(repeating: "x", count: WorkspaceJobNotifier.maxDetailLength + 30)
        let result = try #require(WorkspaceJobNotifier.truncated(text))
        #expect(result.count == WorkspaceJobNotifier.maxDetailLength)
        #expect(result.hasSuffix("…"))
    }

    @Test func titleJoinsTabAndWorkspace() {
        let context = WorkspaceJobContext(
            tabName: "deploy",
            workspaceName: "infra",
            workspaceID: UUID(),
            visibility: Harness.hidden)
        #expect(WorkspaceJobNotifier.title(context) == "deploy · infra")
    }

    @Test func programDetailReachesTheNotificationBody() throws {
        let h = Harness()
        h.send(.running)
        h.send(.needsAttention, detail: "Run rm -rf build?")
        let note = try #require(h.sink.posted.first)
        #expect(note.body == "Needs you: Run rm -rf build?")
    }
}

struct SurfaceDesktopNotificationAttentionTests {
    private let now = Date(timeIntervalSinceReferenceDate: 9_000)

    @Test func pendingDesktopNotificationAloneIsDetected() {
        let signals = Signals().applying(.notification, at: now)
        #expect(signals.attentionIsOnlyDesktopNotification(at: now))
    }

    @Test func bellIsNotDesktopNotification() {
        let signals = Signals().applying(.notification, at: now).applying(.bell, at: now)
        #expect(!signals.attentionIsOnlyDesktopNotification(at: now))
    }

    @Test func programStatusIsNotDesktopNotification() {
        let report = ProgramStatusReport(state: .blocked)
        let signals = Signals().applying(.notification, at: now).applying(.programStatus(report), at: now)
        #expect(!signals.attentionIsOnlyDesktopNotification(at: now))
    }

    @Test func errorProgressIsNotDesktopNotification() {
        let signals = Signals().applying(.notification, at: now).applying(.progress(.error), at: now)
        #expect(!signals.attentionIsOnlyDesktopNotification(at: now))
    }

    @Test func nonAttentionStateIsNeverDesktopNotification() {
        #expect(!Signals().attentionIsOnlyDesktopNotification(at: now))
        let running = Signals().applying(.commandStarted, at: now)
        #expect(!running.attentionIsOnlyDesktopNotification(at: now))
    }
}
