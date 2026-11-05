import Foundation

enum WorkspaceOverviewSort: Equatable {
    case creation
    case name
    case activity
}

enum CloseConfirmationAnchor: Equatable {
    case titlebar
    case card
}

enum WorkspaceOverlay: Equatable {
    case overview
    case newWorkspace
    case activityPopover
    case closeConfirmation(workspaceID: UUID, anchor: CloseConfirmationAnchor)
    case switcher

    enum Kind: Int, Comparable {
        case overview
        case newWorkspace
        case activityPopover
        case closeConfirmation
        case switcher

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var kind: Kind {
        switch self {
        case .overview: return .overview
        case .newWorkspace: return .newWorkspace
        case .activityPopover: return .activityPopover
        case .closeConfirmation: return .closeConfirmation
        case .switcher: return .switcher
        }
    }
}

@MainActor
final class WorkspaceOverlayState: ObservableObject {
    @Published private(set) var overlays: [WorkspaceOverlay] = []
    @Published var sort: WorkspaceOverviewSort = .creation
    var foregroundProcessTabs: (UUID) -> Set<UUID> = { _ in [] }

    var top: WorkspaceOverlay? {
        overlays.last
    }

    var isAnyOpen: Bool {
        !overlays.isEmpty
    }

    func isOpen(_ kind: WorkspaceOverlay.Kind) -> Bool {
        overlay(of: kind) != nil
    }

    func overlay(of kind: WorkspaceOverlay.Kind) -> WorkspaceOverlay? {
        overlays.first { $0.kind == kind }
    }

    var closeConfirmation: (workspaceID: UUID, anchor: CloseConfirmationAnchor)? {
        guard case .closeConfirmation(let workspaceID, let anchor)? = overlay(of: .closeConfirmation) else {
            return nil
        }
        return (workspaceID, anchor)
    }

    func present(_ overlay: WorkspaceOverlay) {
        switch overlay.kind {
        case .newWorkspace:
            if !isOpen(.overview) { insert(.overview) }

        case .switcher:
            remove(.activityPopover)

        case .activityPopover:
            remove(.switcher)

        case .overview, .closeConfirmation:
            break
        }
        insert(overlay)
    }

    func toggle(_ overlay: WorkspaceOverlay) {
        if isOpen(overlay.kind) {
            dismiss(overlay.kind)
        } else {
            present(overlay)
        }
    }

    func dismiss(_ kind: WorkspaceOverlay.Kind) {
        remove(kind)
        if kind == .overview {
            remove(.newWorkspace)
            if closeConfirmation?.anchor == .card {
                remove(.closeConfirmation)
            }
        }
    }

    @discardableResult
    func dismissTop() -> Bool {
        guard let top else { return false }
        dismiss(top.kind)
        return true
    }

    func dismissTransient() {
        remove(.switcher)
        remove(.activityPopover)
        if closeConfirmation?.anchor == .titlebar {
            remove(.closeConfirmation)
        }
    }

    func reconcile(workspaceIDs: Set<UUID>) {
        guard let pending = closeConfirmation, !workspaceIDs.contains(pending.workspaceID) else { return }
        remove(.closeConfirmation)
    }

    func requestClose(
        workspaceID: UUID,
        anchor: CloseConfirmationAnchor,
        in snapshot: WorkspaceOverlaySnapshot,
        close: (UUID) -> Void
    ) {
        guard let workspace = snapshot.workspace(id: workspaceID), !workspace.isDefault else { return }
        let confirmation = CloseWorkspaceConfirmation.make(
            for: workspace,
            foregroundProcessTabs: foregroundProcessTabs(workspaceID))
        if confirmation.requiresConfirmation {
            present(.closeConfirmation(workspaceID: workspaceID, anchor: anchor))
        } else {
            close(workspaceID)
        }
    }

    private func insert(_ overlay: WorkspaceOverlay) {
        overlays.removeAll { $0.kind == overlay.kind }
        overlays.append(overlay)
        overlays.sort { $0.kind < $1.kind }
    }

    private func remove(_ kind: WorkspaceOverlay.Kind) {
        guard isOpen(kind) else { return }
        overlays.removeAll { $0.kind == kind }
    }
}
