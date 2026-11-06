import SwiftUI

struct WorkspaceMenuView: View {
    static let minWidth: CGFloat = 260
    static let maxWidth: CGFloat = 320
    static let rowRadius: CGFloat = 8
    static let rowHeight: CGFloat = 28
    static let panelPadding: CGFloat = 6
    static let separatorMargin: CGFloat = 6

    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WorkspaceTitlebarPalette(colorScheme: colorScheme)

        VStack(spacing: 0) {
            ForEach(viewModel.menuItems) { item in
                switch item.kind {
                case .separator:
                    palette.separator
                        .frame(height: 1)
                        .padding(.vertical, Self.separatorMargin)

                case .workspace:
                    WorkspaceMenuWorkspaceRow(item: item, palette: palette, viewModel: viewModel)

                case .fontSize:
                    WorkspaceMenuActionRow(
                        item: item,
                        palette: palette,
                        trailing: viewModel.currentFontSize.map { "\($0) pt" },
                        viewModel: viewModel
                    )
                    if viewModel.isFontSizeExpanded {
                        ForEach(viewModel.fontSizeOptions) { option in
                            WorkspaceMenuFontSizeRow(option: option, palette: palette, viewModel: viewModel)
                        }
                    }

                default:
                    WorkspaceMenuActionRow(
                        item: item,
                        palette: palette,
                        trailing: item.shortcut,
                        viewModel: viewModel
                    )
                }
            }
        }
        .padding(Self.panelPadding)
        .frame(minWidth: Self.minWidth, maxWidth: Self.maxWidth)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces")
    }
}

private struct MenuRowChrome: ViewModifier {
    let isEnabled: Bool
    let palette: WorkspaceTitlebarPalette
    @Binding var isHovering: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(height: WorkspaceMenuView.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: WorkspaceMenuView.rowRadius, style: .continuous)
                    .fill(isEnabled && isHovering ? palette.rowHover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: WorkspaceMenuView.rowRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovering = $0 }
    }
}

private struct ActiveMark: View {
    let isActive: Bool
    let palette: WorkspaceTitlebarPalette

    var body: some View {
        Text(isActive ? "●" : "")
            .font(.system(size: 8))
            .foregroundColor(palette.primaryText)
            .frame(width: 10)
            .accessibilityHidden(true)
    }
}

private struct WorkspaceMenuWorkspaceRow: View {
    let item: WorkspaceMenuItem
    let palette: WorkspaceTitlebarPalette
    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            StatusIndicatorView(
                state: item.state,
                diameter: 14,
                badgeText: StatusIndicatorView.badgeText(for: item.state, runningCount: item.runningCount)
            )

            Text(item.title)
                .workspaceTitlebarFont(size: 12.5, weight: item.isActive ? .semibold : .regular)
                .foregroundColor(isHovering || item.isActive ? palette.primaryText : palette.menuText)
                .lineLimit(1)
                .layoutPriority(2)

            if let runningLabel = item.runningLabel {
                Text(runningLabel)
                    .workspaceTitlebarFont(size: 11)
                    .foregroundColor(palette.mutedText)
                    .lineLimit(1)
                    .fixedSize()
            }

            if let folder = item.folder {
                Text(folder)
                    .font(WorkspaceTitlebarFont.mono(size: 11))
                    .foregroundColor(palette.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            trailing
        }
        .modifier(MenuRowChrome(isEnabled: item.isEnabled, palette: palette, isHovering: $isHovering))
        .onTapGesture { viewModel.perform(item) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { viewModel.perform(item) }
    }

    private var closesOnHover: Bool {
        item.showsClose && isHovering
    }

    private var trailing: some View {
        ZStack(alignment: .trailing) {
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(WorkspaceTitlebarFont.mono(size: 11))
                    .foregroundColor(palette.mutedText)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(closesOnHover ? 0 : 1)
            }

            if item.showsClose {
                CloseGlyphButton(
                    size: 20,
                    normal: palette.menuText,
                    hoverBackground: palette.hoverButton,
                    hoverForeground: palette.primaryText,
                    accessibilityLabel: "Close workspace \(item.title)",
                    action: {
                        if case .workspace(let id) = item.kind { viewModel.closeWorkspace(id: id) }
                    }
                )
                .opacity(closesOnHover ? 1 : 0)
                .allowsHitTesting(closesOnHover)
            }
        }
    }
}

private struct WorkspaceMenuActionRow: View {
    let item: WorkspaceMenuItem
    let palette: WorkspaceTitlebarPalette
    let trailing: String?
    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(item.title)
                .workspaceTitlebarFont(size: 12.5)
                .foregroundColor(isHovering && item.isEnabled ? palette.primaryText : palette.menuText)
                .lineLimit(1)

            Spacer(minLength: 12)

            if let trailing {
                Text(trailing)
                    .font(WorkspaceTitlebarFont.mono(size: 11))
                    .foregroundColor(palette.mutedText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .modifier(MenuRowChrome(isEnabled: item.isEnabled, palette: palette, isHovering: $isHovering))
        .onTapGesture { viewModel.perform(item) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(trailing ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { viewModel.perform(item) }
    }
}

private struct WorkspaceMenuFontSizeRow: View {
    let option: WorkspaceFontSizeOption
    let palette: WorkspaceTitlebarPalette
    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ActiveMark(isActive: option.isCurrent, palette: palette)

            Text("\(option.size)")
                .workspaceTitlebarFont(size: 12.5)
                .foregroundColor(isHovering ? palette.primaryText : palette.menuText)

            Spacer(minLength: 12)

            Text("\(option.size) pt")
                .font(WorkspaceTitlebarFont.mono(size: 11))
                .foregroundColor(palette.mutedText)
        }
        .padding(.leading, 16)
        .modifier(MenuRowChrome(isEnabled: true, palette: palette, isHovering: $isHovering))
        .onTapGesture { viewModel.chooseFontSize(option.size) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Font size \(option.size)")
        .accessibilityAddTraits(option.isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { viewModel.chooseFontSize(option.size) }
    }
}
