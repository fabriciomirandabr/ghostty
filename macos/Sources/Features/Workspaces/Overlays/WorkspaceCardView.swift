import SwiftUI

struct WorkspaceStateBadge: View {
    let state: SurfaceActivityState
    var runningCount = 0

    var body: some View {
        if let label = WorkspaceStateText.badge(state) {
            HStack(spacing: 6) {
                if state == .running {
                    StatusIndicatorView(
                        state: .running,
                        diameter: 18,
                        badgeText: StatusIndicatorView.badgeText(for: .running, context: .workspace, runningCount: runningCount)
                    )
                }
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundColor(foreground)
            .padding(.leading, state == .running ? 0 : 10)
            .padding(.trailing, 10)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.rowRadius, style: .continuous)
                    .fill(background)
            )
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
    }

    private var background: Color {
        switch state {
        case .needsAttention: return WorkspaceOverlayPalette.needsAttention
        case .done: return WorkspaceOverlayPalette.doneBadgeBackground
        case .running, .idle: return Color.clear
        }
    }

    private var foreground: Color {
        switch state {
        case .running: return WorkspaceOverlayPalette.primaryText
        case .needsAttention: return WorkspaceOverlayPalette.badgeInk
        case .done: return WorkspaceOverlayPalette.doneBadgeInk
        case .idle: return Color.clear
        }
    }
}

struct WorkspaceCloseButton: View {
    var accessibilityLabel: String
    var size: CGFloat = 22
    var background: Color = Color.clear
    var border: Color = Color.clear
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(hovering ? WorkspaceOverlayPalette.strongText : WorkspaceOverlayPalette.menuText)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .overlay(Circle().strokeBorder(border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

struct WorkspaceCardView: View {
    static let height: CGFloat = 300

    let workspace: WorkspaceSummary
    let thumbnails: WorkspaceThumbnailSource
    var terminalBackground: Color
    var terminalForeground: Color
    var onSelect: () -> Void
    var onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 12) {
            WorkspaceThumbnailView(
                tabID: workspace.selectedTabID,
                source: thumbnails,
                background: terminalBackground,
                foreground: terminalForeground
            )
            footer
        }
        .padding(12)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.cardRadius, style: .continuous)
                .fill(WorkspaceOverlayPalette.card)
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.cardRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if !workspace.isDefault {
                WorkspaceCloseButton(
                    accessibilityLabel: "Close workspace \(workspace.name)",
                    background: WorkspaceOverlayPalette.closeButtonBackground,
                    border: WorkspaceOverlayPalette.panelBorder,
                    action: onClose
                )
                .padding(.top, 20)
                .padding(.trailing, 20)
                .opacity(hovering ? 1 : 0)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.cardRadius, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: borderColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open workspace \(workspace.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onSelect)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            WorkspaceStateBadge(state: workspace.state, runningCount: workspace.runningPaneCount)

            Text(workspace.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(WorkspaceOverlayPalette.primaryText)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 0)

            Text(WorkspaceFolderLabel.abbreviated(workspace.directory))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(WorkspaceOverlayPalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: 24)
    }

    var borderColor: Color {
        if workspace.isCurrent { return WorkspaceOverlayPalette.currentBorder }
        switch workspace.state {
        case .needsAttention: return WorkspaceOverlayPalette.needsAttention
        case .running, .done, .idle: return hovering ? WorkspaceOverlayPalette.cardHoverBorder : WorkspaceOverlayPalette.cardBorder
        }
    }
}

struct NewWorkspaceCardView: View {
    var onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 56, weight: .ultraLight))
            Text("New workspace")
                .font(.system(size: 12))
        }
        .foregroundColor(hovering ? WorkspaceOverlayPalette.strongText : WorkspaceOverlayPalette.secondaryText)
        .frame(maxWidth: .infinity)
        .frame(height: WorkspaceCardView.height)
        .overlay(
            RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.cardRadius, style: .continuous)
                .strokeBorder(
                    hovering ? WorkspaceOverlayPalette.dashedHoverBorder : WorkspaceOverlayPalette.dashedBorder,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.cardRadius, style: .continuous))
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New workspace")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onSelect)
    }
}
