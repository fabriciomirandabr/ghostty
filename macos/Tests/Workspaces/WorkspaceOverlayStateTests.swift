import Foundation
import Testing
@testable import Ghostty

@MainActor
struct WorkspaceOverlayStateTests {
    private let workspaceID = UUID()

    @Test func escapeClosesTheHighestOverlayFirst() {
        let state = WorkspaceOverlayState()
        state.present(.overview)
        state.present(.activityPopover)
        state.present(.closeConfirmation(workspaceID: workspaceID, anchor: .card))

        #expect(state.top?.kind == .closeConfirmation)
        #expect(state.dismissTop())
        #expect(state.top?.kind == .activityPopover)
        #expect(state.dismissTop())
        #expect(state.top?.kind == .overview)
        #expect(state.dismissTop())
        #expect(!state.dismissTop())
        #expect(!state.isAnyOpen)
    }

    @Test func switcherSitsAboveEverything() {
        let state = WorkspaceOverlayState()
        state.present(.switcher)
        state.present(.overview)
        state.present(.closeConfirmation(workspaceID: workspaceID, anchor: .titlebar))
        #expect(state.top?.kind == .switcher)
        #expect(state.overlays.map(\.kind) == [.overview, .closeConfirmation, .switcher])
    }

    @Test func switcherAndPopoverExcludeEachOther() {
        let state = WorkspaceOverlayState()
        state.present(.activityPopover)
        state.present(.switcher)
        #expect(!state.isOpen(.activityPopover))
        #expect(state.isOpen(.switcher))

        state.present(.activityPopover)
        #expect(!state.isOpen(.switcher))
        #expect(state.isOpen(.activityPopover))
    }

    @Test func newWorkspaceOpensTheOverview() {
        let state = WorkspaceOverlayState()
        state.present(.newWorkspace)
        #expect(state.overlays.map(\.kind) == [.overview, .newWorkspace])
    }

    @Test func closingTheOverviewClosesWhatIsAnchoredToIt() {
        let state = WorkspaceOverlayState()
        state.present(.newWorkspace)
        state.present(.closeConfirmation(workspaceID: workspaceID, anchor: .card))
        state.dismiss(.overview)
        #expect(!state.isAnyOpen)
    }

    @Test func titlebarConfirmationSurvivesTheOverviewClosing() {
        let state = WorkspaceOverlayState()
        state.present(.overview)
        state.present(.closeConfirmation(workspaceID: workspaceID, anchor: .titlebar))
        state.dismiss(.overview)
        #expect(state.closeConfirmation?.anchor == .titlebar)
    }

    @Test func toggleOpensAndCloses() {
        let state = WorkspaceOverlayState()
        state.toggle(.overview)
        #expect(state.isOpen(.overview))
        state.toggle(.overview)
        #expect(!state.isOpen(.overview))
    }

    @Test func presentingTwiceKeepsOneInstance() {
        let state = WorkspaceOverlayState()
        state.present(.overview)
        state.present(.overview)
        #expect(state.overlays.count == 1)

        let other = UUID()
        state.present(.closeConfirmation(workspaceID: workspaceID, anchor: .card))
        state.present(.closeConfirmation(workspaceID: other, anchor: .card))
        #expect(state.closeConfirmation?.workspaceID == other)
        #expect(state.overlays.count == 2)
    }

    @Test func dismissTransientLeavesTheOverviewAlone() {
        let state = WorkspaceOverlayState()
        state.present(.overview)
        state.present(.activityPopover)
        state.dismissTransient()
        #expect(state.overlays.map(\.kind) == [.overview])
    }

    @Test func reconcileKeepsConfirmationForLiveWorkspace() {
        let state = WorkspaceOverlayState()
        state.present(.closeConfirmation(workspaceID: workspaceID, anchor: .titlebar))
        state.reconcile(workspaceIDs: [workspaceID])
        #expect(state.closeConfirmation != nil)
    }
}
