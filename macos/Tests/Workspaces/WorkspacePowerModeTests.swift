import AppKit
import Combine
import Foundation
import Testing
@testable import Ghostty

@MainActor
struct WorkspacePowerModeTests {
    @Test func resolverCoversEveryInputCombination() {
        let nominal = ProcessInfo.ThermalState.nominal
        let fair = ProcessInfo.ThermalState.fair
        let serious = ProcessInfo.ThermalState.serious
        let critical = ProcessInfo.ThermalState.critical

        #expect(WorkspacePowerMode.resolve(lowPower: false, thermal: nominal, onBattery: false) == .performance)
        #expect(WorkspacePowerMode.resolve(lowPower: false, thermal: fair, onBattery: false) == .performance)
        #expect(WorkspacePowerMode.resolve(lowPower: true, thermal: nominal, onBattery: false) == .saver)
        #expect(WorkspacePowerMode.resolve(lowPower: false, thermal: serious, onBattery: false) == .saver)
        #expect(WorkspacePowerMode.resolve(lowPower: false, thermal: critical, onBattery: false) == .saver)
        #expect(WorkspacePowerMode.resolve(lowPower: false, thermal: nominal, onBattery: true) == .saver)
        #expect(WorkspacePowerMode.resolve(lowPower: true, thermal: serious, onBattery: true) == .saver)
        #expect(WorkspacePowerMode.resolve(lowPower: true, thermal: fair, onBattery: false) == .saver)
        #expect(WorkspacePowerMode.resolve(lowPower: true, thermal: serious, onBattery: false) == .saver)
        #expect(WorkspacePowerMode.resolve(lowPower: true, thermal: nominal, onBattery: true) == .saver)
        #expect(WorkspacePowerMode.resolve(lowPower: false, thermal: serious, onBattery: true) == .saver)
    }

    @Test func saverIntervalsAreSlowerThanPerformanceOnes() {
        #expect(WorkspacePowerMode.performance.chromeThrottleInterval == 0.2)
        #expect(WorkspacePowerMode.saver.chromeThrottleInterval == 1.0)
        #expect(WorkspacePowerMode.performance.snapshotInterval == 0.5)
        #expect(WorkspacePowerMode.saver.snapshotInterval == 2.0)
        #expect(WorkspacePowerMode.performance.thumbnailRefreshInterval == 0.5)
        #expect(WorkspacePowerMode.saver.thumbnailRefreshInterval == 2.0)
    }

    @Test func monitorFollowsItsInputsAndPublishesOnlyRealChanges() {
        var inputs = WorkspacePowerInputs(lowPower: false, thermal: .nominal, onBattery: false)
        let monitor = WorkspacePowerMonitor(readInputs: { inputs })
        var modes: [WorkspacePowerMode] = []
        let cancellable = monitor.$mode.sink { modes.append($0) }

        #expect(monitor.mode == .performance)

        monitor.refresh()
        inputs.onBattery = true
        monitor.refresh()
        monitor.refresh()
        inputs.lowPower = true
        monitor.refresh()
        inputs.onBattery = false
        inputs.lowPower = false
        monitor.refresh()

        #expect(modes == [.performance, .saver, .performance])
        cancellable.cancel()
    }

    @Test func monitorStartsInSaverWhenTheMachineIsAlreadyHot() {
        let monitor = WorkspacePowerMonitor(readInputs: {
            WorkspacePowerInputs(lowPower: false, thermal: .serious, onBattery: false)
        })

        #expect(monitor.mode == .saver)
    }

    @Test func theRealPowerSourceCanBeRead() {
        let inputs = WorkspacePowerSource.currentInputs()
        #expect(inputs.mode == WorkspacePowerMode.resolve(
            lowPower: inputs.lowPower,
            thermal: inputs.thermal,
            onBattery: inputs.onBattery))
    }
}

@MainActor
struct WorkspaceSnapshotScalingTests {
    private func bitmapImage(pointWidth: CGFloat, pointHeight: CGFloat, scale: CGFloat) throws -> NSImage {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pointWidth * scale),
            pixelsHigh: Int(pointHeight * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        rep.size = NSSize(width: pointWidth, height: pointHeight)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func pixelWidth(_ image: NSImage) -> Int {
        image.representations.map(\.pixelsWide).max() ?? 0
    }

    @Test func aWideCaptureIsStoredAtMostFourHundredEightyPointsWide() throws {
        let snapshots = WorkspaceSnapshotStore()
        let tab = UUID()
        let capture = try bitmapImage(pointWidth: 3440, pointHeight: 1440, scale: 2)

        snapshots.storeCapture(capture, for: tab, screenScale: 2)

        let stored = try #require(snapshots.image(for: tab))
        #expect(stored.size.width <= 480)
        #expect(stored.size.width == 480)
        #expect(stored.size.height == 201)
        #expect(pixelWidth(stored) == 960)
        #expect(pixelWidth(stored) < pixelWidth(capture) / 7)
    }

    @Test func theScaleIsCappedAtTwoAndFlooredAtOne() throws {
        let capture = try bitmapImage(pointWidth: 1200, pointHeight: 600, scale: 2)

        let tall = WorkspaceSnapshotImage.downscaled(capture, maxWidth: 480, screenScale: 3)
        let flat = WorkspaceSnapshotImage.downscaled(capture, maxWidth: 480, screenScale: 1)

        #expect(pixelWidth(tall) == 960)
        #expect(pixelWidth(flat) == 480)
        #expect(flat.size.height == 240)
    }

    @Test func aCaptureWithinTheLimitIsKeptAsIs() throws {
        let capture = try bitmapImage(pointWidth: 400, pointHeight: 300, scale: 1)

        let result = WorkspaceSnapshotImage.downscaled(capture, maxWidth: 480, screenScale: 2)

        #expect(result === capture)
    }

    @Test func downscalingKeepsTheContent() throws {
        let capture = OverlayFixtures.solidImage(.red, side: 1000)

        let result = WorkspaceSnapshotImage.downscaled(capture, maxWidth: 480, screenScale: 1)

        #expect(result.size.width == 480)
        #expect(result.size.height == 480)
        let cgImage = try #require(result.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let color = try #require(rep.colorAt(x: 100, y: 100)?.usingColorSpace(.deviceRGB))
        #expect(color.redComponent > 0.9)
        #expect(color.greenComponent < 0.1)
    }

    @Test func snapshotsSurviveTheOverviewClosing() throws {
        let store = MockStore(defaultDirectory: WorkspaceFixtures.home, makeTab: { WorkspaceFixtures.makeTab() })
        let overlay = WorkspaceOverlayState()
        let tab = UUID()
        overlay.present(.overview)
        store.snapshots.storeCapture(try bitmapImage(pointWidth: 1600, pointHeight: 900, scale: 2), for: tab, screenScale: 2)

        overlay.dismiss(.overview)

        #expect(!overlay.isOpen(.overview))
        #expect(store.snapshots.image(for: tab) != nil)
        #expect(!store.snapshots.images.isEmpty)
    }
}
