import AppKit

struct WorkspaceJobNotification: Equatable {
    enum Kind: String, Equatable {
        case done
        case needsAttention
    }

    var identifier: String
    var threadIdentifier: String
    var title: String
    var body: String
    var surfaceID: UUID
    var workspaceID: UUID
}

@MainActor
protocol WorkspaceJobNotificationSink: AnyObject {
    func post(_ notification: WorkspaceJobNotification)
    func retract(identifiers: [String])
}

struct WorkspaceJobVisibility: Equatable {
    var windowIsKey: Bool
    var appIsActive: Bool
    var workspaceIsSelected: Bool
    var tabIsSelected: Bool
    var surfaceIsFocused: Bool

    var isVisibleAndFocused: Bool {
        windowIsKey && appIsActive && workspaceIsSelected && tabIsSelected && surfaceIsFocused
    }
}

struct WorkspaceJobContext: Equatable {
    var terminalLabel: String
    var workspaceName: String
    var workspaceID: UUID
    var visibility: WorkspaceJobVisibility
}

struct WorkspaceJobActivity: Equatable {
    var state: SurfaceActivityState
    var detail: String?
    var attentionIsDesktopNotification: Bool = false
}

@MainActor
final class WorkspaceJobNotifier {
    static let coalesceWindow: TimeInterval = 2
    static let maxDetailLength = 120

    private let sink: any WorkspaceJobNotificationSink
    private let isEnabled: () -> Bool
    private let now: () -> Date
    private var states: [UUID: SurfaceActivityState] = [:]
    private var lastPosted: [String: Date] = [:]

    init(
        sink: any WorkspaceJobNotificationSink,
        isEnabled: @escaping () -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.sink = sink
        self.isEnabled = isEnabled
        self.now = now
    }

    func activityDidChange(
        surfaceID: UUID,
        activity: WorkspaceJobActivity,
        context: () -> WorkspaceJobContext?
    ) {
        guard let previous = states.updateValue(activity.state, forKey: surfaceID) else { return }
        guard previous != activity.state else { return }

        if previous == .needsAttention {
            let retracted = Self.identifier(surfaceID, .needsAttention)
            sink.retract(identifiers: [retracted])
            lastPosted.removeValue(forKey: retracted)
        }

        guard let kind = Self.kind(from: previous, activity: activity), isEnabled() else { return }
        guard let context = context(), !context.visibility.isVisibleAndFocused else { return }

        let identifier = Self.identifier(surfaceID, kind)
        let timestamp = now()
        if let last = lastPosted[identifier], timestamp.timeIntervalSince(last) < Self.coalesceWindow { return }
        lastPosted[identifier] = timestamp

        sink.post(WorkspaceJobNotification(
            identifier: identifier,
            threadIdentifier: context.workspaceID.uuidString,
            title: Self.title(context),
            body: Self.body(kind, detail: activity.detail),
            surfaceID: surfaceID,
            workspaceID: context.workspaceID
        ))
    }

    func forget(surfaceID: UUID) {
        states.removeValue(forKey: surfaceID)
        lastPosted = lastPosted.filter { !$0.key.hasPrefix(Self.identifierPrefix + surfaceID.uuidString) }
    }

    static func kind(
        from previous: SurfaceActivityState,
        activity: WorkspaceJobActivity
    ) -> WorkspaceJobNotification.Kind? {
        switch activity.state {
        case .needsAttention:
            previous != .needsAttention && !activity.attentionIsDesktopNotification ? .needsAttention : nil
        case .done:
            previous == .running ? .done : nil
        case .idle, .running:
            nil
        }
    }

    static func isEnabled(workspaceNotifications: Bool, desktopNotifications: Bool) -> Bool {
        workspaceNotifications && desktopNotifications
    }

    static func terminalLabel<ViewType: NSView & Codable & Identifiable>(
        of surface: ViewType,
        in tab: WorkspaceTab<ViewType>,
        title: (ViewType) -> String,
        pwd: (ViewType) -> String?
    ) -> String where ViewType.ID == UUID {
        let panes = Array(tab.tree)
        let focused = panes.first { $0.id == tab.focusedSurfaceID } ?? panes.first
        let tabTitle = WorkspaceTabTitle.override(tab.titleOverride)
            ?? WorkspaceTabTitle.resolve(title: focused.map(title) ?? "", pwd: focused.flatMap(pwd))
        return WorkspacePaneLabel.make(
            tabTitle: tabTitle,
            titleOverride: tab.titleOverride,
            paneTitle: title(surface),
            panePwd: pwd(surface),
            paneCount: panes.count)
    }

    static func title(_ context: WorkspaceJobContext) -> String {
        context.terminalLabel + " · " + context.workspaceName
    }

    static func body(_ kind: WorkspaceJobNotification.Kind, detail: String?) -> String {
        let headline = switch kind {
        case .done: "Done"
        case .needsAttention: "Needs you"
        }
        guard let detail = truncated(detail) else { return headline }
        return headline + ": " + detail
    }

    static func truncated(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let collapsed = detail.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxDetailLength else { return collapsed }
        return String(collapsed.prefix(maxDetailLength - 1)) + "…"
    }

    static let identifierPrefix = "workspace-job."

    static func identifier(_ surfaceID: UUID, _ kind: WorkspaceJobNotification.Kind) -> String {
        identifierPrefix + surfaceID.uuidString + "." + kind.rawValue
    }
}
