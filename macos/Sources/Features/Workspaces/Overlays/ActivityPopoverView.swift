import SwiftUI

struct ActivityRow: Identifiable, Equatable {
    let id: UUID
    let workspaceID: UUID
    let tabID: UUID
    let surfaceID: UUID
    let title: String
    let subtitle: String
    let state: SurfaceActivityState
}

struct ActivitySection: Identifiable, Equatable {
    let id: UUID
    let header: String?
    let rows: [ActivityRow]

    var state: SurfaceActivityState {
        rows.map(\.state).max() ?? .idle
    }
}

enum ActivityRows {
    static func sections(
        from snapshot: WorkspaceOverlaySnapshot,
        home: String = NSHomeDirectory()
    ) -> [ActivitySection] {
        var sections: [ActivitySection] = []
        for workspace in snapshot.workspaces {
            for tab in workspace.tabs {
                if let section = section(for: tab, in: workspace, home: home) {
                    sections.append(section)
                }
            }
        }
        return sections.enumerated()
            .sorted { lhs, rhs in
                lhs.element.state != rhs.element.state
                    ? lhs.element.state > rhs.element.state
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func section(
        for tab: WorkspaceTabSummary,
        in workspace: WorkspaceSummary,
        home: String
    ) -> ActivitySection? {
        guard tab.isSplit else {
            guard tab.state != .idle, let pane = tab.panes.first else { return nil }
            let row = ActivityRow(
                id: pane.id,
                workspaceID: workspace.id,
                tabID: tab.id,
                surfaceID: pane.id,
                title: tab.title,
                subtitle: tab.lastCommand.map { "\(workspace.name) · \($0)" } ?? workspace.name,
                state: tab.state
            )
            return ActivitySection(id: tab.id, header: nil, rows: [row])
        }

        let rows = tab.panes.enumerated()
            .filter { $0.element.state != .idle }
            .sorted { lhs, rhs in
                lhs.element.state != rhs.element.state
                    ? lhs.element.state > rhs.element.state
                    : lhs.offset < rhs.offset
            }
            .map { entry in
                ActivityRow(
                    id: entry.element.id,
                    workspaceID: workspace.id,
                    tabID: tab.id,
                    surfaceID: entry.element.id,
                    title: entry.element.title,
                    subtitle: paneSubtitle(entry.element, home: home),
                    state: entry.element.state
                )
            }
        guard !rows.isEmpty else { return nil }
        return ActivitySection(id: tab.id, header: "\(tab.title) · \(workspace.name)", rows: rows)
    }

    private static func paneSubtitle(_ pane: WorkspacePaneSummary, home: String) -> String {
        var parts: [String] = []
        if let pwd = pane.pwd, !pwd.isEmpty {
            parts.append(WorkspaceFolderLabel.abbreviated(path: pwd, home: home))
        }
        if let command = pane.lastCommand, !command.isEmpty {
            parts.append(command)
        }
        return parts.joined(separator: " · ")
    }
}

enum ActivityPopoverTiming {
    static let openDelay: TimeInterval = 0.25
    static let closeDelay: TimeInterval = 0.18
}

struct ActivityPopoverView: View {
    let sections: [ActivitySection]
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
            if sections.isEmpty {
                Text("No terminals in progress.")
                    .font(.system(size: 12))
                    .foregroundColor(WorkspaceOverlayPalette.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(minHeight: ActivityPopoverView.rowHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(sections) { section in
                    if let header = section.header {
                        ActivityPopoverSectionHeader(text: header)
                    }
                    ForEach(section.rows) { row in
                        ActivityPopoverRow(row: row) { onSelect(row) }
                    }
                }
            }

            ActivityPopoverFooter(action: onShowWorkspaces)
        }
    }
}

private struct ActivityPopoverSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(WorkspaceOverlayPalette.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
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
                    if !row.subtitle.isEmpty {
                        Text(row.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundColor(WorkspaceOverlayPalette.secondaryText)
                            .lineLimit(2)
                    }
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
        .accessibilityLabel(
            [row.title, WorkspaceStateText.accessibilityLabel(row.state), row.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        )
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
