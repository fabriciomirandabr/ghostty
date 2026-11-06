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

            SplitTerminalButton(viewModel: viewModel)
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

private struct SplitTerminalButton: View {
    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WorkspaceTitlebarPalette(colorScheme: colorScheme)

        Button {
            let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
            viewModel.splitTerminal(SplitTerminalDirection(modifiers: modifiers))
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(palette.primaryText)
                .frame(width: NewTabButton.size, height: NewTabButton.size)
                .background(Circle().fill(isHovering && viewModel.canSplit ? palette.hoverButton : .clear))
                .contentShape(Circle())
                .opacity(viewModel.canSplit ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSplit)
        .onHover { isHovering = $0 }
        .help(viewModel.splitTerminalTooltip)
        .accessibilityLabel(viewModel.splitTerminalTooltip)
    }
}
