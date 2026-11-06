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
        var timelineCounts: [String: Int] = [:]
        var periodicCounts: [String: Int] = [:]
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let squeezed = text.filter { !$0.isWhitespace }
            let name = url.lastPathComponent
            let isBadgeFile = badgeFiles.contains(name)
            if isBadgeFile {
                scannedBadgeFiles += 1
                timelineCounts[name] = text.components(separatedBy: "TimelineView").count - 1
                periodicCounts[name] = squeezed.components(separatedBy: "TimelineView(.periodic(").count - 1
            }
            let bannedInBadgeFiles = [
                "withAnimation(", ".animation(", "TimelineView(.animation", "by:1/60", "by:0.016",
            ].contains { text.contains($0) || squeezed.contains($0) }
            if text.contains("repeatForever") || (isBadgeFile && bannedInBadgeFiles) {
                offenders.append(name)
            }
        }
        #expect(scannedBadgeFiles >= 3)
        #expect(offenders.isEmpty)
        #expect(timelineCounts["ActivityBadgeView.swift"] == 1)
        #expect(periodicCounts["ActivityBadgeView.swift"] == 1)
        #expect(timelineCounts["StatusIndicatorView.swift"] == 0)
        #expect(timelineCounts["ActivityPopoverView.swift"] == 0)
    }

    @Test func ringStepMapsTimeToEighths() {
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let steps = (0..<16).map { ActivityBadgeView.ringStep(at: base.addingTimeInterval(Double($0) * 0.25 + 0.01)) }
        #expect(Set(steps) == Set(0...7))
        #expect(Array(steps[8...]) == Array(steps[..<8]))
        #expect(zip(steps, steps.dropFirst()).allSatisfy { ($0 + 1) % 8 == $1 })
        #expect(ActivityBadgeView.ringStep(at: base) == ActivityBadgeView.ringStep(at: base.addingTimeInterval(0.2)))
        #expect(ActivityBadgeView.ringStep(at: Date(timeIntervalSinceReferenceDate: 0)) == 0)
        #expect(ActivityBadgeView.ringStep(at: Date(timeIntervalSinceReferenceDate: 0.5)) == 2)
        #expect(ActivityBadgeView.ringStep(at: Date(timeIntervalSinceReferenceDate: -0.1)) == 7)
        #expect(ActivityBadgeView.ringAngle(at: Date(timeIntervalSinceReferenceDate: 0.75)) == 135)
    }

    @Test func ringSpinsOnlyWhenMotionAllowedAndKey() {
        #expect(ActivityBadgeView.shouldSpinRing(reduceMotion: false, isKeyWindow: true, isWindowVisible: true))
        #expect(!ActivityBadgeView.shouldSpinRing(reduceMotion: true, isKeyWindow: true, isWindowVisible: true))
        #expect(!ActivityBadgeView.shouldSpinRing(reduceMotion: false, isKeyWindow: false, isWindowVisible: true))
    }

    @MainActor
    @Test func ringStaysStaticWhenWindowHidden() {
        #expect(!ActivityBadgeView.shouldSpinRing(reduceMotion: false, isKeyWindow: true, isWindowVisible: false))
        #expect(!ActivityBadgeView.shouldSpinRing(reduceMotion: true, isKeyWindow: false, isWindowVisible: false))
        #expect(WorkspaceTitlebarSnapshot().isWindowVisible == false)
        let model = WorkspaceTitlebarViewModel(shortcut: { _ in nil })
        #expect(!model.isWindowVisible)
        model.apply(WorkspaceTitlebarSnapshot(isWindowVisible: true))
        #expect(model.isWindowVisible)
        model.apply(WorkspaceTitlebarSnapshot(isWindowVisible: false))
        #expect(!model.isWindowVisible)
    }

    @Test func ringScheduleStartsOnAQuarterSecondBoundary() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000.37)
        let start = ActivityBadgeView.ringScheduleStart(now: now)
        #expect(start.timeIntervalSinceReferenceDate == 1_000_000.25)
        #expect(start <= now)
        #expect(now.timeIntervalSince(start) < 0.25)
        #expect(ActivityBadgeView.ringStep(at: start) == ActivityBadgeView.ringStep(at: now))
    }

    @Test func displayTextCapsLargeCounts() {
        #expect(ActivityBadgeView.displayText(runningCount: 0) == "0")
        #expect(ActivityBadgeView.displayText(runningCount: 7) == "7")
        #expect(ActivityBadgeView.displayText(runningCount: 99) == "99")
        #expect(ActivityBadgeView.displayText(runningCount: 100) == "99+")
    }
}
