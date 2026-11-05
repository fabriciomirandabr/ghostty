import SwiftUI

class WindowDraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override var safeAreaRect: NSRect { bounds }
}

struct WindowDraggableHost<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> WindowDraggableHostingView<Content> {
        WindowDraggableHostingView(rootView: content)
    }

    func updateNSView(_ nsView: WindowDraggableHostingView<Content>, context: Context) {
        nsView.rootView = content
    }
}
