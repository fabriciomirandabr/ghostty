import AppKit

class WorkspacesTerminalWindow: TerminalWindow {
    override var supportsUpdateAccessory: Bool { false }

    private var trafficLightObservers: [NSObjectProtocol] = []

    deinit {
        trafficLightObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func alignTrafficLights() {
        guard !styleMask.contains(.fullScreen),
              let container = standardWindowButton(.closeButton)?.superview?.superview,
              let parent = container.superview
        else { return }

        let height = WorkspaceTitlebarMetrics.minimumHeight
        let target = CGRect(
            x: container.frame.minX,
            y: parent.bounds.height - height,
            width: container.frame.width,
            height: height)
        if container.frame != target {
            container.frame = target
            container.layoutSubtreeIfNeeded()
        }

        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(type), let titlebar = button.superview else { continue }
            let originY = titlebar.bounds.height - height / 2 - button.frame.height / 2
            if button.frame.origin.y != originY {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: originY))
            }
        }
    }

    private func observeTrafficLightChanges() {
        guard trafficLightObservers.isEmpty else { return }
        var sources: [(Notification.Name, AnyObject)] = [
            (NSWindow.didUpdateNotification, self),
            (NSWindow.didResizeNotification, self),
            (NSWindow.didExitFullScreenNotification, self)
        ]
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(type) else { continue }
            button.postsFrameChangedNotifications = true
            sources.append((NSView.frameDidChangeNotification, button))
        }
        if let container = standardWindowButton(.closeButton)?.superview?.superview {
            container.postsFrameChangedNotifications = true
            sources.append((NSView.frameDidChangeNotification, container))
        }

        trafficLightObservers = sources.map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.alignTrafficLights() }
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        applyWorkspacesStyle()
        DispatchQueue.main.async { [weak self] in
            self?.applyWorkspacesStyle()
        }
    }

    func applyWorkspacesStyle() {
        styleMask.insert(.fullSizeContentView)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        tabbingMode = .disallowed

        if #available(macOS 27, *),
           let themeFrame = contentView?.superview,
           let scrollPocket = themeFrame.firstDescendant(withClassName: "NSScrollPocket") {
            scrollPocket.isHidden = true
        }

        observeTrafficLightChanges()
        alignTrafficLights()
    }

    override var contentLayoutRect: CGRect {
        var rect = super.contentLayoutRect
        rect.origin.y = 0
        rect.size.height = self.frame.height
        return rect
    }

    override func becomeMain() {
        super.becomeMain()
        applyWorkspacesStyle()
    }

    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {}

    override var title: String {
        didSet {
            titleVisibility = .hidden
        }
    }
}
