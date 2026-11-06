import AppKit

@MainActor
final class WorkspaceSnapshotStore: ObservableObject {
    @Published private(set) var images: [UUID: NSImage] = [:]

    func image(for tabID: UUID) -> NSImage? {
        images[tabID]
    }

    func store(_ image: NSImage, for tabID: UUID) {
        images[tabID] = image
    }

    func remove(tabID: UUID) {
        images[tabID] = nil
    }

    func prune(keeping tabIDs: Set<UUID>) {
        images = images.filter { tabIDs.contains($0.key) }
    }

    func storeCapture(_ image: NSImage, for tabID: UUID, screenScale: CGFloat) {
        store(
            WorkspaceSnapshotImage.downscaled(
                image,
                maxWidth: WorkspaceSnapshotImage.maxWidth,
                screenScale: screenScale),
            for: tabID)
    }

    func clear() {
        guard !images.isEmpty else { return }
        images = [:]
    }
}

enum WorkspaceSnapshotImage {
    static let maxWidth: CGFloat = 480
    static let maxScale: CGFloat = 2

    static func targetSize(for size: CGSize, maxWidth: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        let width = min(size.width, maxWidth)
        return CGSize(width: width, height: max(1, (size.height * width / size.width).rounded()))
    }

    static func downscaled(_ image: NSImage, maxWidth: CGFloat, screenScale: CGFloat) -> NSImage {
        guard image.size.width > maxWidth else { return image }

        let points = targetSize(for: image.size, maxWidth: maxWidth)
        let scale = min(max(screenScale, 1), maxScale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int((points.width * scale).rounded())),
            pixelsHigh: max(1, Int((points.height * scale).rounded())),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            Ghostty.logger.warning("snapshot downscale unavailable, keeping the full size capture")
            return image
        }

        rep.size = points
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: CGRect(origin: .zero, size: points), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: points)
        result.addRepresentation(rep)
        return result
    }
}
