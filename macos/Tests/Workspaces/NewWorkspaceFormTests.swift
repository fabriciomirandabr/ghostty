import Foundation
import Testing
@testable import Ghostty

struct NewWorkspaceFormTests {
    private let folder = URL(fileURLWithPath: "/tmp/ws-home/Code/api")

    @Test func choosingAFolderPrefillsTheName() {
        var form = NewWorkspaceForm()
        form.chooseDirectory(folder)
        #expect(form.name == "api")
        #expect(form.directory == folder)
        #expect(form.canCreate(existingNames: ["Default"]))
    }

    @Test func editedNameSurvivesChoosingAnotherFolder() {
        var form = NewWorkspaceForm()
        form.setName("backend")
        form.chooseDirectory(folder)
        #expect(form.name == "backend")

        var untouched = NewWorkspaceForm()
        untouched.chooseDirectory(folder)
        untouched.chooseDirectory(URL(fileURLWithPath: "/tmp/ws-home/Code/web"))
        #expect(untouched.name == "web")
    }

    @Test func emptyNameBlocksCreate() {
        var form = NewWorkspaceForm()
        form.chooseDirectory(folder)
        form.setName("   ")
        #expect(form.problem(existingNames: []) == .emptyName)
        #expect(!form.canCreate(existingNames: []))
    }

    @Test func missingFolderBlocksCreate() {
        var form = NewWorkspaceForm()
        form.setName("api")
        #expect(form.problem(existingNames: []) == .missingFolder)
    }

    @Test func duplicateNameIsCaseInsensitive() {
        var form = NewWorkspaceForm()
        form.chooseDirectory(folder)
        form.setName("  DEFAULT ")
        #expect(form.problem(existingNames: ["Default", "web"]) == .duplicateName)
        #expect(NewWorkspaceForm.duplicateMessage == "A workspace with this name already exists.")
    }

    @Test func nameIsCutAtTheModelLimit() {
        var form = NewWorkspaceForm()
        form.setName(String(repeating: "x", count: 400))
        #expect(form.name.count == WorkspaceName.maxLength)
    }
}
