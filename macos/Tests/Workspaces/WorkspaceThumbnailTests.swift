import AppKit
import Testing
@testable import Ghostty

@MainActor
struct WorkspaceThumbnailTests {
    @Test func textLinesDropTrailingBlankRows() {
        let lines = WorkspaceThumbnailText.lines(from: "$ ls   \nREADME\n\n\n")
        #expect(lines == ["$ ls", "README"])
    }

    @Test func blankScreenHasNoText() {
        #expect(WorkspaceThumbnailText.lines(from: "") == nil)
        #expect(WorkspaceThumbnailText.lines(from: "  \n\n   \n") == nil)
    }

    @Test func textKeepsTheLastLinesAndCapsColumns() {
        let raw = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let lines = WorkspaceThumbnailText.lines(from: raw)
        #expect(lines?.count == WorkspaceThumbnailText.maxLines)
        #expect(lines?.last == "line 100")

        let wide = WorkspaceThumbnailText.lines(from: String(repeating: "w", count: 500))
        #expect(wide?.first?.count == WorkspaceThumbnailText.maxColumns)
    }

    @Test func uniformImageIsDetected() {
        let black = OverlayFixtures.solidImage(.black)
        let striped = OverlayFixtures.solidImage(.black, stripe: .white)
        #expect(WorkspaceThumbnailImage.isUniform(black))
        #expect(!WorkspaceThumbnailImage.isUniform(striped))
    }

    @Test func uniformImageFallsBackToText() {
        let black = OverlayFixtures.solidImage(.black)
        let content = WorkspaceThumbnailContent.resolve(image: black, text: ["$ ls"])
        guard case .text(let lines) = content else {
            Issue.record("expected text fallback, got \(content)")
            return
        }
        #expect(lines == ["$ ls"])
    }

    @Test func realImageWinsOverText() {
        let striped = OverlayFixtures.solidImage(.black, stripe: .white)
        let content = WorkspaceThumbnailContent.resolve(image: striped, text: ["$ ls"])
        guard case .image = content else {
            Issue.record("expected image, got \(content)")
            return
        }
    }

    @Test func nothingAvailableIsBlank() {
        guard case .blank = WorkspaceThumbnailContent.resolve(image: nil, text: nil) else {
            Issue.record("expected blank")
            return
        }
        guard case .blank = WorkspaceThumbnailContent.resolve(image: OverlayFixtures.solidImage(.black), text: nil) else {
            Issue.record("expected blank for a uniform image without text")
            return
        }
    }

    @Test func storeSourceFallsBackToTextWhenThereIsNoUsableMetalImage() throws {
        let store = WorkspaceFixtures.makeStore()
        let view = MockView()
        let workspace = try store.addWorkspace(name: "api", directory: URL(fileURLWithPath: "/tmp/ws-home/api")) {
            WorkspaceFixtures.makeTab(views: [view])
        }
        let tab = try #require(workspace.selectedTab)
        let source = StoreThumbnailSource(store: store) { _ in "$ ls\nREADME\n" }

        guard case .text(let withoutImage) = WorkspaceThumbnailContent.resolve(
            image: source.image(for: tab.id), text: source.text(for: tab.id)
        ) else {
            Issue.record("expected text when no snapshot exists")
            return
        }
        #expect(withoutImage == ["$ ls", "README"])

        store.snapshots.store(OverlayFixtures.solidImage(.black), for: tab.id)
        guard case .text(let withBlackImage) = WorkspaceThumbnailContent.resolve(
            image: source.image(for: tab.id), text: source.text(for: tab.id)
        ) else {
            Issue.record("expected text when the snapshot is uniform")
            return
        }
        #expect(withBlackImage == ["$ ls", "README"])

        store.snapshots.store(OverlayFixtures.solidImage(.black, stripe: .white), for: tab.id)
        guard case .image = WorkspaceThumbnailContent.resolve(
            image: source.image(for: tab.id), text: source.text(for: tab.id)
        ) else {
            Issue.record("expected the real image once the snapshot has content")
            return
        }
    }

    @Test func storeSourceReadsTheFocusedSurfaceOfTheTab() throws {
        let store = WorkspaceFixtures.makeStore()
        let first = MockView()
        let second = MockView()
        let workspace = try store.addWorkspace(name: "api", directory: URL(fileURLWithPath: "/tmp/ws-home/api")) {
            WorkspaceFixtures.makeTab(views: [first, second])
        }
        let tab = try #require(workspace.selectedTab)
        let screens: [UUID: String] = [first.id: "first screen\n", second.id: "second screen\n"]
        let source = StoreThumbnailSource(store: store) { screens[$0.id] ?? "" }

        #expect(source.text(for: tab.id) == ["first screen"])
        store.updateTab(workspaceID: workspace.id, tabID: tab.id) { $0.focusedSurfaceID = second.id }
        #expect(source.text(for: tab.id) == ["second screen"])
        #expect(source.text(for: UUID()) == nil)

        #expect(source.image(for: tab.id) == nil)
        store.snapshots.store(OverlayFixtures.solidImage(.black), for: tab.id)
        #expect(source.image(for: tab.id) != nil)
    }
}
