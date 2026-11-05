import SwiftUI

struct ActivityBadgeView: View {
    static let size: CGFloat = 28
    static let cornerRadius: CGFloat = 8
    static let ringSize: CGFloat = 22
    static let maxDisplayedCount = 99

    let runningCount: Int
    let needsAttention: Bool
    let isOpen: Bool
    var onTap: () -> Void = {}
    var onHoverChanged: (Bool) -> Void = { _ in }

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    var body: some View {
        let palette = WorkspaceTitlebarPalette(colorScheme: colorScheme)

        Button(action: onTap) {
            badgeContent(palette: palette)
                .frame(width: Self.size, height: Self.size)
                .background(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(isHovering || isOpen ? palette.badgeHoverBackground : palette.badgeBackground)
                )
                .overlay {
                    if runningCount > 0 {
                        ProcessingRing(color: palette.badgeRing, isAnimated: !reduceMotion)
                            .frame(width: Self.ringSize, height: Self.ringSize)
                            .allowsHitTesting(false)
                    }
                }
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
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            onHoverChanged(hovering)
        }
        .accessibilityLabel(Self.accessibilityLabel(runningCount: runningCount, needsAttention: needsAttention))
    }

    @ViewBuilder
    private func badgeContent(palette: WorkspaceTitlebarPalette) -> some View {
        if Self.showsGrid(runningCount: runningCount) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(palette.badgeText.opacity(0.6))
        } else {
            Text(Self.displayText(runningCount: runningCount))
                .workspaceTitlebarFont(size: 12, weight: .semibold)
                .foregroundColor(palette.badgeText)
        }
    }
}

private struct ProcessingRing: View {
    let color: Color
    let isAnimated: Bool

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.625, to: 0.875)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
            Circle()
                .trim(from: 0.875, to: 1)
                .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
            Circle()
                .trim(from: 0, to: 0.125)
                .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
        }
        .padding(0.75)
        .modifier(Spinning(period: 1, isActive: isAnimated))
    }
}
