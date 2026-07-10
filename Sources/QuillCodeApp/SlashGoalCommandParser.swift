import Foundation
import QuillCodeCore

enum WorkspaceThreadGoalRequest: Equatable {
    case show
    case set(String)
    case complete
    case block(String)
    case resume
    case clear
}

enum SlashGoalCommandParser {
    static let usage = "Try /goal objective, /goal status, /goal complete, /goal block reason, /goal resume, or /goal clear."

    static func parse(_ argument: String) -> SlashCommand {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .goal(.show) }

        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let action = parts[0].lowercased()
        let remainder = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch action {
        case "status", "show":
            return remainder.isEmpty ? .goal(.show) : .invalid(usage)
        case "set", "start", "new":
            return goalText(remainder).map { .goal(.set($0)) } ?? .invalid(usage)
        case "complete", "completed", "done", "finish":
            return remainder.isEmpty ? .goal(.complete) : .invalid(usage)
        case "block", "blocked", "pause":
            return blockerText(remainder).map { .goal(.block($0)) } ?? .invalid(usage)
        case "resume", "continue", "unblock":
            return remainder.isEmpty ? .goal(.resume) : .invalid(usage)
        case "clear", "remove", "delete":
            return remainder.isEmpty ? .goal(.clear) : .invalid(usage)
        default:
            return goalText(trimmed).map { .goal(.set($0)) } ?? .invalid(usage)
        }
    }

    private static func goalText(_ value: String) -> String? {
        normalized(value, maximumLength: ThreadGoal.maximumObjectiveLength)
    }

    private static func blockerText(_ value: String) -> String? {
        normalized(value, maximumLength: ThreadGoal.maximumBlockerLength)
    }

    private static func normalized(_ value: String, maximumLength: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }
}
