import Foundation

enum WorkspaceStateStoreError: Error, Equatable {
    case newerVersion(Int)
}

@MainActor
final class WorkspaceStateStore {
    typealias Writer = (Data, URL) throws -> Void

    static let fileName = "workspaces.json"
    static let defaultDebounceInterval: TimeInterval = 1

    static let shared: WorkspaceStateStore = {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            preconditionFailure("the workspace state file needs the app bundle identifier")
        }
        return WorkspaceStateStore(fileURL: defaultFileURL(bundleIdentifier: bundleIdentifier))
    }()

    let fileURL: URL
    let debounceInterval: TimeInterval
    var didWrite: ((WorkspacePersistedState) -> Void)?

    private let writer: Writer
    private(set) var writeCount = 0
    private var pendingState: WorkspacePersistedState?
    private var pendingWrite: DispatchWorkItem?

    private struct VersionProbe: Decodable {
        let version: Int
    }

    init(
        fileURL: URL,
        debounceInterval: TimeInterval = WorkspaceStateStore.defaultDebounceInterval,
        writer: @escaping Writer = { try $0.write(to: $1, options: .atomic) }
    ) {
        self.fileURL = fileURL
        self.debounceInterval = debounceInterval
        self.writer = writer
    }

    static func defaultFileURL(bundleIdentifier: String, fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    var hasPendingSave: Bool { pendingState != nil }

    func load() throws -> WorkspacePersistedState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let probe = try decoder.decode(VersionProbe.self, from: data)
        guard probe.version <= WorkspacePersistedState.currentVersion else {
            throw WorkspaceStateStoreError.newerVersion(probe.version)
        }
        return try decoder.decode(WorkspacePersistedState.self, from: data)
    }

    func save(_ state: WorkspacePersistedState) throws {
        cancelPending()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try writer(data, fileURL)
        writeCount += 1
        Ghostty.logger.debug(
            "workspace state written: write=\(self.writeCount, privacy: .public) workspaces=\(state.workspaces.count, privacy: .public)")
        didWrite?(state)
    }

    func scheduleSave(_ state: WorkspacePersistedState) {
        pendingState = state
        guard pendingWrite == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingWrite?.isCancelled == false else { return }
                self.pendingWrite = nil
                self.writePending()
            }
        }
        pendingWrite = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    func flush() throws {
        guard let state = pendingState else { return }
        try save(state)
    }

    func delete() throws {
        cancelPending()
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func writePending() {
        do {
            try flush()
        } catch {
            Ghostty.logger.warning("workspace state save failed: \(error, privacy: .public)")
        }
    }

    func cancelPending() {
        pendingWrite?.cancel()
        pendingWrite = nil
        pendingState = nil
    }
}
