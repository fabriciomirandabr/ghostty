import AppKit

class WorkspacesTerminalWindow: TerminalWindow {
    override var supportsUpdateAccessory: Bool { false }

    private var isAligningTrafficLights = false

    func alignTrafficLights() {
        guard !isAligningTrafficLights, !styleMask.contains(.fullScreen) else { return }
        isAligningTrafficLights = true
        defer { isAligningTrafficLights = false }

        guard let container = standardWindowButton(.closeButton)?.superview?.superview,
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
        }

        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(type), let titlebar = button.superview else { continue }
            let originY = titlebar.bounds.height - height / 2 - button.frame.height / 2
            if button.frame.origin.y != originY {
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: originY))
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
