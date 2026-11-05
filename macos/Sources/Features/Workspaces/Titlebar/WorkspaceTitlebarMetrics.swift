import AppKit
import SwiftUI

@MainActor
final class WorkspaceTitlebarMetrics: ObservableObject {
    static let minimumHeight: CGFloat = 44
    static let initialLeadingInset: CGFloat = 80
    static let trafficLightGap: CGFloat = 12

    struct Measurement: Equatable {
        let height: CGFloat
        let leadingInset: CGFloat
    }

    @Published private(set) var height: CGFloat = WorkspaceTitlebarMetrics.minimumHeight
    @Published private(set) var leadingInset: CGFloat = WorkspaceTitlebarMetrics.initialLeadingInset

    nonisolated static func measure(closeFrame: CGRect, zoomFrame: CGRect, windowHeight: CGFloat) -> Measurement {
        let centerFromTop = windowHeight - closeFrame.midY
        return Measurement(
            height: max(minimumHeight, (centerFromTop * 2).rounded()),
            leadingInset: (zoomFrame.maxX + trafficLightGap).rounded())
    }

    func update(from window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let closeSuperview = close.superview,
              let zoomSuperview = zoom.superview
        else { return }

        let measurement = Self.measure(
            closeFrame: closeSuperview.convert(close.frame, to: nil),
            zoomFrame: zoomSuperview.convert(zoom.frame, to: nil),
            windowHeight: window.frame.height)

        if height != measurement.height { height = measurement.height }
        if leadingInset != measurement.leadingInset { leadingInset = measurement.leadingInset }
    }
}

struct WorkspaceTitlebarMetricsProbe: NSViewRepresentable {
    let metrics: WorkspaceTitlebarMetrics

    func makeNSView(context: Context) -> ProbeView {
        ProbeView(metrics: metrics)
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        private let metrics: WorkspaceTitlebarMetrics
        private var observers: [NSObjectProtocol] = []

        init(metrics: WorkspaceTitlebarMetrics) {
            self.metrics = metrics
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else { return }

            var targets: [NSView] = []
            for type in [NSWindow.ButtonType.closeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type) else { continue }
                button.postsFrameChangedNotifications = true
                targets.append(button)
                if let superview = button.superview {
                    superview.postsFrameChangedNotifications = true
                    targets.append(superview)
                }
            }

            let names: [(Notification.Name, AnyObject)] = targets.map { (NSView.frameDidChangeNotification, $0) }
                + [(NSWindow.didExitFullScreenNotification, window), (NSWindow.didResizeNotification, window)]
            observers = names.map { name, object in
                NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }

            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }

        private func refresh() {
            guard let window else { return }
            metrics.update(from: window)
        }
    }
}
