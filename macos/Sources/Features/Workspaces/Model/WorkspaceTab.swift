import AppKit

struct WorkspaceTab<ViewType: NSView & Codable & Identifiable>: Identifiable where ViewType.ID == UUID {
    let id: UUID
    var titleOverride: String?
    var focusedSurfaceID: UUID?
    private(set) var tree: SplitTree<ViewType>

    init?(
        id: UUID = UUID(),
        titleOverride: String? = nil,
        tree: SplitTree<ViewType>,
        focusedSurfaceID: UUID? = nil
    ) {
        guard !tree.isEmpty else { return nil }
        self.id = id
        self.titleOverride = titleOverride
        self.tree = tree
        self.focusedSurfaceID = focusedSurfaceID
    }

    func contains(_ surface: ViewType) -> Bool {
        tree.contains { $0 === surface }
    }

    @discardableResult
    mutating func setTree(_ newTree: SplitTree<ViewType>) -> Bool {
        guard !newTree.isEmpty else { return false }
        tree = newTree
        return true
    }
}
