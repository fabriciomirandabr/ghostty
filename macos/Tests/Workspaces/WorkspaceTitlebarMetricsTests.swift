import AppKit
import Testing
@testable import Ghostty

@MainActor
struct WorkspaceTitlebarMetricsTests {
    @Test func heightCentersTheBarOnTheTrafficLights() {
        let measurement = WorkspaceTitlebarMetrics.measure(
            closeFrame: CGRect(x: 14, y: 278, width: 14, height: 16),
            zoomFrame: CGRect(x: 54, y: 278, width: 14, height: 16),
            windowHeight: 300)

        #expect(measurement.height == WorkspaceTitlebarMetrics.minimumHeight)
        #expect(measurement.leadingInset == 80)
    }

    @Test func tallerTitlebarGrowsTheBar() {
        let measurement = WorkspaceTitlebarMetrics.measure(
            closeFrame: CGRect(x: 20, y: 267, width: 14, height: 14),
            zoomFrame: CGRect(x: 80, y: 267, width: 14, height: 14),
            windowHeight: 300)

        #expect(measurement.height == 52)
        #expect(measurement.leadingInset == 106)
    }

    @Test func minimumHeightIsTheEgoBarHeight() {
        #expect(WorkspaceTitlebarMetrics.minimumHeight == 44)
        #expect(WorkspaceTabPill.height == 30)
        #expect(WorkspaceMenuButton.height == 30)
        #expect(ActivityBadgeView.size == 28)
    }

    @Test func neverShrinksBelowTheMinimum() {
        let measurement = WorkspaceTitlebarMetrics.measure(
            closeFrame: CGRect(x: 0, y: 296, width: 10, height: 10),
            zoomFrame: CGRect(x: 40, y: 296, width: 10, height: 10),
            windowHeight: 300)

        #expect(measurement.height == WorkspaceTitlebarMetrics.minimumHeight)
    }

    @Test func updateReadsTheRealWindowButtons() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true

        let metrics = WorkspaceTitlebarMetrics()
        metrics.update(from: window)

        let close = window.standardWindowButton(.closeButton)
        let expected = close.flatMap { button in
            button.superview.map { window.frame.height - $0.convert(button.frame, to: nil).midY }
        }

        #expect(expected != nil)
        #expect(metrics.height == max(WorkspaceTitlebarMetrics.minimumHeight, ((expected ?? 0) * 2).rounded()))
    }
}
