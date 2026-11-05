import AppKit
import SwiftUI
import Testing
@testable import Ghostty

@MainActor
struct WorkspaceRootViewTests {
    private func render(height: CGFloat) throws -> NSBitmapImageRep {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let container = TerminalViewContainer {
            WorkspaceRootView(
                titlebarHeight: height,
                titlebar: ZStack {
                    Color.red
                    Color.white.frame(width: 80, height: 24)
                },
                terminal: Color.blue,
                overlay: Color.clear)
        }
        window.contentView = container
        window.layoutIfNeeded()
        container.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let rep = try #require(container.bitmapImageRepForCachingDisplay(in: container.bounds))
        container.cacheDisplay(in: container.bounds, to: rep)
        return rep
    }

    private func isWhite(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Bool {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
        return color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9
    }

    private func isBlue(_ rep: NSBitmapImageRep, x: Int, y: Int) -> Bool {
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
        return color.blueComponent > 0.8 && color.redComponent < 0.5
    }

    @Test func titlebarItemsAreCenteredInsideTheBar() throws {
        let height: CGFloat = 32
        let rep = try render(height: height)
        let x = 300
        let top = Int((height - 24) / 2) + 1
        let bottom = Int((height + 24) / 2) - 2

        #expect(isWhite(rep, x: x, y: Int(height / 2)))
        #expect(isWhite(rep, x: x, y: top))
        #expect(isWhite(rep, x: x, y: bottom))
    }

    @Test func terminalStartsBelowTheBar() throws {
        let height: CGFloat = 32
        let rep = try render(height: height)

        #expect(!isBlue(rep, x: 100, y: Int(height) - 2))
        #expect(isBlue(rep, x: 100, y: Int(height) + 2))
    }
}

private final class TerminalMarkerView: NSView {}

private struct TerminalMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalMarkerView { TerminalMarkerView() }
    func updateNSView(_ nsView: TerminalMarkerView, context: Context) {}
}

private struct SplitPanesPreview: View {
    var body: some View {
        HStack(spacing: 1) {
            pane(title: "shell", isActive: true, lines: [
                "~/code/api $ git status",
                "On branch main",
                "nothing to commit, working tree clean",
                "~/code/api $ npm test",
                "Tests: 42 passed, 42 total",
                "~/code/api $"
            ])
            pane(title: "server", isActive: false, lines: [
                "~/code/api $ npm run dev",
                "server listening on :3000",
                "GET /health 200 4ms",
                "GET /users 200 11ms"
            ])
        }
        .background(Color(white: 0.2))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func pane(title: String, isActive: Bool, lines: [String]) -> some View {
        VStack(spacing: 0) {
            SplitPaneHeaderView(title: title, isActive: isActive, onClose: {})
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index])
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(white: 0.85))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.11))
        }
    }
}

private final class DocThumbnails: WorkspaceThumbnailSource {
    private let lines: [UUID: [String]]

    init(lines: [UUID: [String]]) {
        self.lines = lines
    }

    func image(for tabID: UUID) -> NSImage? { nil }
    func text(for tabID: UUID) -> [String]? { lines[tabID] }
}

@MainActor
struct WorkspaceRootViewWindowTests {
    private struct Fixture {
        let window: WorkspacesTerminalWindow
        let container: TerminalViewContainer
        let metrics: WorkspaceTitlebarMetrics
    }

    private enum Shot: CaseIterable {
        case tabBar
        case menu
        case popover
        case grid
        case rename
        case splitHeaders

        var fileName: String {
            switch self {
            case .tabBar: "tab-bar.png"
            case .menu: "workspace-menu.png"
            case .popover: "activity-popover.png"
            case .grid: "workspace-grid.png"
            case .rename: "rename.png"
            case .splitHeaders: "split-headers.png"
            }
        }

        var cropsToBar: Bool {
            self == .tabBar || self == .rename
        }
    }

    private static let docSize = CGSize(width: 1200, height: 760)
    private static let barCropHeight: CGFloat = 48
    private static let docScale: CGFloat = 2

    private static let docWorkspaces: [(name: String, state: SurfaceActivityState, running: Int)] = [
        ("api", .running, 2),
        ("web", .needsAttention, 0),
        ("worker", .done, 0),
        ("docs", .idle, 0)
    ]

    private static let shortcuts: [String: KeyboardShortcut] = {
        var table: [String: KeyboardShortcut] = [
            "toggle_workspace_switcher": KeyboardShortcut("k", modifiers: .command),
            "new_workspace": KeyboardShortcut("g", modifiers: .command),
            "new_tab": KeyboardShortcut("t", modifiers: .command),
            "close_workspace": KeyboardShortcut("w", modifiers: [.command, .shift]),
            "toggle_workspace_overview": KeyboardShortcut("o", modifiers: .command)
        ]
        for index in 1...9 {
            table["goto_workspace:\(index)"] = KeyboardShortcut(
                KeyEquivalent(Character("\(index)")),
                modifiers: [.command, .option]
            )
        }
        return table
    }()

    private static func overlayWorkspaces() -> [WorkspaceSummary] {
        func directory(_ name: String) -> String { "\(NSHomeDirectory())/code/\(name)" }
        return [
            OverlayFixtures.workspace("api", directory: directory("api"), isCurrent: true, tabs: [
                TabSpec(title: "shell"),
                TabSpec(title: "tests", state: .running, command: "npm test")
            ]),
            OverlayFixtures.workspace("web", directory: directory("web"), tabs: [
                TabSpec(title: "server", state: .needsAttention, command: "pnpm dev"),
                TabSpec(title: "shell")
            ]),
            OverlayFixtures.workspace("worker", directory: directory("worker"), tabs: [
                TabSpec(title: "build", state: .done, command: "make build")
            ]),
            OverlayFixtures.workspace("docs", directory: directory("docs"), tabs: [
                TabSpec(title: "shell")
            ])
        ]
    }

    private static func thumbnailLines(for workspaces: [WorkspaceSummary]) -> [UUID: [String]] {
        let byName: [String: [String]] = [
            "api": ["~/code/api $ npm run dev", "server listening on :3000", "GET /health 200 4ms"],
            "web": ["~/code/web $ pnpm dev", "ready in 412 ms", "Proceed with install? (y/n)"],
            "worker": ["~/code/worker $ make build", "compiling 18 files", "build finished in 6.2s"],
            "docs": ["~/code/docs $"]
        ]
        return Dictionary(uniqueKeysWithValues: workspaces.map { ($0.selectedTabID, byName[$0.name] ?? []) })
    }

    private func makeFixture(shot: Shot = .tabBar, size: CGSize = CGSize(width: 700, height: 400)) -> Fixture {
        let window = WorkspacesTerminalWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.applyWorkspacesStyle()

        let metrics = WorkspaceTitlebarMetrics()
        metrics.update(from: window)

        let model = WorkspaceTitlebarViewModel(shortcut: { Self.shortcuts[$0] })
        let workspaces = Self.docWorkspaces.map {
            WorkspaceTitlebarWorkspace(
                id: UUID(), name: $0.name, folder: "~/code/\($0.name)", isDefault: false,
                state: $0.state, runningCount: $0.running)
        }
        let tabs = [
            WorkspaceTitlebarTab(id: UUID(), title: "shell", state: .idle),
            WorkspaceTitlebarTab(id: UUID(), title: "tests", state: .running),
            WorkspaceTitlebarTab(id: UUID(), title: "server", state: .needsAttention),
            WorkspaceTitlebarTab(id: UUID(), title: "build", state: .done)
        ]
        model.apply(WorkspaceTitlebarSnapshot(
            workspaces: workspaces,
            selectedWorkspaceID: workspaces[0].id,
            tabs: tabs,
            selectedTabID: tabs[0].id,
            badge: .init(runningCount: 2, needsAttention: true)))
        model.isMenuPresented = shot == .menu
        if shot == .rename { model.beginRename(tabID: tabs[1].id) }

        let overlayState = WorkspaceOverlayState()
        let allWorkspaces = Self.overlayWorkspaces()
        var overlayWorkspaces = allWorkspaces
        switch shot {
        case .popover:
            overlayState.present(.activityPopover)
            overlayWorkspaces = Array(allWorkspaces.prefix(2))
        case .grid:
            overlayState.present(.overview)
        default:
            break
        }
        let overlaySnapshot = OverlayFixtures.snapshot(overlayWorkspaces)
        let overlayActions = WorkspaceOverlayActions(
            selectWorkspace: { _ in },
            selectTab: { _, _, _ in },
            closeWorkspace: { _ in },
            createWorkspace: { _, _ in nil })
        let thumbnails = DocThumbnails(lines: Self.thumbnailLines(for: allWorkspaces))
        let barHeight = metrics.height
        let showsLayer = shot == .popover || shot == .grid
        let showsMenu = shot == .menu

        let container = TerminalViewContainer {
            WorkspaceRootView(
                titlebarHeight: metrics.height,
                titlebar: WorkspaceTitlebarView(viewModel: model, metrics: metrics),
                terminal: terminal(for: shot),
                overlay: ZStack(alignment: .topLeading) {
                    if showsLayer {
                        WorkspaceOverlayLayer(
                            titlebarHeight: barHeight,
                            snapshot: overlaySnapshot,
                            state: overlayState,
                            thumbnails: thumbnails,
                            terminalBackground: Color(white: 0.11),
                            terminalForeground: Color(white: 0.85),
                            actions: overlayActions)
                    }
                    if showsMenu {
                        WorkspaceMenuView(viewModel: model)
                            .fixedSize(horizontal: true, vertical: false)
                            .workspaceOverlayPanel(padding: 0)
                            .padding(.leading, metrics.leadingInset)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
        }
        window.contentView = container
        window.layoutIfNeeded()
        container.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        container.layoutSubtreeIfNeeded()
        return Fixture(window: window, container: container, metrics: metrics)
    }

    private func terminal(for shot: Shot) -> AnyView {
        switch shot {
        case .splitHeaders: AnyView(SplitPanesPreview())
        case .tabBar, .menu, .popover, .grid, .rename: AnyView(TerminalMarker())
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func windowRect(of view: NSView) -> CGRect {
        view.convert(view.bounds, to: nil)
    }

    private func titlebarHost(in fixture: Fixture) -> NSView? {
        descendants(of: fixture.container).first { view in
            view.mouseDownCanMoveWindow && String(describing: type(of: view)).hasPrefix("WindowDraggableHostingView")
        }
    }

    private func workspaceChevronMidY(in fixture: Fixture) -> CGFloat? {
        guard let host = titlebarHost(in: fixture),
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)

        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        let firstColumn = Int((fixture.metrics.leadingInset + WorkspaceMenuButton.horizontalPadding) * scale)
        let lastColumn = Int((fixture.metrics.leadingInset + WorkspaceMenuButton.horizontalPadding + 10) * scale)
        var rows: [Int] = []
        for row in 0..<rep.pixelsHigh {
            let isBright = (firstColumn...lastColumn).contains { column in
                guard let color = rep.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { return false }
                return color.redComponent > 0.8 && color.greenComponent > 0.8 && color.blueComponent > 0.8
            }
            if isBright { rows.append(row) }
        }
        guard let first = rows.first, let last = rows.last else { return nil }
        let midFromTop = CGFloat(first + last + 1) / 2 / scale
        return windowRect(of: host).maxY - midFromTop
    }

    @Test func barSitsInsideTheWindowAndAlignsWithTheTrafficLights() throws {
        let fixture = makeFixture()
        let window = fixture.window
        let host = try #require(titlebarHost(in: fixture))
        let bar = windowRect(of: host)
        let close = try #require(window.standardWindowButton(.closeButton))
        let closeRect = try #require(close.superview).convert(close.frame, to: nil)
        let buttonMidY = try #require(workspaceChevronMidY(in: fixture))

        #expect(bar.minY >= 0)
        #expect(bar.maxY <= window.frame.height + 0.5)
        #expect(abs(bar.maxY - window.frame.height) <= 0.5)
        #expect(abs(bar.height - fixture.metrics.height) <= 0.5)
        #expect(buttonMidY > bar.minY && buttonMidY < bar.maxY)
        #expect(abs(buttonMidY - closeRect.midY) <= 1)
    }

    @Test func terminalStartsAtTheBottomOfTheBar() throws {
        let fixture = makeFixture()
        let host = try #require(titlebarHost(in: fixture))
        let marker = try #require(descendants(of: fixture.container).first { $0 is TerminalMarkerView })

        #expect(abs(windowRect(of: marker).maxY - windowRect(of: host).minY) <= 0.5)
    }

    @Test func rendersDocumentationScreenshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["WORKSPACES_DOC_RENDER_DIR"] else { return }
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        for shot in Shot.allCases {
            let fixture = makeFixture(shot: shot, size: Self.docSize)
            let data = try pngData(of: fixture, cropHeight: shot.cropsToBar ? Self.barCropHeight : nil)
            try data.write(to: base.appendingPathComponent(shot.fileName))
        }
    }

    private func pngData(of fixture: Fixture, cropHeight: CGFloat?) throws -> Data {
        fixture.window.update()
        let frameView = try #require(fixture.window.contentView?.superview)
        let bounds = frameView.bounds
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * Self.docScale),
            pixelsHigh: Int(bounds.height * Self.docScale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)

        guard let cropHeight else {
            return try #require(rep.representation(using: .png, properties: [:]))
        }
        let image = try #require(rep.cgImage)
        let cropped = try #require(image.cropping(to: CGRect(
            x: 0, y: 0, width: image.width, height: Int(cropHeight * Self.docScale))))
        return try #require(NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]))
    }
}
