import Foundation

struct ProgramResume: Equatable, Sendable {
    static let allowedProgramName = "claude"
    static let allowedPrograms: Set<String> = [allowedProgramName]
    static let commandWordSeparators: Set<Character> = ["/", "=", ";", "&", "|"]
    static let sessionIDLength = 36
    static let sessionIDDashes: Set<Int> = [8, 13, 18, 23]

    let program: String
    let token: String

    init?(program: String, token: String) {
        guard Self.allowedPrograms.contains(program), Self.isValidToken(token) else { return nil }
        self.program = program
        self.token = token
    }

    static func isValidToken(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        guard bytes.count == sessionIDLength else { return false }
        return bytes.enumerated().allSatisfy { index, byte in
            if sessionIDDashes.contains(index) { return byte == UInt8(ascii: "-") }
            return (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }

    static func commandAllows(_ command: String?) -> Bool {
        guard let command, !command.allSatisfy(\.isWhitespace) else { return true }
        let words = command.split { $0.isWhitespace || commandWordSeparators.contains($0) }
        return words.contains { $0 == Substring(allowedProgramName) }
    }

    static func parse(_ raw: String) -> ProgramResume? {
        let parts = raw.split(separator: "/", maxSplits: .max, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return ProgramResume(program: String(parts[0]), token: String(parts[1]))
    }

    var command: String {
        "\(program) --resume \(Ghostty.Shell.quote(token))"
    }

    var launchInput: String {
        command + "\n"
    }

    static func restored(_ resume: ProgramResume?, directoryExists: Bool, enabled: Bool) -> ProgramResume? {
        guard enabled, directoryExists else { return nil }
        return resume
    }

    static func launchInput(for resume: ProgramResume?, directoryExists: Bool, enabled: Bool) -> String? {
        restored(resume, directoryExists: directoryExists, enabled: enabled)?.launchInput
    }
}
