import SwiftUI

struct WorkspaceTitlebarPalette {
    let barBackground: Color
    let barBorder: Color
    let activePill: Color
    let hoverPill: Color
    let hoverButton: Color
    let primaryText: Color
    let secondaryText: Color
    let hoverText: Color
    let menuText: Color
    let mutedText: Color
    let rowHover: Color
    let separator: Color
    let renameBackground: Color
    let renameBorder: Color
    let badgeHoverBackground: Color

    init(colorScheme: ColorScheme) {
        func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
            WorkspaceStatusColors.color(hex: value, opacity: opacity)
        }

        badgeHoverBackground = hex(0x4A4A4A)

        switch colorScheme {
        case .dark:
            barBackground = hex(0x232323)
            barBorder = hex(0xFFFFFF, 0.06)
            activePill = hex(0x3A3A3A)
            hoverPill = hex(0xFFFFFF, 0.04)
            hoverButton = hex(0x2A2A2A)
            primaryText = hex(0xFFFFFF)
            secondaryText = hex(0x8C8C8C)
            hoverText = hex(0xBDBDBD)
            menuText = hex(0xD0D0D0)
            mutedText = hex(0x8C8C8C)
            rowHover = hex(0xFFFFFF, 0.07)
            separator = hex(0x3A3A3A)
            renameBackground = hex(0x0F0F0F)
            renameBorder = hex(0xFFFFFF, 0.28)
        default:
            barBackground = hex(0xE9E9E9)
            barBorder = hex(0x000000, 0.08)
            activePill = hex(0x000000, 0.12)
            hoverPill = hex(0x000000, 0.05)
            hoverButton = hex(0x000000, 0.08)
            primaryText = hex(0x1A1A1A)
            secondaryText = hex(0x6E6E6E)
            hoverText = hex(0x3C3C3C)
            menuText = hex(0x2A2A2A)
            mutedText = hex(0x6E6E6E)
            rowHover = hex(0x000000, 0.07)
            separator = hex(0x000000, 0.12)
            renameBackground = hex(0xFFFFFF)
            renameBorder = hex(0x000000, 0.28)
        }
    }
}

private struct WorkspaceTitleFontFamilyKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var workspaceTitleFontFamily: String? {
        get { self[WorkspaceTitleFontFamilyKey.self] }
        set { self[WorkspaceTitleFontFamilyKey.self] = newValue }
    }
}

enum WorkspaceTitlebarFont {
    static func font(size: CGFloat, weight: Font.Weight = .regular, family: String?) -> Font {
        if let family, !family.isEmpty {
            return Font.custom(family, size: size).weight(weight)
        }
        return Font.system(size: size, weight: weight)
    }

    static func mono(size: CGFloat) -> Font {
        Font.system(size: size, design: .monospaced)
    }
}

struct WorkspaceTitlebarFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight

    @Environment(\.workspaceTitleFontFamily) private var family

    func body(content: Content) -> some View {
        content.font(WorkspaceTitlebarFont.font(size: size, weight: weight, family: family))
    }
}

extension View {
    func workspaceTitlebarFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(WorkspaceTitlebarFontModifier(size: size, weight: weight))
    }
}

struct WorkspaceTitlebarView: View {
    static let trailingInset: CGFloat = 8

    @ObservedObject var viewModel: WorkspaceTitlebarViewModel
    @ObservedObject var metrics: WorkspaceTitlebarMetrics

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WorkspaceTitlebarPalette(colorScheme: colorScheme)

        HStack(spacing: 8) {
            WorkspaceMenuButton(viewModel: viewModel)
            WorkspaceTabBar(viewModel: viewModel)
                .padding(.trailing, 6)
            ActivityBadgeView(
                runningCount: viewModel.badge.runningCount,
                needsAttention: viewModel.badge.needsAttention,
                isOpen: viewModel.isOverviewOpen,
                onTap: { viewModel.badgeTapped() },
                onHoverChanged: { viewModel.badgeHoverChanged($0) }
            )
        }
        .padding(.leading, metrics.leadingInset)
        .padding(.trailing, Self.trailingInset)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.height)
        .background(palette.barBackground)
        .overlay(alignment: .bottom) {
            palette.barBorder.frame(height: 1)
        }
        .environment(\.workspaceTitleFontFamily, viewModel.fontFamily)
    }
}
