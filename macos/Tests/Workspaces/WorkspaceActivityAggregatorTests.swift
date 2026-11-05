import Testing
@testable import Ghostty

struct WorkspaceActivityAggregatorTests {
    @Test func tabPriority() {
        #expect(WorkspaceActivityAggregator.tabState([]) == .idle)
        #expect(WorkspaceActivityAggregator.tabState([.idle, .done]) == .done)
        #expect(WorkspaceActivityAggregator.tabState([.done, .running, .idle]) == .running)
        #expect(WorkspaceActivityAggregator.tabState([.running, .needsAttention, .done]) == .needsAttention)
    }

    @Test func workspacePriority() {
        #expect(WorkspaceActivityAggregator.workspaceState([]) == .idle)
        #expect(WorkspaceActivityAggregator.workspaceState([[.idle], [.done]]) == .done)
        #expect(WorkspaceActivityAggregator.workspaceState([[.done], [.running, .idle]]) == .running)
        #expect(WorkspaceActivityAggregator.workspaceState([[.running], [.idle, .needsAttention]]) == .needsAttention)
    }

    @Test func badgeCountsRunningTabs() {
        let summary = WorkspaceActivityAggregator.summary([
            [.running, .running],
            [.running],
            [.idle, .done],
        ])
        #expect(summary == .init(runningCount: 2, needsAttention: false))
    }

    @Test func attentionFromAnySurface() {
        let summary = WorkspaceActivityAggregator.summary([
            [.idle, .done],
            [.running, .needsAttention],
        ])
        #expect(summary == .init(runningCount: 1, needsAttention: true))
    }

    @Test func attentionOnlyTabIsNotRunning() {
        let summary = WorkspaceActivityAggregator.summary([[.needsAttention]])
        #expect(summary == .init(runningCount: 0, needsAttention: true))
    }

    @Test func emptyWindow() {
        #expect(WorkspaceActivityAggregator.summary([]) == .init(runningCount: 0, needsAttention: false))
    }
}
