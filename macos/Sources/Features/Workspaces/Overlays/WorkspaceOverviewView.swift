import SwiftUI

enum WorkspaceOverviewOrder {
    static func ordered(_ workspaces: [WorkspaceSummary], by sort: WorkspaceOverviewSort) -> [WorkspaceSummary] {
        let pinned = workspaces.filter(\.isDefault)
        let rest = workspaces.filter { !$0.isDefault }

        switch sort {
        case .creation:
            return pinned + rest

        case .name:
            return pinned + rest.sorted { byName($0, $1) }

        case .activity:
            return pinned + rest.sorted { lhs, rhs in
                lhs.state != rhs.state ? lhs.state > rhs.state : byName(lhs, rhs)
            }
        }
    }

    private static func byName(_ lhs: WorkspaceSummary, _ rhs: WorkspaceSummary) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

enum WorkspaceOverviewLayout {
    static let wideBreakpoint: CGFloat = 1100
    static let mediumBreakpoint: CGFloat = 800

    static func columnCount(for width: CGFloat) -> Int {
        if width > wideBreakpoint { return 4 }
        if width > mediumBreakpoint { return 3 }
        return 2
    }

    static func countLabel(_ count: Int) -> String {
        count == 1 ? "1 workspace" : "\(count) workspaces"
    }
}

struct WorkspaceOverviewActions {
    var selectWorkspace: (UUID) -> Void
    var requestClose: (UUID) -> Void
    var confirmClose: (UUID) -> Void
    var cancelClose: () -> Void
    var toggleNewWorkspace: () -> Void
    var createWorkspace: (String, URL) -> WorkspaceError?
}

struct WorkspaceOverviewView: View {
    let snapshot: WorkspaceOverlaySnapshot
    @ObservedObject var state: WorkspaceOverlayState
    let thumbnails: WorkspaceThumbnailSource
    var terminalBackground: Color
    var terminalForeground: Color
    let actions: WorkspaceOverviewActions

    @State private var sortMenuOpen = false

    private let gridSpacing: CGFloat = 22

    var body: some View {
        ZStack(alignment: .top) {
            WorkspaceOverlayPalette.overviewBackground

            VStack(spacing: 0) {
                header
                    .zIndex(1)
                content
            }

            if sortMenuOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { sortMenuOpen = false }
                SortMenu(selection: state.sort) { sort in
                    state.sort = sort
                    sortMenuOpen = false
                }
                .padding(.top, 50)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces overview")
        .onExitCommand {
            if sortMenuOpen {
                sortMenuOpen = false
            } else {
                _ = state.dismissTop()
            }
        }
    }

    private var header: some View {
        Button {
            sortMenuOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(WorkspaceOverviewLayout.countLabel(snapshot.workspaces.count))
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(WorkspaceOverlayPalette.hint)
            }
            .foregroundColor(WorkspaceOverlayPalette.primaryText)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Capsule().fill(sortMenuOpen ? WorkspaceOverlayPalette.rowHover : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .accessibilityLabel("\(WorkspaceOverviewLayout.countLabel(snapshot.workspaces.count)), sort options")
    }

    private var content: some View {
        GeometryReader { proxy in
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: gridSpacing, alignment: .top),
                count: WorkspaceOverviewLayout.columnCount(for: proxy.size.width)
            )

            ScrollView {
                LazyVGrid(columns: columns, spacing: gridSpacing) {
                    ForEach(WorkspaceOverviewOrder.ordered(snapshot.workspaces, by: state.sort)) { workspace in
                        card(for: workspace)
                            .zIndex(state.closeConfirmation?.workspaceID == workspace.id ? 1 : 0)
                    }

                    newWorkspaceCard
                        .zIndex(state.isOpen(.newWorkspace) ? 1 : 0)
                }
                .frame(maxWidth: 1560)
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func card(for workspace: WorkspaceSummary) -> some View {
        WorkspaceCardView(
            workspace: workspace,
            thumbnails: thumbnails,
            terminalBackground: terminalBackground,
            terminalForeground: terminalForeground,
            onSelect: { actions.selectWorkspace(workspace.id) },
            onClose: { actions.requestClose(workspace.id) }
        )
        .overlay {
            if let pending = state.closeConfirmation,
               pending.anchor == .card,
               pending.workspaceID == workspace.id,
               let confirmation = CloseWorkspaceConfirmation.resolve(
                   workspaceID: workspace.id,
                   in: snapshot,
                   foregroundProcessSurfaces: state.foregroundProcessSurfaces(workspace.id)) {
                CloseWorkspaceConfirmationView(
                    confirmation: confirmation,
                    onCancel: actions.cancelClose,
                    onConfirm: { actions.confirmClose(workspace.id) }
                )
            }
        }
    }

    private var newWorkspaceCard: some View {
        NewWorkspaceCardView(onSelect: actions.toggleNewWorkspace)
            .overlay {
                if state.isOpen(.newWorkspace) {
                    NewWorkspaceSheet(
                        existingNames: snapshot.names,
                        onCreate: actions.createWorkspace,
                        onCancel: { state.dismiss(.newWorkspace) }
                    )
                }
            }
    }
}

private struct SortMenu: View {
    let selection: WorkspaceOverviewSort
    var onSelect: (WorkspaceOverviewSort) -> Void

    var body: some View {
        VStack(spacing: 0) {
            item("Sort by name", sort: .name)
            item("Sort by activity", sort: .activity)
        }
        .frame(minWidth: 188)
        .workspaceOverlayPanel(shadowOpacity: 0.6, shadowRadius: 18, shadowY: 12)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sort workspaces")
    }

    private func item(_ title: String, sort: WorkspaceOverviewSort) -> some View {
        SortMenuItem(title: title, isSelected: selection == sort) { onSelect(sort) }
    }
}

private struct SortMenuItem: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(isSelected ? "●" : "")
                    .font(.system(size: 8))
                    .frame(width: 10)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
            .foregroundColor(hovering ? WorkspaceOverlayPalette.strongText : WorkspaceOverlayPalette.menuText)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(WorkspaceOverlayRowBackground(isHighlighted: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
