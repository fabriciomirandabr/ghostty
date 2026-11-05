import AppKit

@MainActor
final class WorkspaceSnapshotStore: ObservableObject {
    @Published private(set) var images: [UUID: NSImage] = [:]

    func image(for tabID: UUID) -> NSImage? {
        images[tabID]
    }

    func store(_ image: NSImage, for tabID: UUID) {
        images[tabID] = image
    }

    func remove(tabID: UUID) {
        images[tabID] = nil
    }

    func prune(keeping tabIDs: Set<UUID>) {
        images = images.filter { tabIDs.contains($0.key) }
    }
}
