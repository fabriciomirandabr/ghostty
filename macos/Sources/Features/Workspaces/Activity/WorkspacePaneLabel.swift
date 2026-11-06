import Foundation

enum WorkspacePaneLabel {
    static let separator = " › "

    static func make(
        tabTitle: String,
        titleOverride: String?,
        paneTitle: String,
        panePwd: String?,
        paneCount: Int
    ) -> String {
        guard paneCount >= 2 else { return tabTitle }
        let pane = WorkspaceTabTitle.resolve(title: paneTitle, pwd: panePwd)
        guard let override = WorkspaceTabTitle.override(titleOverride) else { return pane }
        let name = override.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != pane.trimmingCharacters(in: .whitespacesAndNewlines) else { return pane }
        return override + separator + pane
    }
}
