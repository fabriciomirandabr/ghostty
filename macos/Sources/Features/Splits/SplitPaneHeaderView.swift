import Combine
import SwiftUI

struct SplitPaneHeaderPalette: Equatable {
    let background: Color
    let activeBackground: Color
    let text: Color
    let activeText: Color
    let activeLine: Color
    let bottomLine: Color
    let closeText: Color
    let closeHoverBackground: Color
    let closeHoverText: Color

    init(colorScheme: ColorScheme) {
        func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
            WorkspaceStatusColors.color(hex: value, opacity: opacity)
        }

        switch colorScheme {
        case .dark:
            background = hex(0x171717)
            activeBackground = hex(0x202020)
            text = hex(0x8C8C8C)
            activeText = hex(0xF2F2F2)
            activeLine = hex(0xFFFFFF, 0.28)
            bottomLine = hex(0x2A2A2A)
            closeText = hex(0xB4B4B4)
            closeHoverBackground = hex(0xFFFFFF, 0.12)
            closeHoverText = hex(0xFFFFFF)
        default:
            background = hex(0xEDEDED)
            activeBackground = hex(0xF7F7F7)
            text = hex(0x6E6E6E)
            activeText = hex(0x1A1A1A)
            activeLine = hex(0x000000, 0.28)
            bottomLine = hex(0x000000, 0.1)
            closeText = hex(0x4A4A4A)
            closeHoverBackground = hex(0x000000, 0.1)
            closeHoverText = hex(0x000000)
        }
    }
}

enum SplitPaneHeader {
    static func isVisible(
        isSplit: Bool,
        windowDecorations: Bool,
        style: Ghostty.Config.MacOSTitlebarStyle
    ) -> Bool {
        isSplit && WorkspaceWindowPolicy.usesWorkspaceWindow(
            windowDecorations: windowDecorations,
            style: style)
    }
}

struct SplitPaneHeaderView: View {
    static let height: CGFloat = 24

    let title: String
    let isActive: Bool
    let onClose: () -> Void

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = SplitPaneHeaderPalette(colorScheme: colorScheme)

        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(isActive ? palette.activeText : palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            CloseButton(palette: palette, onClose: onClose)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(isActive ? palette.activeBackground : palette.background)
        .overlay(alignment: .top) {
            if isActive {
                palette.activeLine.frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            palette.bottomLine.frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pane \(title)")
    }

    private struct CloseButton: View {
        let palette: SplitPaneHeaderPalette
        let onClose: () -> Void

        @State private var isHovering = false

        var body: some View {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isHovering ? palette.closeHoverText : palette.closeText)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(isHovering ? palette.closeHoverBackground : .clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel("Close pane")
        }
    }
}

struct SplitPaneHeaderHost: View {
    let surfaceView: Ghostty.SurfaceView
    let isActive: Bool
    let onClose: () -> Void

    @State private var title: String

    init(surfaceView: Ghostty.SurfaceView, isActive: Bool, onClose: @escaping () -> Void) {
        self.surfaceView = surfaceView
        self.isActive = isActive
        self.onClose = onClose
        _title = State(initialValue: surfaceView.title)
    }

    var body: some View {
        SplitPaneHeaderView(title: title, isActive: isActive, onClose: onClose)
            .onReceive(surfaceView.$title.removeDuplicates()) { title = $0 }
    }
}
