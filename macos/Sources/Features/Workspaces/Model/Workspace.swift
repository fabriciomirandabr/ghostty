import AppKit

enum WorkspaceError: Error, Equatable {
    case duplicateName
    case emptyName
    case surfaceNotFound
}

enum WorkspaceName {
    static let maxLength = 40
    static let defaultName = "Default"

    static func normalize(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }
}

struct Workspace<ViewType: NSView & Codable & Identifiable>: Identifiable where ViewType.ID == UUID {
    let id: UUID
    var name: String
    var directory: URL
    let isDefault: Bool
    private(set) var tabs: [WorkspaceTab<ViewType>]
    private(set) var selectedTabID: UUID

    init(
        id: UUID = UUID(),
        name: String,
        directory: URL,
        isDefault: Bool = false,
        tab: WorkspaceTab<ViewType>
    ) {
        self.id = id
        self.name = name
        self.directory = directory
        self.isDefault = isDefault
        self.tabs = [tab]
        self.selectedTabID = tab.id
    }

    init?(
        id: UUID = UUID(),
        name: String,
        directory: URL,
        isDefault: Bool = false,
        tabs: [WorkspaceTab<ViewType>],
        selectedTabID: UUID
    ) {
        guard tabs.contains(where: { $0.id == selectedTabID }) else { return nil }
        self.id = id
        self.name = name
        self.directory = directory
        self.isDefault = isDefault
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }

    var selectedTab: WorkspaceTab<ViewType>? {
        tab(id: selectedTabID)
    }

    var surfaces: [ViewType] {
        tabs.flatMap { Array($0.tree) }
    }

    func tab(id: UUID) -> WorkspaceTab<ViewType>? {
        tabs.first { $0.id == id }
    }

    func contains(_ surface: ViewType) -> Bool {
        tabs.contains { $0.contains(surface) }
    }

    func tab(containing surface: ViewType) -> WorkspaceTab<ViewType>? {
        tabs.first { $0.contains(surface) }
    }

    mutating func appendTab(_ tab: WorkspaceTab<ViewType>) {
        tabs.append(tab)
        selectedTabID = tab.id
    }

    @discardableResult
    mutating func selectTab(id: UUID) -> Bool {
        guard tabs.contains(where: { $0.id == id }) else { return false }
        selectedTabID = id
        return true
    }

    @discardableResult
    mutating func updateTab(id: UUID, _ body: (inout WorkspaceTab<ViewType>) -> Void) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        body(&tabs[index])
        return true
    }

    @discardableResult
    mutating func removeTab(
        id: UUID,
        makeReplacement: () -> WorkspaceTab<ViewType>
    ) -> WorkspaceTab<ViewType>? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = makeReplacement()
            tabs.append(replacement)
            selectedTabID = replacement.id
        } else if removed.id == selectedTabID {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }

        return removed
    }
}
