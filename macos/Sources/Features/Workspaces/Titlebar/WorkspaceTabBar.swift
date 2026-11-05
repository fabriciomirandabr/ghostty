import SwiftUI

struct WorkspaceTabBar: View {
    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.tabs) { tab in
                WorkspaceTabPill(
                    tab: tab,
                    isSelected: tab.id == viewModel.selectedTabID,
                    viewModel: viewModel
                )
            }

            NewTabButton(viewModel: viewModel)
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .frame(height: WorkspaceTabPill.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace terminals")
    }
}

private struct NewTabButton: View {
    static let size: CGFloat = 28

    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WorkspaceTitlebarPalette(colorScheme: colorScheme)

        Button {
            viewModel.newTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(palette.primaryText)
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(isHovering ? palette.hoverButton : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("New Terminal")
    }
}
