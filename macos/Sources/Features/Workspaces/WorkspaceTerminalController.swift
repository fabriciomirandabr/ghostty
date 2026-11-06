import AppKit
import Combine
import GhosttyKit
import SwiftUI

enum WorkspaceTabNavigation {
    static func isGotoTabPerformable(tabCount: Int, isWorkspaceSurface: Bool) -> Bool {
        isWorkspaceSurface || tabCount > 1
    }

    static func targetIndex(rawValue: Int32, current: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }

        if rawValue > 0 {
            return min(Int(rawValue) - 1, count - 1)
        }

        switch rawValue {
        case GHOSTTY_GOTO_TAB_PREVIOUS.rawValue: return (current - 1 + count) % count
        case GHOSTTY_GOTO_TAB_NEXT.rawValue: return (current + 1) % count
        case GHOSTTY_GOTO_TAB_LAST.rawValue: return count - 1
        default: return nil
        }
    }
}

final class WorkspaceTerminalController: TerminalController, WorkspaceStoreDelegate {
    typealias ViewType = Ghostty.SurfaceView

    let store: WorkspaceStore<Ghostty.SurfaceView>

    let overlayState = WorkspaceOverlayState()
    let titlebarViewModel: WorkspaceTitlebarViewModel
    private(set) lazy var thumbnails = store.makeThumbnailSource()

    @Published private(set) var overlaySnapshot = WorkspaceOverlaySnapshot(workspaces: [])

    var isOverviewShowing: Bool {
        get { overlayState.isOpen(.overview) }
        set { setOverlay(.overview, open: newValue) }
    }

    var isSwitcherShowing: Bool {
        get { overlayState.isOpen(.switcher) }
        set { setOverlay(.switcher, open: newValue) }
    }

    var isActivityPopoverShowing: Bool {
        get { overlayState.isOpen(.activityPopover) }
        set { setOverlay(.activityPopover, open: newValue) }
    }

    var isNewWorkspaceSheetShowing: Bool {
        get { overlayState.isOpen(.newWorkspace) }
        set { setOverlay(.newWorkspace, open: newValue) }
    }

    var pendingWorkspaceClose: UUID? {
        overlayState.closeConfirmation?.workspaceID
    }

    private var isPresentingTab = false
    private var storeCancellable: AnyCancellable?
    private var overlayCancellable: AnyCancellable?
    private var menuCancellable: AnyCancellable?
    private var renameCancellable: AnyCancellable?
    private var activityCancellable: AnyCancellable?
    private var resumeCancellable: AnyCancellable?
    private var jobCancellables: [AnyCancellable] = []
    private lazy var jobNotifier = WorkspaceJobNotifier(
        sink: WorkspaceJobNotificationCenterSink(),
        isEnabled: { [ghostty = self.ghostty] in
            WorkspaceJobNotifier.isEnabled(
                workspaceNotifications: ghostty.config.workspaceNotifications,
                desktopNotifications: ghostty.config.desktopNotifications)
        }
    )
    private var chromeRefreshPending = false
    private lazy var chromeThrottle = WorkspaceChromeRefreshThrottle { [weak self] in
        self?.refreshChrome()
    }
    private var persistGate = WorkspacePersistGate()
    private var powerCancellable: AnyCancellable?
    private var popoverHoverItem: DispatchWorkItem?
    private var snapshotTimer: Timer?
    private var escapeMonitor: Any?
    private var currentFontSize: Int?
    private var observedSurfaceIDs: [UUID] = []
    private var wasOverlayOpen = false
    private let persistence = WorkspacePersistence.shared

    init(
        _ ghostty: Ghostty.App,
        withBaseConfig base: Ghostty.SurfaceConfiguration? = nil,
        withSurfaceTree tree: SplitTree<Ghostty.SurfaceView>? = nil,
        restoring state: WorkspacesState<Ghostty.SurfaceView>? = nil,
        origin: WorkspaceWindowOrigin = .fresh
    ) {
        guard let app = ghostty.app else { preconditionFailure("app must be loaded") }

        let defaultDirectory = WorkspaceDefaultDirectory.resolve(ghostty.config.workspaceDefaultDirectory)
        let store: WorkspaceStore<Ghostty.SurfaceView>
        if let state {
            store = WorkspaceStore(restoring: state, defaultDirectory: defaultDirectory) {
                WorkspaceTerminalController.makeShellTab(app, directory: defaultDirectory)
            }
            if let base, let defaultWorkspace = store.workspaces.first {
                let tab = Self.makeRequestedTab(app, base: base, directory: defaultWorkspace.directory)
                store.addTab(tab, to: defaultWorkspace.id)
                store.select(workspaceID: defaultWorkspace.id, tabID: tab.id)
            }
        } else {
            let firstTree = tree ?? SplitTree(view: Ghostty.SurfaceView(
                app,
                baseConfig: WorkspaceSurfaceConfiguration.make(base: base, directory: defaultDirectory)))
            store = WorkspaceStore(defaultDirectory: defaultDirectory) {
                guard let tab = WorkspaceTab(tree: firstTree) else {
                    preconditionFailure("the initial surface tree must not be empty")
                }
                return tab
            }
        }
        self.store = store
        self.titlebarViewModel = WorkspaceTitlebarViewModel(
            fontFamily: ghostty.config.windowTitleFontFamily,
            shortcut: { ghostty.config.keyboardShortcut(for: $0) })
        self.currentFontSize = ghostty.config.fontSize

        super.init(ghostty, withBaseConfig: base, withSurfaceTree: store.selectedTab?.tree)

        if state != nil {
            persistence.register(self, origin: .restoredWorkspaces, state: persistedState())
        } else {
            persistence.register(self, origin: origin)
        }
        store.delegate = self
        Self.registerOwner(self, of: store.allSurfaces)
        WorkspaceJobNotificationCenterSink.requestAuthorizationIfEnabled(
            workspaceNotifications: ghostty.config.workspaceNotifications,
            desktopNotifications: ghostty.config.desktopNotifications)
        overlayState.foregroundProcessTabs = { [weak self] workspaceID in
            guard let self else { return [] }
            return WorkspaceWindowPolicy.tabsNeedingConfirmation(workspaceID: workspaceID, in: self.store)
        }

        storeCancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.scheduleChromeRefresh()
            DispatchQueue.main.async { self?.invalidateRestorableState() }
        }

        titlebarViewModel.actions = makeTitlebarActions()
        bindChrome()
        scheduleChromeRefresh()

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(workspaceDidCloseSurface(_:)),
            name: Ghostty.Notification.ghosttyCloseSurface,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(workspaceDidNewSplit(_:)),
            name: Ghostty.Notification.ghosttyNewSplit,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onNewWorkspace(_:)),
            name: Ghostty.Notification.ghosttyNewWorkspace,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onCloseWorkspace(_:)),
            name: Ghostty.Notification.ghosttyCloseWorkspace,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onGotoWorkspace(_:)),
            name: Ghostty.Notification.ghosttyGotoWorkspace,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onToggleWorkspaceOverview(_:)),
            name: Ghostty.Notification.ghosttyToggleWorkspaceOverview,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onToggleWorkspaceSwitcher(_:)),
            name: Ghostty.Notification.ghosttyToggleWorkspaceSwitcher,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onToggleActivityPopover(_:)),
            name: Ghostty.Notification.ghosttyToggleActivityPopover,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    static func persistedWorkspaces(forNewWindowIn ghostty: Ghostty.App) -> WorkspacesState<Ghostty.SurfaceView>? {
        guard ghostty.config.usesWorkspaceWindow else { return nil }
        return makeWorkspacesState(in: ghostty) {
            WorkspacePersistence.shared.loadForNewWindow(enabled: $0)
        }
    }

    static func persistedWorkspaces(forLaunchRecoveryIn ghostty: Ghostty.App) -> WorkspacesState<Ghostty.SurfaceView>? {
        guard ghostty.config.usesWorkspaceWindow else { return nil }
        return makeWorkspacesState(in: ghostty) {
            WorkspacePersistence.shared.loadForRecovery(enabled: $0)
        }
    }

    private static func makeWorkspacesState(
        in ghostty: Ghostty.App,
        load: (Bool) -> WorkspacePersistedState?
    ) -> WorkspacesState<Ghostty.SurfaceView>? {
        guard let app = ghostty.app else { return nil }

        guard let persisted = load(ghostty.config.windowSaveState != "never") else { return nil }

        let resumeEnabled = ghostty.config.workspaceResumePrograms
        let state = persisted.makeWorkspacesState { directory, resume -> SplitTree<Ghostty.SurfaceView> in
            let view = Ghostty.SurfaceView(
                app,
                baseConfig: WorkspaceSurfaceConfiguration.make(
                    base: nil,
                    directory: directory,
                    resume: resume,
                    enabled: resumeEnabled))
            if let seeded = ProgramResume.restored(resume, directoryExists: true, enabled: resumeEnabled) {
                view.seedProgramResume(seeded)
            }
            return SplitTree(view: view)
        }
        Ghostty.logger.info("restoring workspaces from file: \(state.workspaces.count, privacy: .public) workspaces")
        return state
    }

    private static func makeRequestedTab(
        _ app: ghostty_app_t,
        base: Ghostty.SurfaceConfiguration,
        directory: URL
    ) -> WorkspaceTab<Ghostty.SurfaceView> {
        var config = base
        if config.workingDirectory == nil {
            config.workingDirectory = directory.path
        }
        let tree = SplitTree(view: Ghostty.SurfaceView(app, baseConfig: config))
        guard let tab = WorkspaceTab(tree: tree) else {
            preconditionFailure("a single surface tree is never empty")
        }
        return tab
    }

    private var persistenceEnabled: Bool {
        ghostty.config.windowSaveState != "never"
    }

    private func persistedState() -> WorkspacePersistedState {
        let resumeEnabled = ghostty.config.workspaceResumePrograms
        return WorkspacePersistedState(
            store: store,
            directory: { $0.pwd },
            resume: { resumeEnabled ? $0.programResume : nil })
    }

    private func schedulePersistIfChanged() {
        persistGate.persistIfNeeded(
            persistedState(),
            enabled: persistenceEnabled,
            owner: self,
            persistence: persistence)
    }

    func persistenceRoleDidPass() {
        persistGate.reset()
        chromeThrottle.request()
    }

    func persistNow() {
        recordFocusInSelectedTab()
        persistence.flush(persistedState(), from: self, enabled: persistenceEnabled)
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        persistNow()
    }

    static func isWorkspaceSurface(_ surface: Ghostty.SurfaceView) -> Bool {
        BaseTerminalController.controller(owning: surface) is WorkspaceTerminalController
    }

    static func makeShellTab(_ app: ghostty_app_t, directory: URL) -> WorkspaceTab<Ghostty.SurfaceView> {
        let config = WorkspaceSurfaceConfiguration.make(base: nil, directory: directory)
        let tree = SplitTree(view: Ghostty.SurfaceView(app, baseConfig: config))
        guard let tab = WorkspaceTab(tree: tree) else {
            preconditionFailure("a single surface tree is never empty")
        }
        return tab
    }

    override func owns(_ surface: Ghostty.SurfaceView) -> Bool {
        WorkspaceWindowPolicy.owns(surface, in: store)
    }

    override var ownedSurfaces: [Ghostty.SurfaceView] {
        store.allSurfaces
    }

    static func workspaceID(containing surface: Ghostty.SurfaceView) -> UUID? {
        guard let controller = BaseTerminalController.controller(owning: surface) as? WorkspaceTerminalController
        else { return nil }
        return WorkspaceWindowPolicy.workspaceID(containing: surface, in: controller.store)
    }

    static func isCloseWorkspacePerformable(for surface: Ghostty.SurfaceView) -> Bool {
        guard let controller = BaseTerminalController.controller(owning: surface) as? WorkspaceTerminalController
        else { return false }
        return WorkspaceWindowPolicy.canCloseSelectedWorkspace(controller.store)
    }

    override func surfacesDidLeaveTree(_ surfaces: [Ghostty.SurfaceView]) {
        var departed: [Ghostty.SurfaceView] = []
        for surface in surfaces {
            if store.contains(surface) {
                dismissClipboardConfirmationSheet(for: surface)
            } else {
                departed.append(surface)
            }
        }

        if !departed.isEmpty {
            super.surfacesDidLeaveTree(departed)
        }
    }

    func surfacesDidEnter(_ surfaces: [Ghostty.SurfaceView]) {
        Self.registerOwner(self, of: surfaces)
        syncSurfaceTreeOcclusionState()
    }

    func surfacesDidLeave(_ surfaces: [Ghostty.SurfaceView]) {
        Self.unregisterOwner(self, of: surfaces)
        for surface in surfaces where !surfaceTree.contains(surface) {
            cancelPendingClipboardConfirmation(for: surface)
        }
    }

    override var hasSurfaceNeedingQuitConfirmation: Bool {
        !WorkspaceWindowPolicy.canCloseWithoutConfirmation(store)
    }

    override func surfaceTreeDidChange(
        from: SplitTree<Ghostty.SurfaceView>,
        to: SplitTree<Ghostty.SurfaceView>
    ) {
        if !isPresentingTab,
           !to.isEmpty,
           let workspace = store.selectedWorkspace,
           let tab = workspace.selectedTab {
            store.updateTab(workspaceID: workspace.id, tabID: tab.id) { $0.setTree(to) }
        }

        super.surfaceTreeDidChange(from: from, to: to)
    }

    override func surfaceTreeDidBecomeEmpty() {
        guard !isPresentingTab else { return }
        closeTabImmediately(registerRedo: false)
    }

    override func makeTerminalViewContainer() -> TerminalViewContainer {
        TerminalViewContainer {
            WorkspaceWindowContent(controller: self, ghostty: ghostty, overlayState: overlayState)
        }
    }

    private func setOverlay(_ kind: WorkspaceOverlay.Kind, open: Bool) {
        guard open != overlayState.isOpen(kind) else { return }

        if !open {
            overlayState.dismiss(kind)
            return
        }

        switch kind {
        case .overview: overlayState.present(.overview)
        case .newWorkspace: overlayState.present(.newWorkspace)
        case .activityPopover: overlayState.present(.activityPopover)
        case .switcher: overlayState.present(.switcher)
        case .closeConfirmation: break
        }
    }

    private func scheduleChromeRefresh() {
        guard !chromeRefreshPending else { return }
        chromeRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshChrome()
        }
    }

    private func refreshChrome() {
        chromeRefreshPending = false
        chromeThrottle.noteRefreshed()

        let surfaces = store.allSurfaces
        let ids = surfaces.map(\.id)
        if ids != observedSurfaceIDs {
            observeJobActivity(surfaces, previousIDs: observedSurfaceIDs)
            observedSurfaceIDs = ids
            activityCancellable = Publishers.MergeMany(surfaces.map(Self.changes(of:)))
                .sink { [weak self] _ in self?.chromeThrottle.request() }
            resumeCancellable = Publishers.MergeMany(surfaces.map(Self.resumeChanges(of:)))
                .sink { [weak self] _ in self?.invalidateRestorableState() }
        }

        titlebarViewModel.apply(WorkspaceTitlebarSnapshot.make(
            store: store,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            fontSize: currentFontSize,
            canSplit: focusedSurface?.surfaceModel != nil,
            activity: { $0.activityState },
            surfaceTitle: { Self.focusedSurface(of: $0)?.title ?? "" },
            surfacePwd: { Self.focusedSurface(of: $0)?.pwd }))

        let snapshot = currentOverlaySnapshot()
        if snapshot != overlaySnapshot {
            overlaySnapshot = snapshot
        }

        schedulePersistIfChanged()
    }

    private func observeJobActivity(_ surfaces: [Ghostty.SurfaceView], previousIDs: [UUID]) {
        let current = Set(surfaces.map(\.id))
        for id in previousIDs where !current.contains(id) {
            jobNotifier.forget(surfaceID: id)
        }

        jobCancellables = surfaces.map { surface in
            surface.$activityState.sink { [weak self, weak surface] _ in
                guard let self, let surface else { return }
                self.jobNotifier.activityDidChange(
                    surfaceID: surface.id,
                    activity: surface.jobActivity,
                    context: { self.jobContext(for: surface) })
            }
        }
    }

    private func jobContext(for surface: Ghostty.SurfaceView) -> WorkspaceJobContext? {
        guard let workspace = store.workspace(containing: surface),
              let tab = workspace.tab(containing: surface) else { return nil }

        let titled = Self.focusedSurface(of: tab)
        let override = WorkspaceTabTitle.override(tab.titleOverride)
        let tabName = override ?? WorkspaceTabTitle.resolve(title: titled?.title ?? "", pwd: titled?.pwd)
        let windowIsKey = window.map { $0.isKeyWindow && $0.isVisible && $0.occlusionState.contains(.visible) } ?? false

        return WorkspaceJobContext(
            tabName: tabName,
            workspaceName: workspace.name,
            workspaceID: workspace.id,
            visibility: WorkspaceJobVisibility(
                windowIsKey: windowIsKey,
                appIsActive: NSApp.isActive,
                workspaceIsSelected: workspace.id == store.selectedWorkspaceID,
                tabIsSelected: tab.id == workspace.selectedTabID,
                surfaceIsFocused: surface.focused))
    }

    @discardableResult
    func focus(surfaceID: UUID, inWorkspace workspaceID: UUID) -> Bool {
        guard let workspace = store.workspace(id: workspaceID),
              let tab = workspace.tabs.first(where: { $0.tree.contains { $0.id == surfaceID } }) else { return false }

        select(workspaceID: workspaceID, tabID: tab.id, surfaceID: surfaceID)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    private func currentOverlaySnapshot() -> WorkspaceOverlaySnapshot {
        store.overlaySnapshot {
            WorkspaceSurfaceInfo(
                title: $0.title,
                lastCommand: $0.lastCommand,
                state: $0.activityState,
                pwd: $0.pwd)
        }
    }

    private static func changes(of surface: Ghostty.SurfaceView) -> AnyPublisher<Void, Never> {
        Publishers.Merge(
            WorkspaceSurfaceChanges.merged(
                activityState: surface.$activityState,
                title: surface.$title,
                lastCommand: surface.$lastCommand,
                pwd: surface.$pwd),
            resumeChanges(of: surface)
        ).eraseToAnyPublisher()
    }

    private static func resumeChanges(of surface: Ghostty.SurfaceView) -> AnyPublisher<Void, Never> {
        surface.$programResume.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
    }

    private static func focusedSurface(of tab: WorkspaceTab<Ghostty.SurfaceView>) -> Ghostty.SurfaceView? {
        let surfaces = Array(tab.tree)
        return surfaces.first { $0.id == tab.focusedSurfaceID } ?? surfaces.first
    }

    private func bindChrome() {
        powerCancellable = WorkspacePowerMonitor.shared.$mode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] mode in
                guard let self, self.snapshotTimer != nil else { return }
                self.stopSnapshotTimer()
                self.scheduleSnapshotTimer(interval: mode.snapshotInterval)
            }

        overlayCancellable = overlayState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.overlaysDidChange() }
        }

        renameCancellable = titlebarViewModel.$renamingTabID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] id in
                guard id == nil else { return }
                DispatchQueue.main.async { self?.returnFocusToTerminal() }
            }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.keyCode == Self.escapeKeyCode,
                  event.window === self.window,
                  self.overlayState.isAnyOpen || self.titlebarViewModel.isMenuPresented,
                  !(self.window?.firstResponder is NSText) else { return event }

            if self.titlebarViewModel.isMenuPresented {
                self.titlebarViewModel.dismissMenu()
            } else {
                self.overlayState.dismissTop()
            }
            return nil
        }
    }

    private static let escapeKeyCode: UInt16 = 53

    private func overlaysDidChange() {
        titlebarViewModel.isOverviewOpen = overlayState.isOpen(.overview)

        let anyOpen = overlayState.isAnyOpen
        defer { wasOverlayOpen = anyOpen }

        if anyOpen {
            if !wasOverlayOpen, window?.firstResponder is Ghostty.SurfaceView {
                window?.makeFirstResponder(window?.contentView)
            }
        } else if wasOverlayOpen {
            returnFocusToTerminal()
        }

        if overlayState.isOpen(.overview) {
            startSnapshotTimer()
        } else {
            stopSnapshotTimer()
        }
    }

    private func stopSnapshotTimer() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }

    private var windowAllowsSnapshotCapture: Bool {
        guard let window else { return false }
        return WorkspaceSnapshotCapture.isAllowed(
            isKeyWindow: window.isKeyWindow,
            isVisible: window.isVisible,
            isOccluded: !window.occlusionState.contains(.visible))
    }

    private func returnFocusToTerminal() {
        guard let window, window.isKeyWindow || window.isMainWindow else { return }
        guard !(window.firstResponder is Ghostty.SurfaceView) else { return }
        guard let target = focusedSurface ?? surfaceTree.first else { return }
        Ghostty.moveFocus(to: target)
    }

    private func startSnapshotTimer() {
        captureSelectedTabSnapshot()
        guard snapshotTimer == nil else { return }
        scheduleSnapshotTimer(interval: WorkspacePowerMonitor.shared.mode.snapshotInterval)
    }

    private func scheduleSnapshotTimer(interval: TimeInterval) {
        snapshotTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.windowAllowsSnapshotCapture else { return }
                self.captureSelectedTabSnapshot()
            }
        }
    }

    func captureSelectedTabSnapshot() {
        guard let tab = store.selectedTab else { return }

        let surfaces = Array(tab.tree)
        let target = surfaces.first { $0.id == tab.focusedSurfaceID } ?? surfaces.first
        guard let target, let window = target.window, let image = target.asImage else { return }
        store.snapshots.storeCapture(image, for: tab.id, screenScale: window.backingScaleFactor)
    }

    private func makeTitlebarActions() -> WorkspaceTitlebarActions {
        WorkspaceTitlebarActions(
            selectWorkspace: { [weak self] in self?.select(workspaceID: $0) },
            closeWorkspace: { [weak self] in self?.requestCloseWorkspace(id: $0) },
            selectTab: { [weak self] in self?.selectTab(id: $0) },
            closeTab: { [weak self] in self?.closeTab(id: $0) },
            renameTab: { [weak self] in self?.renameTab(id: $0, to: $1) },
            newTab: { [weak self] in self?.newTab(baseConfig: nil) },
            splitTerminal: { [weak self] in self?.splitFocusedTerminal($0) },
            newWorkspace: { [weak self] in self?.newWorkspace(nil) },
            switchWorkspace: { [weak self] in self?.isSwitcherShowing = true },
            showAll: { [weak self] in self?.isOverviewShowing = true },
            setFontSize: { [weak self] in self?.setFontSize($0) },
            toggleOverview: { [weak self] in self?.toggleWorkspaceOverview(nil) },
            badgeHoverChanged: { [weak self] in self?.activityHoverChanged($0) })
    }

    func splitFocusedTerminal(_ direction: SplitTerminalDirection) {
        guard let surface = focusedSurface?.surfaceModel else {
            Ghostty.logger.debug("split terminal ignored: no focused surface")
            return
        }
        if !surface.perform(action: direction.bindingAction) {
            Ghostty.logger.warning("action failed action=\(direction.bindingAction, privacy: .public)")
        }
    }

    func makeOverlayActions() -> WorkspaceOverlayActions {
        WorkspaceOverlayActions(
            selectWorkspace: { [weak self] in self?.select(workspaceID: $0) },
            selectTab: { [weak self] in self?.select(workspaceID: $0, tabID: $1, surfaceID: $2) },
            closeWorkspace: { [weak self] in self?.closeWorkspace(id: $0) },
            createWorkspace: { [weak self] in self?.rejection(creatingWorkspace: $0, in: $1) },
            activityHoverChanged: { [weak self] in self?.activityHoverChanged($0) })
    }

    private func rejection(creatingWorkspace name: String, in directory: URL) -> WorkspaceError? {
        do throws(WorkspaceError) {
            try createWorkspace(name: name, directory: directory)
            return nil
        } catch {
            return error
        }
    }

    private func activityHoverChanged(_ hovering: Bool) {
        popoverHoverItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.isActivityPopoverShowing = hovering
        }
        popoverHoverItem = item
        let delay = hovering ? ActivityPopoverTiming.openDelay : ActivityPopoverTiming.closeDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func renameTab(id: UUID, to name: String) {
        guard let workspace = store.selectedWorkspace, workspace.tab(id: id) != nil else { return }
        store.updateTab(workspaceID: workspace.id, tabID: id) { $0.titleOverride = name }
    }

    private func setFontSize(_ size: Int) {
        currentFontSize = size
        let action = "set_font_size:\(size)"
        for surface in store.allSurfaces {
            guard let handle = surface.surface else { continue }
            if !ghostty_surface_binding_action(handle, action, UInt(action.lengthOfBytes(using: .utf8))) {
                Ghostty.logger.warning("action failed action=\(action, privacy: .public)")
            }
        }
        scheduleChromeRefresh()
    }

    override func windowDidResize(_ notification: Notification) {
        super.windowDidResize(notification)
        (window as? WorkspacesTerminalWindow)?.alignTrafficLights()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        (window as? WorkspacesTerminalWindow)?.alignTrafficLights()
    }

    override func promptTabTitle() {
        titlebarViewModel.beginRenamingSelectedTab()
    }

    @IBAction override func changeTabTitle(_ sender: Any) {
        promptTabTitle()
    }

    override func focusedSurfaceDidChange(to: Ghostty.SurfaceView?) {
        super.focusedSurfaceDidChange(to: to)
        recordFocusInSelectedTab()
        scheduleChromeRefresh()
    }

    private func recordFocusInSelectedTab() {
        guard let workspace = store.selectedWorkspace,
              let tab = workspace.selectedTab,
              let focused = focusedSurface,
              tab.contains(focused),
              tab.focusedSurfaceID != focused.id else { return }

        store.updateTab(workspaceID: workspace.id, tabID: tab.id) { $0.focusedSurfaceID = focused.id }
    }

    func select(workspaceID: UUID, tabID: UUID? = nil, surfaceID: UUID? = nil) {
        recordFocusInSelectedTab()
        captureSelectedTabSnapshot()
        if let tabID, let surfaceID {
            store.updateTab(workspaceID: workspaceID, tabID: tabID) { tab in
                if tab.tree.contains(where: { $0.id == surfaceID }) {
                    tab.focusedSurfaceID = surfaceID
                }
            }
        }
        guard store.select(workspaceID: workspaceID, tabID: tabID) else { return }
        presentSelectedTab()
    }

    func selectTab(id: UUID) {
        select(workspaceID: store.selectedWorkspaceID, tabID: id)
    }

    func selectPreviousWorkspace() {
        recordFocusInSelectedTab()
        captureSelectedTabSnapshot()
        store.selectPrevious()
        presentSelectedTab()
    }

    func selectNextWorkspace() {
        recordFocusInSelectedTab()
        captureSelectedTabSnapshot()
        store.selectNext()
        presentSelectedTab()
    }

    func gotoWorkspace(index: Int) {
        recordFocusInSelectedTab()
        captureSelectedTabSnapshot()
        guard store.goto(index: index) else { return }
        presentSelectedTab()
    }

    private func presentSelectedTab() {
        guard let tab = store.selectedTab else { return }

        let previousTree = surfaceTree
        let previousFocus = focusedSurface
        undoManager?.removeAllActions(withTarget: self)

        isPresentingTab = true
        surfaceTree = tab.tree
        isPresentingTab = false

        for surface in previousTree where !tab.tree.contains(surface) {
            surface.focusDidChange(false)
        }

        let target = tab.focusedSurfaceID.flatMap { id in tab.tree.first { $0.id == id } } ?? tab.tree.first
        if let target {
            focusedSurface = target
            DispatchQueue.main.async {
                Ghostty.moveFocus(to: target, from: previousFocus)
            }
        }

        invalidateRestorableState()
    }

    @discardableResult
    func newTab(baseConfig: Ghostty.SurfaceConfiguration?) -> Ghostty.SurfaceView? {
        guard let app = ghostty.app, let workspace = store.selectedWorkspace else { return nil }

        let config = WorkspaceSurfaceConfiguration.make(base: baseConfig, workspace: workspace)
        let view = Ghostty.SurfaceView(app, baseConfig: config)
        guard let tab = WorkspaceTab(tree: SplitTree(view: view)) else { return nil }

        recordFocusInSelectedTab()
        captureSelectedTabSnapshot()
        store.addTab(tab, to: workspace.id)
        presentSelectedTab()
        return view
    }

    @discardableResult
    override func newSplit(
        at oldView: Ghostty.SurfaceView,
        direction: SplitTree<Ghostty.SurfaceView>.NewDirection,
        baseConfig config: Ghostty.SurfaceConfiguration?
    ) -> Ghostty.SurfaceView? {
        guard let workspace = store.workspace(containing: oldView) else { return nil }

        return super.newSplit(
            at: oldView,
            direction: direction,
            baseConfig: WorkspaceSurfaceConfiguration.make(base: config, workspace: workspace))
    }

    func createWorkspace(name: String, directory: URL) throws(WorkspaceError) {
        guard let app = ghostty.app else { return }

        let workspace = try store.addWorkspace(name: name, directory: directory) {
            WorkspaceTerminalController.makeShellTab(app, directory: directory)
        }
        select(workspaceID: workspace.id)
    }

    @discardableResult
    func closeWorkspace(id: UUID) -> Bool {
        let wasSelected = store.selectedWorkspaceID == id
        guard store.closeWorkspace(id: id) else { return false }

        if pendingWorkspaceClose == id {
            overlayState.dismiss(.closeConfirmation)
        }
        if wasSelected {
            presentSelectedTab()
        }
        return true
    }

    func requestCloseWorkspace(id: UUID) {
        overlayState.requestClose(
            workspaceID: id,
            anchor: .titlebar,
            in: currentOverlaySnapshot()
        ) { [weak self] in
            self?.closeWorkspace(id: $0)
        }
    }

    override func closeSurface(
        _ node: SplitTree<Ghostty.SurfaceView>.Node,
        withConfirmation: Bool
    ) {
        guard surfaceTree.root == node else {
            super.closeSurface(node, withConfirmation: withConfirmation)
            return
        }

        if withConfirmation {
            closeTab(nil)
        } else {
            closeTabImmediately(registerRedo: false)
        }
    }

    @IBAction override func closeTab(_ sender: Any?) {
        guard let tab = store.selectedTab else { return }

        guard tab.tree.contains(where: { $0.needsConfirmQuit }) else {
            closeTabImmediately(registerRedo: false)
            return
        }

        confirmClose(
            messageText: "Close Tab?",
            informativeText: "The terminal still has a running process. If you close the tab the process will be killed."
        ) { [weak self] in
            self?.closeTabImmediately(registerRedo: false)
        }
    }

    func closeTab(id: UUID) {
        guard let workspace = store.selectedWorkspace,
              let tab = workspace.tab(id: id) else { return }

        guard tab.tree.contains(where: { $0.needsConfirmQuit }) else {
            removeTab(id: id)
            return
        }

        confirmClose(
            messageText: "Close Tab?",
            informativeText: "The terminal still has a running process. If you close the tab the process will be killed."
        ) { [weak self] in
            self?.removeTab(id: id)
        }
    }

    private func removeTab(id: UUID) {
        guard let app = ghostty.app,
              let workspace = store.selectedWorkspace,
              workspace.tab(id: id) != nil else { return }

        let wasSelected = workspace.selectedTabID == id
        if wasSelected {
            captureSelectedTabSnapshot()
        }

        let directory = workspace.directory
        store.removeTab(workspaceID: workspace.id, tabID: id) {
            WorkspaceTerminalController.makeShellTab(app, directory: directory)
        }

        if wasSelected {
            presentSelectedTab()
        }
    }

    override func closeTabImmediately(registerRedo: Bool) {
        guard let tab = store.selectedTab else { return }
        removeTab(id: tab.id)
    }

    @IBAction override func closeWindow(_ sender: Any?) {
        guard window != nil else { return }

        guard !hasSurfaceNeedingQuitConfirmation else {
            confirmClose(
                messageText: "Close Window?",
                informativeText: "All terminal sessions in this window will be terminated."
            ) { [weak self] in
                self?.closeWindowImmediately()
            }
            return
        }

        closeWindowImmediately()
    }

    override func closeWindowImmediately() {
        cancelPendingInitialPresentation()
        window?.close()
    }

    override func windowCanBeClosedWithoutConfirmation() -> Bool {
        guard super.windowCanBeClosedWithoutConfirmation() else { return false }
        return WorkspaceWindowPolicy.canCloseWithoutConfirmation(store)
    }

    override func windowWillClose(_ notification: Notification) {
        stopSnapshotTimer()
        store.snapshots.clear()
        popoverHoverItem?.cancel()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        for surface in store.allSurfaces where !surfaceTree.contains(surface) {
            surface.pendingClipboardConfirmation = nil
        }
        persistNow()
        persistence.unregister(self)
        (persistence.primaryWindow as? WorkspaceTerminalController)?.persistenceRoleDidPass()
        super.windowWillClose(notification)
    }

    override func relabelTabs() {}

    override func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        recordFocusInSelectedTab()
        let data = TerminalRestorableState(from: self, workspaces: store.makeState())
        data.encode(with: state)
    }

    @IBAction func newWorkspace(_ sender: Any?) {
        isNewWorkspaceSheetShowing = true
    }

    @IBAction func closeWorkspace(_ sender: Any?) {
        requestCloseWorkspace(id: store.selectedWorkspaceID)
    }

    @IBAction func toggleWorkspaceSwitcher(_ sender: Any?) {
        isSwitcherShowing.toggle()
    }

    @IBAction func toggleWorkspaceOverview(_ sender: Any?) {
        isOverviewShowing.toggle()
    }

    @IBAction func toggleActivityPopover(_ sender: Any?) {
        isActivityPopoverShowing.toggle()
    }

    @IBAction func selectPreviousWorkspace(_ sender: Any?) {
        selectPreviousWorkspace()
    }

    @IBAction func selectNextWorkspace(_ sender: Any?) {
        selectNextWorkspace()
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(closeWorkspace(_:)):
            return WorkspaceWindowPolicy.canCloseSelectedWorkspace(store)

        default:
            return super.validateMenuItem(item)
        }
    }

    @objc override func onGotoTab(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView, owns(target) else { return }
        guard let tabEnum = notification.userInfo?[Ghostty.Notification.GotoTabKey] as? ghostty_action_goto_tab_e,
              let workspace = store.selectedWorkspace else { return }

        let current = workspace.tabs.firstIndex { $0.id == workspace.selectedTabID } ?? 0
        guard let index = WorkspaceTabNavigation.targetIndex(
            rawValue: tabEnum.rawValue,
            current: current,
            count: workspace.tabs.count) else { return }

        selectTab(id: workspace.tabs[index].id)
    }

    @objc private func workspaceDidCloseSurface(_ notification: Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView,
              store.contains(target),
              !surfaceTree.contains(target) else { return }

        if (notification.userInfo?["process_alive"] as? Bool) ?? false {
            confirmClose(
                messageText: "Close Terminal?",
                informativeText: "The terminal still has a running process. If you close the terminal the process will be killed."
            ) { [weak self] in
                self?.removeHiddenSurface(target)
            }
        } else {
            removeHiddenSurface(target)
        }
    }

    private func removeHiddenSurface(_ surface: Ghostty.SurfaceView) {
        guard let app = ghostty.app, let workspace = store.workspace(containing: surface) else { return }

        let directory = workspace.directory
        store.remove(surface: surface) {
            WorkspaceTerminalController.makeShellTab(app, directory: directory)
        }
    }

    @objc private func workspaceDidNewSplit(_ notification: Notification) {
        guard let oldView = notification.object as? Ghostty.SurfaceView,
              store.contains(oldView),
              !surfaceTree.contains(oldView),
              let direction = Self.newSplitDirection(from: notification),
              let app = ghostty.app,
              let workspace = store.workspace(containing: oldView) else { return }

        let baseConfig = notification.userInfo?[Ghostty.Notification.NewSurfaceConfigKey]
            as? Ghostty.SurfaceConfiguration
        let newView = Ghostty.SurfaceView(
            app,
            baseConfig: WorkspaceSurfaceConfiguration.make(base: baseConfig, workspace: workspace))

        do {
            try store.insert(view: newView, at: oldView, direction: direction)
        } catch {
            Ghostty.logger.warning("failed to insert split into hidden tab: \(error, privacy: .public)")
        }
    }

    @objc private func onNewWorkspace(_ notification: Notification) {
        guard ownsNotificationTarget(notification) else { return }
        newWorkspace(nil)
    }

    @objc private func onCloseWorkspace(_ notification: Notification) {
        guard ownsNotificationTarget(notification) else { return }
        requestCloseWorkspace(id: store.selectedWorkspaceID)
    }

    @objc private func onGotoWorkspace(_ notification: Notification) {
        guard ownsNotificationTarget(notification),
              let value = notification.userInfo?[Ghostty.Notification.GotoWorkspaceKey]
                as? ghostty_action_goto_workspace_e else { return }

        switch value.rawValue {
        case GHOSTTY_GOTO_WORKSPACE_PREVIOUS.rawValue: selectPreviousWorkspace()
        case GHOSTTY_GOTO_WORKSPACE_NEXT.rawValue: selectNextWorkspace()
        default: gotoWorkspace(index: Int(value.rawValue))
        }
    }

    @objc private func onToggleWorkspaceOverview(_ notification: Notification) {
        guard ownsNotificationTarget(notification) else { return }
        toggleWorkspaceOverview(nil)
    }

    @objc private func onToggleWorkspaceSwitcher(_ notification: Notification) {
        guard ownsNotificationTarget(notification) else { return }
        toggleWorkspaceSwitcher(nil)
    }

    @objc private func onToggleActivityPopover(_ notification: Notification) {
        guard ownsNotificationTarget(notification) else { return }
        toggleActivityPopover(nil)
    }

    private func ownsNotificationTarget(_ notification: Notification) -> Bool {
        guard let target = notification.object as? Ghostty.SurfaceView else { return false }
        return owns(target)
    }
}
