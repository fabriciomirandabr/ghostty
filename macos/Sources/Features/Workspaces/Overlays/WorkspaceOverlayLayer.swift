import SwiftUI

struct WorkspaceOverlayActions {
    var selectWorkspace: (UUID) -> Void
    var selectTab: (_ workspaceID: UUID, _ tabID: UUID, _ surfaceID: UUID?) -> Void
    var closeWorkspace: (UUID) -> Void
    var createWorkspace: (String, URL) -> WorkspaceError?
    var activityHoverChanged: (Bool) -> Void = { _ in }
}

struct WorkspaceOverlayLayer: View {
    static let titlebarConfirmationLeading: CGFloat = 70
    static let popoverGap: CGFloat = 4
    static let popoverTrailing: CGFloat = WorkspaceTitlebarView.trailingInset

    static func popoverTopPadding(titlebarHeight: CGFloat) -> CGFloat {
        popoverGap - (titlebarHeight - ActivityBadgeView.size) / 2
    }

    let titlebarHeight: CGFloat
    let snapshot: WorkspaceOverlaySnapshot
    @ObservedObject var state: WorkspaceOverlayState
    let thumbnails: WorkspaceThumbnailSource
    var terminalBackground: Color
    var terminalForeground: Color
    let actions: WorkspaceOverlayActions

    var body: some View {
        ZStack(alignment: .top) {
            if state.isOpen(.overview) {
                WorkspaceOverviewView(
                    snapshot: snapshot,
                    state: state,
                    thumbnails: thumbnails,
                    terminalBackground: terminalBackground,
                    terminalForeground: terminalForeground,
                    actions: overviewActions
                )
            }

            if hasTransient {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { state.dismissTransient() }
            }

            if state.isOpen(.activityPopover) {
                ActivityPopoverView(
                    sections: ActivityRows.sections(from: snapshot),
                    onSelect: { row in
                        state.dismissTransient()
                        state.dismiss(.overview)
                        actions.selectTab(row.workspaceID, row.tabID, row.surfaceID)
                    },
                    onShowWorkspaces: {
                        state.dismiss(.activityPopover)
                        state.present(.overview)
                    },
                    onHoverChanged: actions.activityHoverChanged
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, Self.popoverTrailing)
                .padding(.top, Self.popoverTopPadding(titlebarHeight: titlebarHeight))
            }

            if let pending = state.closeConfirmation,
               pending.anchor == .titlebar,
               let confirmation = CloseWorkspaceConfirmation.resolve(
                   workspaceID: pending.workspaceID,
                   in: snapshot,
                   foregroundProcessSurfaces: state.foregroundProcessSurfaces(pending.workspaceID)) {
                CloseWorkspaceConfirmationView(
                    confirmation: confirmation,
                    onCancel: { state.dismiss(.closeConfirmation) },
                    onConfirm: { confirmClose(pending.workspaceID) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Self.titlebarConfirmationLeading)
                .padding(.top, 6)
            }

            if state.isOpen(.switcher) {
                WorkspaceSwitcherView(
                    entries: WorkspaceSwitcherFilter.entries(from: snapshot),
                    onPick: { workspaceID in
                        state.dismissTransient()
                        state.dismiss(.overview)
                        actions.selectWorkspace(workspaceID)
                    },
                    onCancel: { state.dismiss(.switcher) }
                )
                .padding(.top, 16)
            }
        }
        .onChange(of: snapshot.workspaceIDs) { ids in
            state.reconcile(workspaceIDs: ids)
        }
    }

    private var hasTransient: Bool {
        state.isOpen(.switcher) ||
            state.isOpen(.activityPopover) ||
            state.closeConfirmation?.anchor == .titlebar
    }

    private var overviewActions: WorkspaceOverviewActions {
        WorkspaceOverviewActions(
            selectWorkspace: { workspaceID in
                state.dismiss(.overview)
                actions.selectWorkspace(workspaceID)
            },
            requestClose: { workspaceID in
                state.requestClose(
                    workspaceID: workspaceID,
                    anchor: .card,
                    in: snapshot,
                    close: actions.closeWorkspace
                )
            },
            confirmClose: confirmClose,
            cancelClose: { state.dismiss(.closeConfirmation) },
            toggleNewWorkspace: { state.toggle(.newWorkspace) },
            createWorkspace: { name, directory in
                let rejection = actions.createWorkspace(name, directory)
                if rejection == nil {
                    state.dismiss(.overview)
                }
                return rejection
            }
        )
    }

    private func confirmClose(_ workspaceID: UUID) {
        state.dismiss(.closeConfirmation)
        actions.closeWorkspace(workspaceID)
    }
}
