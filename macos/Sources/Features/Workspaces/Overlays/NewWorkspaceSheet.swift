import AppKit
import SwiftUI

struct NewWorkspaceForm: Equatable {
    enum Problem: Equatable {
        case emptyName
        case missingFolder
        case duplicateName
    }

    var name = ""
    var directory: URL?
    var nameEdited = false

    mutating func setName(_ value: String) {
        name = String(value.prefix(WorkspaceName.maxLength))
        nameEdited = true
    }

    mutating func chooseDirectory(_ url: URL) {
        directory = url
        if !nameEdited || WorkspaceName.normalize(name).isEmpty {
            name = WorkspaceName.normalize(url.lastPathComponent)
            nameEdited = false
        }
    }

    func problem(existingNames: [String]) -> Problem? {
        let normalized = WorkspaceName.normalize(name)
        if normalized.isEmpty { return .emptyName }
        if existingNames.contains(where: { $0.compare(normalized, options: .caseInsensitive) == .orderedSame }) {
            return .duplicateName
        }
        if directory == nil { return .missingFolder }
        return nil
    }

    func canCreate(existingNames: [String]) -> Bool {
        problem(existingNames: existingNames) == nil
    }

    static let duplicateMessage = "A workspace with this name already exists."
}

enum WorkspaceDirectoryPicker {
    @MainActor
    static func choose(startingAt directory: URL?, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = directory

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}

struct NewWorkspaceSheet: View {
    let existingNames: [String]
    var onCreate: (String, URL) -> WorkspaceError?
    var onCancel: () -> Void

    @State private var form = NewWorkspaceForm()
    @State private var rejection: WorkspaceError?
    @FocusState private var nameFocused: Bool

    private var problem: NewWorkspaceForm.Problem? {
        form.problem(existingNames: existingNames)
    }

    private var message: String {
        if problem == .duplicateName || rejection == .duplicateName {
            return NewWorkspaceForm.duplicateMessage
        }
        return ""
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { form.name },
            set: {
                form.setName($0)
                rejection = nil
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New workspace")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(WorkspaceOverlayPalette.primaryText)
                .padding(.bottom, 12)

            fieldLabel("Name")
            TextField("Project name", text: nameBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundColor(WorkspaceOverlayPalette.primaryText)
                .modifier(NewWorkspaceFieldChrome(isFocused: nameFocused))
                .focused($nameFocused)
                .onSubmit(create)
                .padding(.bottom, 10)

            fieldLabel("Folder")
            HStack(spacing: 8) {
                Text(form.directory.map { WorkspaceFolderLabel.abbreviated($0) } ?? "No folder chosen")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(form.directory == nil
                        ? WorkspaceOverlayPalette.secondaryText
                        : WorkspaceOverlayPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .modifier(NewWorkspaceFieldChrome(isFocused: false))

                Button("Choose…", action: chooseFolder)
                    .buttonStyle(WorkspaceOverlayButtonStyle(kind: .secondary))
            }
            .padding(.bottom, 10)

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(WorkspaceOverlayPalette.menuText)
                .frame(minHeight: 16, alignment: .leading)
                .padding(.bottom, 6)
                .accessibilityHidden(message.isEmpty)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .buttonStyle(WorkspaceOverlayButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .buttonStyle(WorkspaceOverlayButtonStyle(kind: .primary))
                    .disabled(!form.canCreate(existingNames: existingNames))
            }
        }
        .frame(width: 262, alignment: .leading)
        .workspaceOverlayPanel(padding: 14, shadowOpacity: 0.6, shadowRadius: 18, shadowY: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New workspace")
        .onExitCommand(perform: onCancel)
        .onAppear {
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(WorkspaceOverlayPalette.hint)
            .padding(.bottom, 4)
    }

    private func chooseFolder() {
        WorkspaceDirectoryPicker.choose(startingAt: form.directory) { url in
            guard let url else { return }
            form.chooseDirectory(url)
            rejection = nil
        }
    }

    private func create() {
        guard form.canCreate(existingNames: existingNames), let directory = form.directory else { return }
        rejection = onCreate(WorkspaceName.normalize(form.name), directory)
    }
}

private struct NewWorkspaceFieldChrome: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.rowRadius, style: .continuous)
                    .fill(WorkspaceOverlayPalette.fieldBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: WorkspaceOverlayMetrics.rowRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? WorkspaceOverlayPalette.fieldFocusBorder : WorkspaceOverlayPalette.fieldBorder,
                        lineWidth: 1
                    )
            )
    }
}
