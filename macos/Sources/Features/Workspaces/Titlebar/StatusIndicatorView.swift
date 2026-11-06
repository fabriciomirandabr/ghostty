import SwiftUI

enum WorkspaceStatusColors {
    static let needsAttentionHex: UInt32 = 0xF5D90A
    static let needsAttentionLightHex: UInt32 = 0x8A5A00
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
        let isDark = colorScheme == .dark
        let fillHex = isDark ? WorkspaceStatusColors.badgeDarkHex : WorkspaceStatusColors.badgeLightHex
        let textHex = isDark ? WorkspaceStatusColors.badgeLightHex : WorkspaceStatusColors.badgeInkHex
        switch state {
        case .idle, .running, .done:
            return WorkspaceBadgeStyle(fillHex: fillHex, foregroundHex: textHex)
        case .needsAttention:
            return WorkspaceBadgeStyle(
                fillHex: fillHex,
                foregroundHex: isDark ? WorkspaceStatusColors.needsAttentionHex : WorkspaceStatusColors.needsAttentionLightHex
            )
        }
    }

    var fill: Color { WorkspaceStatusColors.color(hex: fillHex) }
    var foreground: Color { WorkspaceStatusColors.color(hex: foregroundHex) }
}

enum WorkspaceBadgeContext {
    case workspace
    case tab
}

extension WorkspaceBadgeStyle {
    static let ringLineWidth: CGFloat = 1.5
    static let ringOpacity: Double = 0.6

    static func showsRing(for state: SurfaceActivityState) -> Bool {
        state == .running || state == .needsAttention
    }
}

struct BadgeRing: View {
    let color: Color
    let diameter: CGFloat

    var body: some View {
        Circle()
            .stroke(color.opacity(WorkspaceBadgeStyle.ringOpacity), lineWidth: WorkspaceBadgeStyle.ringLineWidth)
            .frame(width: diameter + 5, height: diameter + 5)
            .allowsHitTesting(false)
    }
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

    static func badgeText(
        for state: SurfaceActivityState,
        context: WorkspaceBadgeContext,
        runningCount: Int
    ) -> String? {
        switch context {
        case .tab: state == .running && runningCount >= 2 ? "\(runningCount)" : nil
        case .workspace: (state == .running || state == .needsAttention) && runningCount > 0 ? "\(runningCount)" : nil
        }
    }

    var body: some View {
        let badge = WorkspaceBadgeStyle.make(for: state, colorScheme: colorScheme)
        ZStack {
            Circle().fill(badge.fill)
            if state == .done {
                CheckGlyph()
                    .stroke(badge.foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
            } else if state == .needsAttention && badgeText == nil {
                Circle()
                    .fill(badge.foreground)
                    .frame(width: diameter * 0.36, height: diameter * 0.36)
            } else if let badgeText {
                Text(badgeText)
                    .font(.system(size: diameter * 0.56, weight: .semibold))
                    .foregroundColor(badge.foreground)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            if WorkspaceBadgeStyle.showsRing(for: state) {
                BadgeRing(color: badge.foreground, diameter: diameter)
            }
        }
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
