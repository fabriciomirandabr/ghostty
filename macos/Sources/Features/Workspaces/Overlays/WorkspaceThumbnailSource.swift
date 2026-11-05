import AppKit

@MainActor
protocol WorkspaceThumbnailSource: AnyObject {
    func image(for tabID: UUID) -> NSImage?
    func text(for tabID: UUID) -> [String]?
}

enum WorkspaceThumbnailText {
    static let maxLines = 48
    static let maxColumns = 160

    static func lines(from raw: String) -> [String]? {
        var lines = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var text = String(line.prefix(maxColumns))
                while text.last?.isWhitespace == true { text.removeLast() }
                return text
            }

        while lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        return Array(lines.suffix(maxLines))
    }
}

enum WorkspaceThumbnailContent {
    case image(NSImage)
    case text([String])
    case blank

    static func resolve(image: NSImage?, text: [String]?) -> WorkspaceThumbnailContent {
        if let image, !WorkspaceThumbnailImage.isUniform(image) {
            return .image(image)
        }
        if let text {
            return .text(text)
        }
        return .blank
    }
}

enum WorkspaceThumbnailImage {
    private static let probeSide = 32
    private static let tolerance = 3

    static func isUniform(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width > 0, cgImage.height > 0 else { return true }

        let side = probeSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }

        let first = Array(pixels[0..<4])
        for index in stride(from: 4, to: pixels.count, by: 4) {
            for channel in 0..<4 where abs(Int(pixels[index + channel]) - Int(first[channel])) > tolerance {
                return false
            }
        }
        return true
    }
}

@MainActor
final class StoreThumbnailSource<ViewType: NSView & Codable & Identifiable>: WorkspaceThumbnailSource
where ViewType.ID == UUID {
    private weak var store: WorkspaceStore<ViewType>?
    private let readText: (ViewType) -> String

    init(store: WorkspaceStore<ViewType>, readText: @escaping (ViewType) -> String) {
        self.store = store
        self.readText = readText
    }

    func image(for tabID: UUID) -> NSImage? {
        store?.snapshots.image(for: tabID)
    }

    func text(for tabID: UUID) -> [String]? {
        guard let store,
              let tab = store.workspaces.lazy.compactMap({ $0.tab(id: tabID) }).first else { return nil }
        let surfaces = Array(tab.tree)
        guard let surface = surfaces.first(where: { $0.id == tab.focusedSurfaceID }) ?? surfaces.first else {
            return nil
        }
        return WorkspaceThumbnailText.lines(from: readText(surface))
    }
}

extension WorkspaceStore where ViewType == Ghostty.SurfaceView {
    func makeThumbnailSource() -> StoreThumbnailSource<Ghostty.SurfaceView> {
        StoreThumbnailSource(store: self) { $0.cachedVisibleContents.get() }
    }
}
