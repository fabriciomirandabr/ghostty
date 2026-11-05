import SwiftUI
import Testing
@testable import Ghostty

struct StatusIndicatorViewTests {
    @Test func colors() {
        #expect(WorkspaceStatusColors.hex(for: .running) == 0x4F7CFF)
        #expect(WorkspaceStatusColors.hex(for: .needsAttention) == 0xF5D90A)
        #expect(WorkspaceStatusColors.hex(for: .done) == 0xFFFFFF)
        #expect(WorkspaceStatusColors.hex(for: .idle) == 0xD0D0D0)
        #expect(WorkspaceStatusColors.badgeDotHex == 0xFF7A1A)
        #expect(WorkspaceStatusColors.tabCircleHex == 0x555555)
    }

    @Test func colorComponents() throws {
        let color = NSColor(WorkspaceStatusColors.color(for: .running)).usingColorSpace(.sRGB)
        let components = try #require(color)
        #expect(Int((components.redComponent * 255).rounded()) == 0x4F)
        #expect(Int((components.greenComponent * 255).rounded()) == 0x7C)
        #expect(Int((components.blueComponent * 255).rounded()) == 0xFF)
        #expect(components.alphaComponent == 1)
    }

    @Test(arguments: [
        (SurfaceActivityState.idle, "Idle"),
        (.done, "Done"),
        (.running, "Running"),
        (.needsAttention, "Needs you"),
    ])
    func accessibilityLabels(state: SurfaceActivityState, expected: String) {
        #expect(StatusIndicatorView.accessibilityLabel(for: state) == expected)
    }
}
