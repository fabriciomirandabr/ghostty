import SwiftUI

struct WorkspaceRootView<Titlebar: View, Terminal: View, Overlay: View>: View {
    let titlebarHeight: CGFloat
    let titlebar: Titlebar
    let terminal: Terminal
    let overlay: Overlay

    var body: some View {
        VStack(spacing: 0) {
            WindowDraggableHost { titlebar }
                .frame(height: titlebarHeight)

            ZStack {
                terminal
                overlay
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

struct WorkspaceWindowContent: View {
    @StateObject private var metrics = WorkspaceTitlebarMetrics()

    @ObservedObject var controller: WorkspaceTerminalController
    @ObservedObject var ghostty: Ghostty.App
    @ObservedObject var overlayState: WorkspaceOverlayState
    @ObservedObject var titlebar: WorkspaceTitlebarViewModel

    init(controller: WorkspaceTerminalController, ghostty: Ghostty.App, overlayState: WorkspaceOverlayState) {
        self.controller = controller
        self.ghostty = ghostty
        self.overlayState = overlayState
        self.titlebar = controller.titlebarViewModel
    }

    var body: some View {
        WorkspaceRootView(
            titlebarHeight: metrics.height,
            titlebar: WorkspaceTitlebarView(viewModel: titlebar, metrics: metrics)
                .environmentObject(ghostty),
            terminal: TerminalView(ghostty: ghostty, viewModel: controller, delegate: controller),
            overlay: overlay)
            .background(WorkspaceTitlebarMetricsProbe(metrics: metrics))
    }

    @ViewBuilder
    private var overlay: some View {
        ZStack(alignment: .topLeading) {
            layer
            menu
        }
    }

    @ViewBuilder
    private var menu: some View {
        if titlebar.isMenuPresented {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { titlebar.dismissMenu() }

            WorkspaceMenuView(viewModel: titlebar)
                .environment(\.workspaceTitleFontFamily, titlebar.fontFamily)
                .fixedSize(horizontal: true, vertical: false)
                .workspaceOverlayPanel(padding: 0)
                .padding(.leading, metrics.leadingInset)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var layer: some View {
        if overlayState.isAnyOpen {
            WorkspaceOverlayLayer(
                titlebarHeight: metrics.height,
                snapshot: controller.overlaySnapshot,
                state: overlayState,
                thumbnails: controller.thumbnails,
                terminalBackground: ghostty.config.backgroundColor,
                terminalForeground: ghostty.config.foregroundColor,
                actions: controller.makeOverlayActions())
        }
    }
}
