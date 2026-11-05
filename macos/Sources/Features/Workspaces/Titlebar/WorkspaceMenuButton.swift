import SwiftUI

struct WorkspaceMenuButton: View {
    static let height: CGFloat = 30
    static let maxWidth: CGFloat = 240
    static let horizontalPadding: CGFloat = 10
    static let itemSpacing: CGFloat = 6

    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WorkspaceTitlebarPalette(colorScheme: colorScheme)

        Button {
            viewModel.toggleMenu()
        } label: {
            HStack(spacing: Self.itemSpacing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(viewModel.activeWorkspaceName)
                    .workspaceTitlebarFont(size: 13, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(palette.primaryText)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(maxWidth: Self.maxWidth)
            .frame(height: Self.height)
            .fixedSize(horizontal: true, vertical: false)
            .background(Capsule().fill(background(palette: palette)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .layoutPriority(2)
        .accessibilityLabel("Workspaces")
        .accessibilityValue(viewModel.activeWorkspaceName)
    }

    private func background(palette: WorkspaceTitlebarPalette) -> Color {
        if viewModel.isMenuPresented { return palette.activePill }
        return isHovering ? palette.hoverButton : .clear
    }
}
