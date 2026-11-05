import Foundation

enum WorkspaceWindowOrigin {
    case fresh
    case restoredWorkspaces
    case restoredWithoutWorkspaces
}

@MainActor
final class WorkspacePersistence {
    static let shared = WorkspacePersistence(store: WorkspaceStateStore.shared)

    private struct WeakWindow {
        weak var object: AnyObject?
        let mayInherit: Bool
    }

    let store: WorkspaceStateStore
    private var windows: [WeakWindow] = []
    private weak var primary: AnyObject?
    private var lastPersisted: WorkspacePersistedState?
    private var holdsNewerFile = false
    private var heldBaseline: WorkspacePersistedState?
    private var fileWasMissing = false
    private var launchFile: WorkspacePersistedState?
    private var launchFileTaken = false

    init(store: WorkspaceStateStore) {
        self.store = store
        store.didWrite = { [weak self] state in
            self?.lastPersisted = state
        }
    }

    var primaryWindow: AnyObject? { primary }

    var hasWindows: Bool { !aliveWindows.isEmpty }

    private var aliveWindows: [AnyObject] {
        windows.compactMap(\.object)
    }

    @discardableResult
    func register(
        _ owner: AnyObject,
        origin: WorkspaceWindowOrigin,
        state: WorkspacePersistedState? = nil
    ) -> Bool {
        windows.removeAll { $0.object == nil }
        let others = aliveWindows.contains { $0 !== owner }
        let isNew = !windows.contains(where: { $0.object === owner })
        let matchesFile = origin == .restoredWorkspaces ? stateMatchesFile(state) : false
        if isNew {
            let mayInherit: Bool
            switch origin {
            case .restoredWorkspaces:
                mayInherit = matchesFile
            case .fresh:
                mayInherit = !others
            case .restoredWithoutWorkspaces:
                mayInherit = false
            }
            windows.append(WeakWindow(object: owner, mayInherit: mayInherit))
        }

        if primary == nil {
            switch origin {
            case .restoredWorkspaces:
                if matchesFile {
                    setPrimary(owner)
                }
            case .fresh:
                if !others {
                    setPrimary(owner)
                }
            case .restoredWithoutWorkspaces:
                break
            }
        }

        if isNew, origin == .restoredWorkspaces, let state, primary === owner {
            if fileWasMissing {
                lastPersisted = nil
                store.scheduleSave(state)
            } else {
                lastPersisted = state
                if holdsNewerFile {
                    heldBaseline = state
                }
            }
        }
        return primary === owner
    }

    private func stateMatchesFile(_ state: WorkspacePersistedState?) -> Bool {
        guard let state else { return true }
        let known = [launchFile, loadFile()].compactMap { $0 }
        guard !known.isEmpty else { return primary == nil }
        return known.contains { $0.sharesWorkspace(with: state) }
    }

    private func loadFile() -> WorkspacePersistedState? {
        let current = readFile()
        if !launchFileTaken {
            launchFileTaken = true
            launchFile = current
        }
        return current
    }

    private func readFile() -> WorkspacePersistedState? {
        fileWasMissing = false
        do {
            let loaded = try store.load()
            fileWasMissing = loaded == nil
            return loaded
        } catch WorkspaceStateStoreError.newerVersion(let found) {
            holdsNewerFile = true
            Ghostty.logger.warning(
                "workspace state file version \(found, privacy: .public) is newer than \(WorkspacePersistedState.currentVersion, privacy: .public); kept until a workspace or tab changes")
            return nil
        } catch {
            Ghostty.logger.warning("workspace state load failed: \(error, privacy: .public)")
            return nil
        }
    }

    func isPrimary(_ owner: AnyObject) -> Bool {
        primary === owner
    }

    func unregister(_ owner: AnyObject) {
        windows.removeAll { $0.object === owner || $0.object == nil }
        if primary === owner {
            setPrimary(windows.first { $0.mayInherit && $0.object != nil }?.object)
        }
    }

    private func setPrimary(_ owner: AnyObject?) {
        primary = owner
        heldBaseline = nil
    }

    func loadForNewWindow(enabled: Bool) -> WorkspacePersistedState? {
        guard enabled, !hasWindows else { return nil }
        return loadFile()
    }

    func loadForRecovery(enabled: Bool) -> WorkspacePersistedState? {
        guard enabled, primary == nil else { return nil }
        return loadFile()
    }

    func stateDidChange(_ state: WorkspacePersistedState, from owner: AnyObject, enabled: Bool) {
        guard isPrimary(owner) else { return }
        guard enabled else {
            disable()
            return
        }
        guard shouldWrite(state) else {
            store.cancelPending()
            return
        }
        store.scheduleSave(state)
    }

    func flush(_ state: WorkspacePersistedState, from owner: AnyObject, enabled: Bool) {
        guard isPrimary(owner) else { return }
        guard enabled else {
            disable()
            return
        }
        do {
            if shouldWrite(state) {
                try store.save(state)
            } else {
                store.cancelPending()
            }
        } catch {
            Ghostty.logger.warning("workspace state save failed: \(error, privacy: .public)")
        }
    }

    private func shouldWrite(_ state: WorkspacePersistedState) -> Bool {
        if holdsNewerFile {
            guard let baseline = heldBaseline else {
                heldBaseline = state
                lastPersisted = state
                return false
            }
            if state.hasSameStructure(as: baseline) {
                lastPersisted = state
                return false
            }
            holdsNewerFile = false
            heldBaseline = nil
        }
        return state != lastPersisted
    }

    private func disable() {
        lastPersisted = nil
        do {
            try store.delete()
        } catch {
            Ghostty.logger.warning("workspace state delete failed: \(error, privacy: .public)")
        }
    }
}
