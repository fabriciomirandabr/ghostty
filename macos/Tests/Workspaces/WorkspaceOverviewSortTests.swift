import Testing
@testable import Ghostty

struct WorkspaceOverviewSortTests {
    private func workspaces() -> [WorkspaceSummary] {
        [
            OverlayFixtures.workspace("Default", isDefault: true),
            OverlayFixtures.workspace("zeta", tabs: [TabSpec(title: "dev", state: .running)]),
            OverlayFixtures.workspace("Alpha"),
            OverlayFixtures.workspace("mid", tabs: [TabSpec(title: "agent", state: .needsAttention)]),
            OverlayFixtures.workspace("beta", tabs: [TabSpec(title: "tests", state: .done)]),
        ]
    }

    @Test func defaultFirstForBothSorts() {
        let byName = WorkspaceOverviewOrder.ordered(workspaces(), by: .name)
        let byActivity = WorkspaceOverviewOrder.ordered(workspaces(), by: .activity)
        #expect(byName.first?.isDefault == true)
        #expect(byActivity.first?.isDefault == true)
        #expect(byName.filter(\.isDefault).count == 1)
        #expect(byActivity.filter(\.isDefault).count == 1)
    }

    @Test func nameSortIsCaseInsensitive() {
        let names = WorkspaceOverviewOrder.ordered(workspaces(), by: .name).map(\.name)
        #expect(names == ["Default", "Alpha", "beta", "mid", "zeta"])
    }

    @Test func activitySortUsesPriorityThenName() {
        let names = WorkspaceOverviewOrder.ordered(workspaces(), by: .activity).map(\.name)
        #expect(names == ["Default", "mid", "zeta", "beta", "Alpha"])
    }

    @Test func activityTiesFallBackToName() {
        let list = [
            OverlayFixtures.workspace("Default", isDefault: true),
            OverlayFixtures.workspace("b", tabs: [TabSpec(title: "x", state: .running)]),
            OverlayFixtures.workspace("a", tabs: [TabSpec(title: "x", state: .running)]),
        ]
        #expect(WorkspaceOverviewOrder.ordered(list, by: .activity).map(\.name) == ["Default", "a", "b"])
    }

    @Test func creationOrderIsKept() {
        let list = workspaces()
        #expect(WorkspaceOverviewOrder.ordered(list, by: .creation) == list)
    }

    @Test func defaultStaysFirstEvenWhenAnotherWorkspaceIsBusier() {
        let list = [
            OverlayFixtures.workspace("Default", isDefault: true),
            OverlayFixtures.workspace("agent", tabs: [TabSpec(title: "x", state: .needsAttention)]),
        ]
        #expect(WorkspaceOverviewOrder.ordered(list, by: .activity).map(\.name) == ["Default", "agent"])
    }

    @Test func columnCountFollowsWidth() {
        #expect(WorkspaceOverviewLayout.columnCount(for: 1400) == 4)
        #expect(WorkspaceOverviewLayout.columnCount(for: 1100) == 3)
        #expect(WorkspaceOverviewLayout.columnCount(for: 900) == 3)
        #expect(WorkspaceOverviewLayout.columnCount(for: 800) == 2)
        #expect(WorkspaceOverviewLayout.columnCount(for: 500) == 2)
    }

    @Test func countLabelPluralizes() {
        #expect(WorkspaceOverviewLayout.countLabel(1) == "1 workspace")
        #expect(WorkspaceOverviewLayout.countLabel(5) == "5 workspaces")
    }
}
