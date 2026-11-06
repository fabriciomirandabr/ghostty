import SwiftUI
import Testing
@testable import Ghostty

struct ActivityBadgeViewTests {
    @Test func accessibilityLabel() {
        #expect(
            ActivityBadgeView.accessibilityLabel(runningCount: 2, needsAttention: true)
                == "Workspaces overview: 2 running, attention needed"
        )
        #expect(
            ActivityBadgeView.accessibilityLabel(runningCount: 0, needsAttention: false)
                == "Workspaces"
        )
        #expect(
            ActivityBadgeView.accessibilityLabel(runningCount: 1, needsAttention: false)
                == "Workspaces overview: 1 running"
        )
        #expect(
            ActivityBadgeView.accessibilityLabel(runningCount: 0, needsAttention: true)
                == "Workspaces, attention needed"
        )
    }

    @Test func gridReplacesZeroCount() {
        #expect(ActivityBadgeView.showsGrid(runningCount: 0))
        #expect(!ActivityBadgeView.showsGrid(runningCount: 1))
        #expect(!ActivityBadgeView.showsGrid(runningCount: 100))
    }

    @Test func titlebarBadgeStyleDoesNotInvertWhileRunning() {
        let dark = WorkspaceBadgeStyle(fillHex: 0x3A3A3A, foregroundHex: 0xFFFFFF)
        #expect(ActivityBadgeView.badgeStyle(runningCount: 0) == dark)
        #expect(ActivityBadgeView.badgeStyle(runningCount: 1) == dark)
        #expect(ActivityBadgeView.badgeStyle(runningCount: 120) == dark)
    }

    @Test func badgeStyleMirrorsInLightMode() {
        let light = WorkspaceBadgeStyle(fillHex: 0xFFFFFF, foregroundHex: 0x111111)
        #expect(ActivityBadgeView.badgeStyle(runningCount: 0, colorScheme: .light) == light)
        #expect(ActivityBadgeView.badgeStyle(runningCount: 2, colorScheme: .light) == light)
        #expect(WorkspaceBadgeStyle.make(for: .idle, colorScheme: .light) == light)
        #expect(WorkspaceBadgeStyle.make(for: .running, colorScheme: .light) == light)
        #expect(WorkspaceBadgeStyle.make(for: .done, colorScheme: .light) == light)
        #expect(
            WorkspaceBadgeStyle.make(for: .needsAttention, colorScheme: .light)
                == WorkspaceBadgeStyle(fillHex: 0xFFFFFF, foregroundHex: 0x8A5A00)
        )
    }

    @Test(arguments: [
        (SurfaceActivityState.idle, UInt32(0x3A3A3A), UInt32(0xFFFFFF)),
        (.running, 0x3A3A3A, 0xFFFFFF),
        (.done, 0x3A3A3A, 0xFFFFFF),
        (.needsAttention, 0x3A3A3A, 0xF5D90A),
    ])
    func badgeStyleMapsStateToTokens(state: SurfaceActivityState, fill: UInt32, foreground: UInt32) {
        let style = WorkspaceBadgeStyle.make(for: state, colorScheme: .dark)
        #expect(style.fillHex == fill)
        #expect(style.foregroundHex == foreground)
    }

    @Test(arguments: [
        (SurfaceActivityState.idle, false),
        (.running, true),
        (.done, false),
        (.needsAttention, true),
    ])
    func ringShowsOnlyForRunningAndAttention(state: SurfaceActivityState, expected: Bool) {
        #expect(WorkspaceBadgeStyle.showsRing(for: state) == expected)
    }

    @Test func titlebarRingStateFollowsPriority() {
        #expect(ActivityBadgeView.ringState(runningCount: 0, needsAttention: false) == .idle)
        #expect(ActivityBadgeView.ringState(runningCount: 2, needsAttention: false) == .running)
        #expect(ActivityBadgeView.ringState(runningCount: 2, needsAttention: true) == .needsAttention)
        #expect(ActivityBadgeView.ringState(runningCount: 0, needsAttention: true) == .needsAttention)
        #expect(WorkspaceBadgeStyle.ringLineWidth == 1.5)
        #expect(WorkspaceBadgeStyle.ringOpacity == 0.6)
    }

    @Test func noAnimationPrimitivesInBadgeSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Features/Workspaces")
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let badgeFiles: Set<String> = ["StatusIndicatorView.swift", "ActivityBadgeView.swift", "ActivityPopoverView.swift"]
        var offenders: [String] = []
        var scannedBadgeFiles = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let isBadgeFile = badgeFiles.contains(url.lastPathComponent)
            if isBadgeFile { scannedBadgeFiles += 1 }
            let bannedEverywhere = text.contains("repeatForever")
            let bannedInBadgeFiles = ["TimelineView", "withAnimation(", ".animation("].contains { text.contains($0) }
            if bannedEverywhere || (isBadgeFile && bannedInBadgeFiles) {
                offenders.append(url.lastPathComponent)
            }
        }
        #expect(scannedBadgeFiles >= 3)
        #expect(offenders.isEmpty)
    }

    @Test func displayTextCapsLargeCounts() {
        #expect(ActivityBadgeView.displayText(runningCount: 0) == "0")
        #expect(ActivityBadgeView.displayText(runningCount: 7) == "7")
        #expect(ActivityBadgeView.displayText(runningCount: 99) == "99")
        #expect(ActivityBadgeView.displayText(runningCount: 100) == "99+")
    }
}
