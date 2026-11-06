import Foundation
import Testing
@testable import Ghostty

struct ProgramResumeTests {
    private static let sessionID = "0f8fad5b-d9cb-469f-a165-70867728950e"

    @Test func parsesProgramAndToken() {
        let resume = ProgramResume.parse("claude/\(Self.sessionID)")
        #expect(resume?.program == "claude")
        #expect(resume?.token == Self.sessionID)
    }

    @Test(arguments: ["sh", "Claude", "claude-code", "", "bash"])
    func rejectsProgramOutsideAllowlist(program: String) {
        #expect(ProgramResume.parse("\(program)/\(Self.sessionID)") == nil)
        #expect(ProgramResume(program: program, token: Self.sessionID) == nil)
    }

    @Test(arguments: [
        "a;b", "a b", "a$b", "a/b", "a..b", "a\u{15}b", "aéb", "a\nb", "a'b", "a`b", "a(b", "a%0Ab", "a\u{0}b",
        "-rf", "-x", "--dangerously-skip-permissions", "abc-123", "abc", "-0f8fad5b-d9cb-469f-a165-70867728950",
        "0F8FAD5B-D9CB-469F-A165-70867728950E",
        "0f8fad5b-d9cb-469f-a165-70867728950",
        "0f8fad5b-d9cb-469f-a165-70867728950ee",
        "0f8fad5bd9cb469fa16570867728950e",
        "0f8fad5b-d9cb-469f-a165-70867728950g",
        "0f8fad5b-d9cb-469f-a165-70867728950e\n",
        " 0f8fad5b-d9cb-469f-a165-70867728950e",
    ])
    func rejectsTokensThatAreNotASessionId(token: String) {
        #expect(ProgramResume(program: "claude", token: token) == nil)
        #expect(ProgramResume.parse("claude/" + token) == nil)
    }

    @Test func rejectsEmptyOrOversizedToken() {
        #expect(ProgramResume(program: "claude", token: "") == nil)
        #expect(ProgramResume(program: "claude", token: String(repeating: "a", count: 64)) == nil)
        #expect(ProgramResume.parse("claude/" + String(repeating: "a", count: 65)) == nil)
    }

    @Test(arguments: ["claude", "claude/", "/", "", "claude/0f8fad5b-d9cb-469f-a165-70867728950e/x", "claude//abc"])
    func rejectsValueWithoutSeparatorOrWithEmptyParts(raw: String) {
        #expect(ProgramResume.parse(raw) == nil)
    }

    @Test func commandIsExactlyProgramResumeToken() throws {
        let resume = try #require(ProgramResume(program: "claude", token: Self.sessionID))
        #expect(resume.command == "claude --resume \(Self.sessionID)")
        #expect(resume.launchInput == "claude --resume \(Self.sessionID)\n")
    }

    @Test func commandNeverContainsControlCharactersOrLeadingDash() throws {
        let resume = try #require(ProgramResume(program: "claude", token: Self.sessionID))
        #expect(!Ghostty.Shell.containsControlCharacters(resume.command))
        #expect(!resume.token.hasPrefix("-"))
    }

    @Test func quoteIsIdentityForAcceptedTokens() {
        #expect(Ghostty.Shell.quote(Self.sessionID) == Self.sessionID)
    }

    @Test func launchInputRequiresDirectoryAndConfig() throws {
        let resume = try #require(ProgramResume(program: "claude", token: Self.sessionID))
        let input = "claude --resume \(Self.sessionID)\n"
        #expect(ProgramResume.launchInput(for: resume, directoryExists: true, enabled: true) == input)
        #expect(ProgramResume.launchInput(for: resume, directoryExists: false, enabled: true) == nil)
        #expect(ProgramResume.launchInput(for: resume, directoryExists: true, enabled: false) == nil)
        #expect(ProgramResume.launchInput(for: resume, directoryExists: false, enabled: false) == nil)
        #expect(ProgramResume.launchInput(for: nil, directoryExists: true, enabled: true) == nil)
    }

    @Test(arguments: [
        nil, "", "claude", "claude --resume x", "/usr/local/bin/claude", "/opt/homebrew/bin/claude --model opus",
        "  claude", "claude\tfoo", "cswap claude", "env A=1 claude --continue", "/opt/bin/claude", "npx claude",
        "A=claude run", "cd x;claude", "cd x&&claude", "cat x|claude",
    ])
    func commandContextAcceptsClaudeOrAnUnknownCommand(command: String?) {
        #expect(ProgramResume.commandAllows(command))
    }

    @Test(arguments: [
        "sh", "cat resume.txt", "cat notes", "ssh host", "less", "claudette", "myclaude", "claude-code",
        "/tmp/notclaude", "./claude2", "Claude",
    ])
    func commandContextRejectsAnotherProgram(command: String) {
        #expect(!ProgramResume.commandAllows(command))
    }

    @Test func restoredRequiresDirectoryAndConfigAndKeepsTheValue() throws {
        let resume = try #require(ProgramResume(program: "claude", token: Self.sessionID))
        #expect(ProgramResume.restored(resume, directoryExists: true, enabled: true) == resume)
        #expect(ProgramResume.restored(resume, directoryExists: false, enabled: true) == nil)
        #expect(ProgramResume.restored(resume, directoryExists: true, enabled: false) == nil)
        #expect(ProgramResume.restored(nil, directoryExists: true, enabled: true) == nil)
    }
}
