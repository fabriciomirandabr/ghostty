import AppKit
import SwiftUI

enum WorkspaceOverlayMetrics {
    static let panelRadius: CGFloat = 12
    static let rowRadius: CGFloat = 8
    static let cardRadius: CGFloat = 8
    static let panelInset: CGFloat = 6
}

enum WorkspaceOverlayPalette {
    static let needsAttention = fixed(0xf5d90a)
    static let badgeInk = fixed(0x111111)

    static let overviewBackground = adaptive(dark: 0x141414, light: 0xf2f2f2)
    static let panel = adaptive(dark: 0x262626, light: 0xfcfcfc)
    static let panelBorder = adaptive(dark: 0x3d3d3d, light: 0xcfcfcf)
    static let separator = adaptive(dark: 0x3a3a3a, light: 0xdddddd)
    static let card = adaptive(dark: 0x1c1c1c, light: 0xffffff)
    static let cardBorder = adaptive(dark: 0x2a2a2a, light: 0xdadada)
    static let cardHoverBorder = adaptive(dark: 0x5a5a5a, light: 0xa6a6a6)
    static let currentBorder = adaptive(dark: 0xd4d4d4, light: 0x3a3a3a)
    static let thumbnailBorder = adaptive(dark: 0x2a2a2a, light: 0xdadada)
    static let dashedBorder = adaptive(dark: 0x3a3a3a, light: 0xc4c4c4)
    static let dashedHoverBorder = adaptive(dark: 0x8a8a8a, light: 0x6a6a6a)

    static let primaryText = adaptive(dark: 0xf2f2f2, light: 0x1a1a1a)
    static let strongText = adaptive(dark: 0xffffff, light: 0x000000)
    static let secondaryText = adaptive(dark: 0x8c8c8c, light: 0x6b6b6b)
    static let menuText = adaptive(dark: 0xd0d0d0, light: 0x333333)
    static let hint = adaptive(dark: 0x9a9a9a, light: 0x6b6b6b)

    static let fieldBackground = adaptive(dark: 0x1b1b1b, light: 0xffffff)
    static let fieldBorder = adaptive(dark: 0x444444, light: 0xc4c4c4)
    static let fieldFocusBorder = adaptive(dark: 0x9a9a9a, light: 0x6a6a6a)

    static let rowHover = adaptive(dark: NSColor(white: 1, alpha: 0.07), light: NSColor(white: 0, alpha: 0.06))
    static let rowSelected = adaptive(dark: NSColor(white: 1, alpha: 0.10), light: NSColor(white: 0, alpha: 0.09))
    static let footerHover = adaptive(dark: NSColor(white: 1, alpha: 0.05), light: NSColor(white: 0, alpha: 0.05))
    static let closeButtonBackground = adaptive(
        dark: NSColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 0.85),
        light: NSColor(white: 1, alpha: 0.9)
    )

    static let primaryButtonBackground = adaptive(dark: 0xe8e8e8, light: 0x1a1a1a)
    static let primaryButtonInk = adaptive(dark: 0x141414, light: 0xffffff)

    static let doneBadgeBackground = adaptive(dark: 0xffffff, light: 0x1a1a1a)
    static let doneBadgeInk = adaptive(dark: 0x111111, light: 0xffffff)

    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }

    private static func fixed(_ hex: UInt32) -> Color {
        Color(nsColor: rgb(hex))
    }

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        adaptive(dark: rgb(dark), light: rgb(light))
    }

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

struct WorkspaceOverlayPanelStyle: ViewModifier {
    var padding: CGFloat = WorkspaceOverlayMetrics.panelInset
    var shadowOpacity: Double = 0.6
    var shadowRadius: CGFloat = 18
    var shadowY: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.panelRadius, style: .continuous)
                    .fill(WorkspaceOverlayPalette.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.panelRadius, style: .continuous)
                    .strokeBorder(WorkspaceOverlayPalette.panelBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    func workspaceOverlayPanel(
        padding: CGFloat = WorkspaceOverlayMetrics.panelInset,
        shadowOpacity: Double = 0.6,
        shadowRadius: CGFloat = 18,
        shadowY: CGFloat = 12
    ) -> some View {
        modifier(WorkspaceOverlayPanelStyle(
            padding: padding,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }
}

struct WorkspaceOverlayButtonStyle: ButtonStyle {
    enum Kind {
        case secondary
        case primary
    }

    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: kind == .primary ? .semibold : .regular))
            .foregroundColor(kind == .primary ? WorkspaceOverlayPalette.primaryButtonInk : WorkspaceOverlayPalette.menuText)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.rowRadius, style: .continuous)
                    .fill(background(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.rowRadius, style: .continuous)
                    .strokeBorder(kind == .primary ? Color.clear : WorkspaceOverlayPalette.fieldBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary:
            return WorkspaceOverlayPalette.primaryButtonBackground.opacity(pressed ? 0.85 : 1)
        case .secondary:
            return pressed ? WorkspaceOverlayPalette.rowHover : Color.clear
        }
    }
}

struct WorkspaceOverlayRowBackground: View {
    var isHighlighted: Bool
    var highlight: Color = WorkspaceOverlayPalette.rowHover

    var body: some View {
        RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.rowRadius, style: .continuous)
            .fill(isHighlighted ? highlight : Color.clear)
    }
}

enum WorkspaceStateText {
    static func badge(_ state: SurfaceActivityState) -> String? {
        switch state {
        case .idle: return nil
        case .done: return "Done"
        case .running: return "Running"
        case .needsAttention: return "Needs you"
        }
    }

    static func rowSuffix(_ state: SurfaceActivityState) -> String {
        switch state {
        case .idle: return "idle"
        case .done: return "done"
        case .running: return "running"
        case .needsAttention: return "needs you"
        }
    }

    static func accessibilityLabel(_ state: SurfaceActivityState) -> String {
        switch state {
        case .idle: return "Idle"
        case .done: return "Done"
        case .running: return "Running"
        case .needsAttention: return "Needs attention"
        }
    }
}
