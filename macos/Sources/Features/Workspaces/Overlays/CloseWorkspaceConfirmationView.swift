import SwiftUI

struct CloseWorkspaceConfirmation: Equatable {
    struct Row: Identifiable, Equatable {
        let id: UUID
        let title: String
        let state: SurfaceActivityState
        let hasForegroundProcess: Bool

        var suffix: String {
            hasForegroundProcess && !CloseWorkspaceConfirmation.isBusy(state)
                ? "process running"
                : WorkspaceStateText.rowSuffix(state)
        }
    }

    let workspaceID: UUID
    let workspaceName: String
    let rows: [Row]

    var requiresConfirmation: Bool {
        !rows.isEmpty
    }

    var headline: String {
        let count = rows.count
        return count == 1
            ? "1 terminal running. Close anyway?"
            : "\(count) terminals running. Close anyway?"
    }

    static func isBusy(_ state: SurfaceActivityState) -> Bool {
        state == .running || state == .needsAttention
    }

    static func make(
        for workspace: WorkspaceSummary,
        foregroundProcessSurfaces: Set<UUID>
    ) -> CloseWorkspaceConfirmation {
        CloseWorkspaceConfirmation(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            rows: workspace.tabs
                .flatMap(\.panes)
                .filter { isBusy($0.state) || foregroundProcessSurfaces.contains($0.id) }
                .map {
                    Row(
                        id: $0.id,
                        title: $0.label,
                        state: $0.state,
                        hasForegroundProcess: foregroundProcessSurfaces.contains($0.id))
                }
        )
    }

    static func resolve(
        workspaceID: UUID,
        in snapshot: WorkspaceOverlaySnapshot,
        foregroundProcessSurfaces: Set<UUID>
    ) -> CloseWorkspaceConfirmation? {
        guard let workspace = snapshot.workspace(id: workspaceID), !workspace.isDefault else { return nil }
        return make(for: workspace, foregroundProcessSurfaces: foregroundProcessSurfaces)
    }
}

struct CloseWorkspaceConfirmationView: View {
    let confirmation: CloseWorkspaceConfirmation
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Workspace \(confirmation.workspaceName)")
                .font(.system(size: 11))
                .foregroundColor(WorkspaceOverlayPalette.secondaryText)
                .lineLimit(1)
                .padding(.bottom, 2)

            Text(confirmation.headline)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(WorkspaceOverlayPalette.strongText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(confirmation.rows) { row in
                        HStack(spacing: 10) {
                            StatusIndicatorView(
                                state: row.state,
                                diameter: 16,
                                badgeText: StatusIndicatorView.badgeText(for: row.state, context: .tab, runningCount: 1)
                            )
                            Text("\(row.title) · \(row.suffix)")
                                .font(.system(size: 12.5))
                                .foregroundColor(WorkspaceOverlayPalette.menuText)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 14)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .buttonStyle(WorkspaceOverlayButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Close", action: onConfirm)
                    .buttonStyle(WorkspaceOverlayButtonStyle(kind: .primary))
            }
        }
        .frame(width: 302, alignment: .leading)
        .workspaceOverlayPanel(padding: 14, shadowOpacity: 0.65, shadowRadius: 16, shadowY: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm closing workspace \(confirmation.workspaceName)")
        .accessibilityAddTraits(.isModal)
    }
}
