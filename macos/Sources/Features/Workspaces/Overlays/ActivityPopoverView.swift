import SwiftUI

struct ActivityRow: Identifiable, Equatable {
    let id: UUID
    let workspaceID: UUID
    let tabID: UUID
    let surfaceID: UUID?
    let title: String
    let subtitle: String
    let state: SurfaceActivityState
}

enum ActivityRows {
    static func make(from snapshot: WorkspaceOverlaySnapshot) -> [ActivityRow] {
        var rows: [(order: Int, row: ActivityRow)] = []
        for workspace in snapshot.workspaces {
            for tab in workspace.tabs where tab.state != .idle {
                let subtitle = tab.lastCommand.map { "\(workspace.name) · \($0)" } ?? workspace.name
                rows.append((
                    rows.count,
                    ActivityRow(
                        id: tab.id,
                        workspaceID: workspace.id,
                        tabID: tab.id,
                        surfaceID: tab.busiestSurfaceID,
                        title: tab.title,
                        subtitle: subtitle,
                        state: tab.state
                    )
                ))
            }
        }
        return rows
            .sorted { lhs, rhs in
                lhs.row.state != rhs.row.state ? lhs.row.state > rhs.row.state : lhs.order < rhs.order
            }
            .map(\.row)
    }
}

enum ActivityPopoverTiming {
    static let openDelay: TimeInterval = 0.25
    static let closeDelay: TimeInterval = 0.18
}

struct ActivityPopoverView: View {
    let rows: [ActivityRow]
    var onSelect: (ActivityRow) -> Void
    var onShowWorkspaces: () -> Void
    var onHoverChanged: (Bool) -> Void = { _ in }

    static let maxContentHeight: CGFloat = 428
    static let panelWidth: CGFloat = 220
    static let rowHeight: CGFloat = 28
    static let badgeSize: CGFloat = 18

    var body: some View {
        ViewThatFits(in: .vertical) {
            list
            ScrollView { list }
        }
        .frame(width: Self.panelWidth - WorkspaceOverlayMetrics.panelInset * 2)
        .frame(maxHeight: Self.maxContentHeight)
        .fixedSize(horizontal: false, vertical: true)
        .workspaceOverlayPanel(shadowOpacity: 0.65, shadowRadius: 20, shadowY: 16)
        .onHover(perform: onHoverChanged)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Terminal activity")
    }

    private var list: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("No terminals in progress.")
                    .font(.system(size: 12))
                    .foregroundColor(WorkspaceOverlayPalette.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(minHeight: ActivityPopoverView.rowHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(rows) { row in
                    ActivityPopoverRow(row: row) { onSelect(row) }
                }
            }

            ActivityPopoverFooter(action: onShowWorkspaces)
        }
    }
}

private struct ActivityPopoverRow: View {
    let row: ActivityRow
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                StatusIndicatorView(
                    state: row.state,
                    diameter: ActivityPopoverView.badgeSize,
                    badgeText: StatusIndicatorView.badgeText(for: row.state, context: .tab, runningCount: 1)
                )

                VStack(alignment: .leading, spacing: 0) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(WorkspaceOverlayPalette.strongText)
                        .lineLimit(2)
                    Text(row.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(WorkspaceOverlayPalette.secondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .frame(minHeight: ActivityPopoverView.rowHeight)
            .background(WorkspaceOverlayRowBackground(isHighlighted: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(row.title), \(WorkspaceStateText.accessibilityLabel(row.state)), \(row.subtitle)")
    }
}

private struct ActivityPopoverFooter: View {
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceOverlayPalette.separator
                .frame(height: 1)
                .padding(.vertical, 6)
            Button(action: action) {
                Text("Show workspaces")
                    .font(.system(size: 12.5))
                    .foregroundColor(hovering ? WorkspaceOverlayPalette.strongText : WorkspaceOverlayPalette.menuText)
                    .padding(.horizontal, 10)
                    .frame(height: ActivityPopoverView.rowHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WorkspaceOverlayRowBackground(
                        isHighlighted: hovering,
                        highlight: WorkspaceOverlayPalette.footerHover
                    ))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}
