import SwiftUI

struct WorkspaceThumbnailView: View {
    static let fontSize: CGFloat = 5.5

    let tabID: UUID
    let source: WorkspaceThumbnailSource
    var background: Color
    var foreground: Color

    @ObservedObject private var power = WorkspacePowerMonitor.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: power.mode.thumbnailRefreshInterval)) { _ in
            content(WorkspaceThumbnailContent.resolve(
                image: source.image(for: tabID),
                text: source.text(for: tabID)
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.cardRadius - 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.cardRadius - 2, style: .continuous)
                .strokeBorder(WorkspaceOverlayPalette.thumbnailBorder, lineWidth: 1)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(_ content: WorkspaceThumbnailContent) -> some View {
        switch content {
        case .image(let image):
            GeometryReader { proxy in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()
            }

        case .text(let lines):
            Color.clear.overlay(alignment: .topLeading) {
                Text(lines.joined(separator: "\n"))
                    .font(.system(size: Self.fontSize, design: .monospaced))
                    .foregroundColor(foreground)
                    .lineLimit(nil)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(6)
            }

        case .blank:
            Color.clear
        }
    }
}
