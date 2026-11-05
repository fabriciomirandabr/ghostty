import Foundation
import Testing
@testable import Ghostty

struct ConfigWorkspacesTests {
    @Test func titlebarStyleParses() throws {
        let config = try TemporaryConfig("macos-titlebar-style = workspaces")
        #expect(config.macosTitlebarStyle == .workspaces)
    }

    @Test func titlebarStyleDefaultsToWorkspaces() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosTitlebarStyle == .workspaces)
        #expect(Ghostty.Config.MacOSTitlebarStyle.default == .workspaces)
    }

    @Test(arguments: [
        ("native", Ghostty.Config.MacOSTitlebarStyle.native),
        ("transparent", Ghostty.Config.MacOSTitlebarStyle.transparent),
        ("tabs", Ghostty.Config.MacOSTitlebarStyle.tabs),
        ("hidden", Ghostty.Config.MacOSTitlebarStyle.hidden),
    ])
    func otherTitlebarStylesStillParse(raw: String, expected: Ghostty.Config.MacOSTitlebarStyle) throws {
        let config = try TemporaryConfig("macos-titlebar-style = \(raw)")
        #expect(config.macosTitlebarStyle == expected)
    }

    @Test func workspaceDefaultDirectoryDefaultsToNil() throws {
        let config = try TemporaryConfig("")
        #expect(config.workspaceDefaultDirectory == nil)
    }

    @Test func workspaceDefaultDirectoryExpandsHome() throws {
        let config = try TemporaryConfig("workspace-default-directory = ~/Library")
        let directory = try #require(config.workspaceDefaultDirectory)
        #expect(!directory.hasPrefix("~"))
        #expect(directory.hasPrefix("/"))
        #expect(directory.hasSuffix("/Library"))
    }

    @Test func workspaceDefaultDirectoryKeepsAbsolutePath() throws {
        let path = FileManager.default.temporaryDirectory.path
        let config = try TemporaryConfig("workspace-default-directory = \(path)")
        #expect(config.workspaceDefaultDirectory == path)
    }

    @Test func workspaceDefaultDirectoryMissingPathIsRejected() throws {
        let config = try TemporaryConfig("workspace-default-directory = /nonexistent-\(UUID().uuidString)")
        #expect(config.workspaceDefaultDirectory == nil)
    }

    @Test func pasteImageSendsCtrlVDefaultsToTrue() throws {
        let config = try TemporaryConfig("")
        #expect(config.macosPasteImageSendsCtrlV)
    }

    @Test func pasteImageSendsCtrlVCanBeDisabled() throws {
        let config = try TemporaryConfig("macos-paste-image-sends-ctrl-v = false")
        #expect(!config.macosPasteImageSendsCtrlV)
    }

    @Test func desktopNotificationsDefaultToTrueAndCanBeDisabled() throws {
        #expect(try TemporaryConfig("").desktopNotifications)
        #expect(try !TemporaryConfig("desktop-notifications = false").desktopNotifications)
    }

    @Test func workspaceNotificationsDefaultToTrueAndCanBeDisabled() throws {
        #expect(try TemporaryConfig("").workspaceNotifications)
        #expect(try !TemporaryConfig("workspace-notifications = false").workspaceNotifications)
    }

    @Test func defaultDirectoryResolvesToHomeWhenUnset() {
        #expect(WorkspaceDefaultDirectory.resolve(nil) == FileManager.default.homeDirectoryForCurrentUser)
        #expect(WorkspaceDefaultDirectory.resolve("") == FileManager.default.homeDirectoryForCurrentUser)
    }

    @Test func defaultDirectoryResolvesConfiguredPath() {
        #expect(WorkspaceDefaultDirectory.resolve("/tmp").path == "/tmp")
    }
}
