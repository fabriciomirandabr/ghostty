import Testing
@testable import Ghostty

struct WorkspacePaneLabelTests {
    @Test func singlePaneUsesTabTitle() {
        let label = WorkspacePaneLabel.make(
            tabTitle: "agent", titleOverride: "agent", paneTitle: "claude", panePwd: nil, paneCount: 1)
        #expect(label == "agent")

        let plain = WorkspacePaneLabel.make(
            tabTitle: "claude", titleOverride: nil, paneTitle: "claude", panePwd: nil, paneCount: 1)
        #expect(plain == "claude")
    }

    @Test func splitPaneUsesResolvedPaneTitle() {
        let label = WorkspacePaneLabel.make(
            tabTitle: "claude", titleOverride: nil, paneTitle: "  👻 pnpm dev ", panePwd: nil, paneCount: 2)
        #expect(label == "pnpm dev")
    }

    @Test func overridePrefixesPaneTitle() {
        let label = WorkspacePaneLabel.make(
            tabTitle: "agent", titleOverride: "agent", paneTitle: "claude", panePwd: nil, paneCount: 2)
        #expect(label == "agent › claude")
        #expect(WorkspacePaneLabel.separator == " › ")

        let blank = WorkspacePaneLabel.make(
            tabTitle: "claude", titleOverride: "   ", paneTitle: "claude", panePwd: nil, paneCount: 3)
        #expect(blank == "claude")
    }

    @Test func labelCollapsesEqualTabAndPaneTitles() {
        let equal = WorkspacePaneLabel.make(
            tabTitle: "claude", titleOverride: " claude ", paneTitle: "claude", panePwd: nil, paneCount: 2)
        #expect(equal == "claude")

        let differentCase = WorkspacePaneLabel.make(
            tabTitle: "Claude", titleOverride: "Claude", paneTitle: "claude", panePwd: nil, paneCount: 2)
        #expect(differentCase == "Claude › claude")
    }

    @Test func emptyPaneTitleFallsBackToFolderThenTerminal() {
        let folder = WorkspacePaneLabel.make(
            tabTitle: "x", titleOverride: nil, paneTitle: "", panePwd: "/tmp/ws-home/code/api", paneCount: 2)
        #expect(folder == "api")

        let terminal = WorkspacePaneLabel.make(
            tabTitle: "x", titleOverride: nil, paneTitle: "👻", panePwd: nil, paneCount: 2)
        #expect(terminal == "Terminal")

        let prefixed = WorkspacePaneLabel.make(
            tabTitle: "agent", titleOverride: "agent", paneTitle: "", panePwd: nil, paneCount: 2)
        #expect(prefixed == "agent › Terminal")
    }
}
