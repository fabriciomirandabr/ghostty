import SwiftUI

enum WorkspaceStatusColors {
    static let needsAttentionHex: UInt32 = 0xF5D90A
    static let badgeDotHex: UInt32 = 0xFF7A1A
    static let badgeDarkHex: UInt32 = 0x3A3A3A
    static let badgeLightHex: UInt32 = 0xFFFFFF
    static let badgeInkHex: UInt32 = 0x111111

    static func color(hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct WorkspaceBadgeStyle: Equatable {
    let fillHex: UInt32
    let foregroundHex: UInt32

    static func make(for state: SurfaceActivityState, colorScheme: ColorScheme = .dark) -> WorkspaceBadgeStyle {
        switch state {
        case .idle:
            WorkspaceBadgeStyle(fillHex: WorkspaceStatusColors.badgeDarkHex, foregroundHex: WorkspaceStatusColors.badgeLightHex)
        case .running, .done:
            if colorScheme == .dark {
                WorkspaceBadgeStyle(fillHex: WorkspaceStatusColors.badgeLightHex, foregroundHex: WorkspaceStatusColors.badgeInkHex)
            } else {
                WorkspaceBadgeStyle(fillHex: WorkspaceStatusColors.badgeDarkHex, foregroundHex: WorkspaceStatusColors.badgeLightHex)
            }
        case .needsAttention:
            WorkspaceBadgeStyle(fillHex: WorkspaceStatusColors.needsAttentionHex, foregroundHex: WorkspaceStatusColors.badgeInkHex)
        }
    }

    var fill: Color { WorkspaceStatusColors.color(hex: fillHex) }
    var foreground: Color { WorkspaceStatusColors.color(hex: foregroundHex) }
}

struct StatusIndicatorView: View {
    let state: SurfaceActivityState
    var diameter: CGFloat = 14
    var badgeText: String?

    @Environment(\.colorScheme) private var colorScheme

    static func accessibilityLabel(for state: SurfaceActivityState) -> String {
        switch state {
        case .idle: "Idle"
        case .done: "Done"
        case .running: "Running"
        case .needsAttention: "Needs you"
        }
    }

    static func badgeText(for state: SurfaceActivityState, runningCount: Int) -> String? {
        state == .running && runningCount > 0 ? "\(runningCount)" : nil
    }

    var body: some View {
        let badge = WorkspaceBadgeStyle.make(for: state, colorScheme: colorScheme)
        ZStack {
            Circle().fill(badge.fill)
            if state == .done {
                CheckGlyph()
                    .stroke(badge.foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
            } else if let badgeText {
                Text(badgeText)
                    .font(.system(size: diameter * 0.56, weight: .semibold))
                    .foregroundColor(badge.foreground)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: state))
    }
}

struct CheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(20, 6))
        path.addLine(to: point(9, 17))
        path.addLine(to: point(4, 12))
        return path
    }
}
