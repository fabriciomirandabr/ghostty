import SwiftUI

struct WorkspaceTabPill: View {
    static let height: CGFloat = 30
    static let maxWidth: CGFloat = 240
    static let minWidth: CGFloat = 48
    static let horizontalPadding: CGFloat = 6
    static let indicatorSize: CGFloat = 20
    static let badgeSize: CGFloat = 14
    static let itemSpacing: CGFloat = 8
    static let closeSize: CGFloat = 20

    let tab: WorkspaceTitlebarTab
    let isSelected: Bool
    @ObservedObject var viewModel: WorkspaceTitlebarViewModel

    @State private var isHovering = false
    @State private var naturalWidth: CGFloat = 0
    @State private var visibleWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    static func isTruncated(naturalWidth: CGFloat, visibleWidth: CGFloat) -> Bool {
        naturalWidth > visibleWidth + 0.5
    }

    private var isRenaming: Bool {
        viewModel.renamingTabID == tab.id
    }

    var body: some View {
        let palette = WorkspaceTitlebarPalette(colorScheme: colorScheme)

        HStack(spacing: 0) {
            StatusIndicatorView(
                state: tab.state,
                diameter: Self.badgeSize,
                badgeText: StatusIndicatorView.badgeText(for: tab.state, context: .tab, runningCount: 1)
            )
            .frame(width: Self.indicatorSize, height: Self.indicatorSize)

            HStack(spacing: 0) {
                titleText(palette: palette)
                    .padding(.leading, Self.itemSpacing)
                closeButton(palette: palette)
                    .padding(.leading, Self.itemSpacing)
            }
            .opacity(isRenaming ? 0 : 1)
            .allowsHitTesting(!isRenaming)
            .accessibilityHidden(isRenaming)
            .overlay {
                if isRenaming {
                    RenameField(viewModel: viewModel, palette: palette)
                        .padding(.leading, Self.itemSpacing)
                }
            }
        }
        .padding(.leading, Self.horizontalPadding)
        .padding(.trailing, Self.horizontalPadding)
        .frame(minWidth: Self.minWidth, maxWidth: Self.maxWidth)
        .frame(height: Self.height)
        .background(Capsule().fill(background(palette: palette)))
        .contentShape(Capsule())
        .modifier(PillTaps(
            isEnabled: !isRenaming,
            onSelect: { viewModel.selectTab(tab.id) },
            onRename: {
                viewModel.selectTab(tab.id)
                viewModel.beginRename(tabID: tab.id)
            }
        ))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func background(palette: WorkspaceTitlebarPalette) -> Color {
        if isSelected { return palette.activePill }
        return isHovering ? palette.hoverPill : .clear
    }

    private func foreground(palette: WorkspaceTitlebarPalette) -> Color {
        if isSelected { return palette.primaryText }
        return isHovering ? palette.hoverText : palette.secondaryText
    }

    private func titleText(palette: WorkspaceTitlebarPalette) -> some View {
        Text(tab.title)
            .workspaceTitlebarFont(size: 13)
            .foregroundColor(foreground(palette: palette))
            .lineLimit(1)
            .truncationMode(.tail)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: VisibleWidthKey.self, value: proxy.size.width)
                }
            )
            .background(
                Text(tab.title)
                    .workspaceTitlebarFont(size: 13)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: NaturalWidthKey.self, value: proxy.size.width)
                        }
                    )
            )
            .onPreferenceChange(VisibleWidthKey.self) { visibleWidth = $0 }
            .onPreferenceChange(NaturalWidthKey.self) { naturalWidth = $0 }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(Self.isTruncated(naturalWidth: naturalWidth, visibleWidth: visibleWidth) ? tab.title : "")
    }

    private func closeButton(palette: WorkspaceTitlebarPalette) -> some View {
        let isVisible = isSelected || isHovering
        return CloseGlyphButton(
            size: Self.closeSize,
            normal: isSelected ? palette.primaryText : palette.secondaryText,
            hoverBackground: palette.hoverButton,
            hoverForeground: palette.primaryText,
            accessibilityLabel: "Close terminal \(tab.title)",
            action: { viewModel.closeTab(tab.id) }
        )
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
    }
}

struct CloseGlyphButton: View {
    let size: CGFloat
    let normal: Color
    let hoverBackground: Color
    let hoverForeground: Color
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isHovering ? hoverForeground : normal)
                .frame(width: size, height: size)
                .background(Circle().fill(isHovering ? hoverBackground : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct VisibleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct NaturalWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PillTaps: ViewModifier {
    let isEnabled: Bool
    let onSelect: () -> Void
    let onRename: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onTapGesture(count: 2, perform: onRename)
                .onTapGesture(perform: onSelect)
        } else {
            content
        }
    }
}

private struct RenameField: View {
    @ObservedObject var viewModel: WorkspaceTitlebarViewModel
    let palette: WorkspaceTitlebarPalette

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $viewModel.renameDraft)
            .textFieldStyle(.plain)
            .workspaceTitlebarFont(size: 13)
            .foregroundColor(palette.primaryText)
            .padding(.horizontal, WorkspaceTabPill.horizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: WorkspaceTabPill.height)
            .background(Capsule().fill(palette.renameBackground))
            .overlay(Capsule().strokeBorder(palette.renameBorder, lineWidth: 1))
            .focused($isFocused)
            .onSubmit { viewModel.commitRename() }
            .onExitCommand { viewModel.cancelRename() }
            .onChange(of: isFocused) { focused in
                if !focused { viewModel.blurRename() }
            }
            .onAppear {
                isFocused = true
                DispatchQueue.main.async {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            .accessibilityLabel("Rename terminal")
    }
}
