import SwiftUI

struct WorkspaceSwitcherEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let folder: String
    let state: SurfaceActivityState
    var runningCount: Int = 0
}

enum WorkspaceSwitcherFilter {
    static func entries(
        from snapshot: WorkspaceOverlaySnapshot,
        home: String = NSHomeDirectory()
    ) -> [WorkspaceSwitcherEntry] {
        snapshot.workspaces.map {
            WorkspaceSwitcherEntry(
                id: $0.id,
                name: $0.name,
                folder: WorkspaceFolderLabel.abbreviated($0.directory, home: home),
                state: $0.state,
                runningCount: $0.runningTabCount
            )
        }
    }

    static func matches(_ entries: [WorkspaceSwitcherEntry], query: String) -> [WorkspaceSwitcherEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.name.range(of: needle, options: .caseInsensitive) != nil ||
                $0.folder.range(of: needle, options: .caseInsensitive) != nil
        }
    }

    static func moved(from index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }

    static func clamped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}

struct WorkspaceSwitcherView: View {
    static let maxWidth: CGFloat = 480

    let entries: [WorkspaceSwitcherEntry]
    var onPick: (UUID) -> Void
    var onCancel: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var fieldFocused: Bool

    private var matches: [WorkspaceSwitcherEntry] {
        WorkspaceSwitcherFilter.matches(entries, query: query)
    }

    var body: some View {
        let results = matches
        let current = WorkspaceSwitcherFilter.clamped(selectedIndex, count: results.count)

        VStack(spacing: 6) {
            searchField(results: results, current: current)

            if results.isEmpty {
                Text("No workspace found.")
                    .font(.system(size: 12))
                    .foregroundColor(WorkspaceOverlayPalette.secondaryText)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                                WorkspaceSwitcherRow(entry: entry, isSelected: index == current) {
                                    selectedIndex = index
                                } onPick: {
                                    onPick(entry.id)
                                }
                                .id(entry.id)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: selectedIndex) { _ in
                        let results = matches
                        let index = WorkspaceSwitcherFilter.clamped(selectedIndex, count: results.count)
                        guard results.indices.contains(index) else { return }
                        proxy.scrollTo(results[index].id)
                    }
                }
            }
        }
        .frame(maxWidth: Self.maxWidth)
        .workspaceOverlayPanel(shadowOpacity: 0.7, shadowRadius: 22, shadowY: 20)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switch workspace")
        .onExitCommand(perform: onCancel)
    }

    private func searchField(results: [WorkspaceSwitcherEntry], current: Int) -> some View {
        ZStack {
            Group {
                hiddenKey(.upArrow, delta: -1, count: results.count)
                hiddenKey(.downArrow, delta: 1, count: results.count)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            TextField("Switch workspace…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(WorkspaceOverlayPalette.strongText)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.rowRadius, style: .continuous)
                        .fill(WorkspaceOverlayPalette.fieldBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.rowRadius, style: .continuous)
                        .strokeBorder(
                            fieldFocused ? WorkspaceOverlayPalette.fieldFocusBorder : WorkspaceOverlayPalette.fieldBorder,
                            lineWidth: 1
                        )
                )
                .focused($fieldFocused)
                .onMoveCommand { direction in
                    switch direction {
                    case .up: move(-1, count: results.count)
                    case .down: move(1, count: results.count)
                    default: break
                    }
                }
                .onSubmit {
                    guard results.indices.contains(current) else { return }
                    onPick(results[current].id)
                }
                .onChange(of: query) { _ in
                    selectedIndex = 0
                }
                .onAppear {
                    DispatchQueue.main.async { fieldFocused = true }
                }
                .accessibilityLabel("Search workspaces")
        }
    }

    private func hiddenKey(_ key: KeyEquivalent, delta: Int, count: Int) -> some View {
        Button { move(delta, count: count) } label: { Color.clear }
            .buttonStyle(.plain)
            .keyboardShortcut(key, modifiers: [])
    }

    private func move(_ delta: Int, count: Int) {
        selectedIndex = WorkspaceSwitcherFilter.moved(
            from: WorkspaceSwitcherFilter.clamped(selectedIndex, count: count),
            by: delta,
            count: count
        )
    }
}

private struct WorkspaceSwitcherRow: View {
    let entry: WorkspaceSwitcherEntry
    let isSelected: Bool
    var onHover: () -> Void
    var onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 10) {
                Group {
                    if entry.state == .running || entry.state == .needsAttention {
                        StatusIndicatorView(
                            state: entry.state,
                            diameter: 16,
                            badgeText: StatusIndicatorView.badgeText(for: entry.state, runningCount: entry.runningCount)
                        )
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 16, height: 16)

                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(entry.folder)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(WorkspaceOverlayPalette.secondaryText)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? WorkspaceOverlayPalette.strongText : WorkspaceOverlayPalette.menuText)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(WorkspaceOverlayRowBackground(
                isHighlighted: isSelected,
                highlight: WorkspaceOverlayPalette.rowSelected
            ))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { onHover() }
        }
        .accessibilityLabel("\(entry.name), \(entry.folder)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
