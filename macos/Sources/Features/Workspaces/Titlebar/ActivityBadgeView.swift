import SwiftUI

struct ActivityBadgeView: View {
    static let size: CGFloat = 28
    static let maxDisplayedCount = 99

    let runningCount: Int
    let needsAttention: Bool
    let isOpen: Bool
    var onTap: () -> Void = {}
    var onHoverChanged: (Bool) -> Void = { _ in }

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    static func accessibilityLabel(runningCount: Int, needsAttention: Bool) -> String {
        let base = showsGrid(runningCount: runningCount) ? "Workspaces" : "Workspaces overview: \(runningCount) running"
        return needsAttention ? base + ", attention needed" : base
    }

    static func showsGrid(runningCount: Int) -> Bool {
        runningCount <= 0
    }

    static func displayText(runningCount: Int) -> String {
        runningCount > maxDisplayedCount ? "\(maxDisplayedCount)+" : "\(runningCount)"
    }

    static func badgeStyle(runningCount: Int, colorScheme: ColorScheme = .dark) -> WorkspaceBadgeStyle {
        WorkspaceBadgeStyle.make(for: showsGrid(runningCount: runningCount) ? .idle : .running, colorScheme: colorScheme)
    }

    var body: some View {
        let palette = WorkspaceTitlebarPalette(colorScheme: colorScheme)
        let style = Self.badgeStyle(runningCount: runningCount, colorScheme: colorScheme)
        let highlighted = (isHovering || isOpen) && Self.showsGrid(runningCount: runningCount)

        Button(action: onTap) {
            badgeContent(style: style)
                .frame(width: Self.size, height: Self.size)
                .background(
                    Circle().fill(highlighted ? palette.badgeHoverBackground : style.fill)
                )
                .overlay(alignment: .topTrailing) {
                    if needsAttention {
                        Circle()
                            .fill(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.badgeDotHex))
                            .frame(width: 8, height: 8)
                            .padding(2)
                            .background(Circle().fill(palette.barBackground))
                            .offset(x: 2, y: -2)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            onHoverChanged(hovering)
        }
        .accessibilityLabel(Self.accessibilityLabel(runningCount: runningCount, needsAttention: needsAttention))
    }

    @ViewBuilder
    private func badgeContent(style: WorkspaceBadgeStyle) -> some View {
        if Self.showsGrid(runningCount: runningCount) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(style.foreground.opacity(0.6))
        } else {
            Text(Self.displayText(runningCount: runningCount))
                .workspaceTitlebarFont(size: 12, weight: .semibold)
                .foregroundColor(style.foreground)
        }
    }
}
