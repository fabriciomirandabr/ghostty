import AppKit
import Foundation
@testable import Ghostty

struct TabSpec {
    var title: String
    var state: SurfaceActivityState = .idle
    var command: String?
}

enum OverlayFixtures {
    static let home = "/tmp/ws-home"

    static func workspace(
        _ name: String,
        directory: String? = nil,
        isDefault: Bool = false,
        isCurrent: Bool = false,
        tabs: [TabSpec] = [TabSpec(title: "shell")]
    ) -> WorkspaceSummary {
        let id = UUID()
        let summaries = tabs.map {
            WorkspaceTabSummary(
                id: UUID(),
                workspaceID: id,
                title: $0.title,
                state: $0.state,
                lastCommand: $0.command,
                busiestSurfaceID: UUID()
            )
        }
        return WorkspaceSummary(
            id: id,
            name: name,
            directory: URL(fileURLWithPath: directory ?? "\(home)/\(name)"),
            isDefault: isDefault,
            isCurrent: isCurrent,
            state: summaries.map(\.state).max() ?? .idle,
            selectedTabID: summaries[0].id,
            tabs: summaries
        )
    }

    static func snapshot(_ workspaces: [WorkspaceSummary]) -> WorkspaceOverlaySnapshot {
        WorkspaceOverlaySnapshot(workspaces: workspaces)
    }

    static func solidImage(_ color: NSColor, side: Int = 64, stripe: NSColor? = nil) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            preconditionFailure("failed to create bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        if let stripe {
            stripe.setFill()
            NSRect(x: 0, y: side / 4, width: side, height: side / 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }
}
