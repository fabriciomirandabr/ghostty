import Foundation

struct ProgramStatusReport: Equatable {
    enum State: Equatable {
        case idle
        case working
        case done
        case blocked
        case error
        case clear
    }

    enum Kind: Equatable {
        case none
        case permission
        case question
        case auth
    }

    var id: String = ""
    var state: State
    var kind: Kind = .none
    var progress: Int?
    var title: String?
    var message: String?

    var text: String? {
        if let message, !message.isEmpty { return message }
        if let title, !title.isEmpty { return title }
        return nil
    }
}

extension SurfaceActivityState {
    static let maxProgramRecords = 64

    struct ProgramRecord: Equatable {
        var state: ProgramStatusReport.State
        var kind: ProgramStatusReport.Kind
        var progress: Int?
        var text: String?
        var doneUntil: Date?
        var order: Int

        func activityState(at now: Date) -> SurfaceActivityState {
            switch state {
            case .working: .running
            case .blocked, .error: .needsAttention
            case .done: (doneUntil ?? .distantPast) > now ? .done : .idle
            case .idle, .clear: .idle
            }
        }
    }
}

extension SurfaceActivityState.Signals {
    mutating func applyProgramStatus(_ report: ProgramStatusReport, at now: Date) {
        switch report.state {
        case .clear:
            if report.id.isEmpty {
                programRecords.removeAll()
            } else {
                programRecords = programRecords.filter {
                    $0.key != report.id && !$0.key.hasPrefix(report.id + "/")
                }
            }

        case .idle, .working, .done, .blocked, .error:
            programOrder += 1
            if programRecords[report.id] == nil, programRecords.count >= SurfaceActivityState.maxProgramRecords {
                if let oldest = programRecords.min(by: { $0.value.order < $1.value.order })?.key {
                    programRecords.removeValue(forKey: oldest)
                }
            }
            programRecords[report.id] = SurfaceActivityState.ProgramRecord(
                state: report.state,
                kind: report.kind,
                progress: report.progress,
                text: report.text,
                doneUntil: report.state == .done
                    ? now.addingTimeInterval(SurfaceActivityState.doneLifetime)
                    : nil,
                order: programOrder
            )
        }
    }

    func programState(at now: Date) -> SurfaceActivityState? {
        guard !programRecords.isEmpty else { return nil }
        return programRecords.values.map { $0.activityState(at: now) }.max() ?? .idle
    }

    func programDetail(at now: Date) -> String? {
        programRecords.values
            .filter { $0.text != nil && $0.activityState(at: now) != .idle }
            .max {
                let (lhs, rhs) = ($0.activityState(at: now), $1.activityState(at: now))
                return lhs == rhs ? $0.order < $1.order : lhs < rhs
            }?
            .text
    }

    func programDoneExpiry(at now: Date) -> TimeInterval? {
        programRecords.values
            .compactMap(\.doneUntil)
            .filter { $0 > now }
            .map { $0.timeIntervalSince(now) }
            .min()
    }
}
