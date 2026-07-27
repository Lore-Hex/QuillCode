import Foundation

struct WorkspaceScheduledCoworkerRequest: Equatable, Sendable {
    var scheduleText: String
    var taskText: String
}

enum WorkspaceScheduledCoworkerRequestParser {
    static func parse(_ prompt: String) -> WorkspaceScheduledCoworkerRequest? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard hasRecurringPrefix(lower) else { return nil }

        guard let split = splitScheduleAndTask(trimmed) else { return nil }
        let scheduleText = normalizedScheduleText(split.schedule)
        let taskText = normalizedTaskText(split.task)

        guard !scheduleText.isEmpty,
              !taskText.isEmpty,
              ThreadFollowUpScheduleParser.parse(scheduleText) != nil,
              hasWorkVerb(taskText)
        else {
            return nil
        }

        return WorkspaceScheduledCoworkerRequest(
            scheduleText: scheduleText,
            taskText: taskText
        )
    }

    private static func hasRecurringPrefix(_ lower: String) -> Bool {
        recurringPrefixes.contains { lower.hasPrefix($0) }
    }

    private static func splitScheduleAndTask(_ prompt: String) -> (schedule: String, task: String)? {
        if let comma = prompt.firstIndex(of: ",") {
            return (
                String(prompt[..<comma]),
                String(prompt[prompt.index(after: comma)...])
            )
        }

        for delimiter in [" and then ", " then "] {
            guard let range = prompt.range(
                of: delimiter,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) else {
                continue
            }
            return (
                String(prompt[..<range.lowerBound]),
                String(prompt[range.upperBound...])
            )
        }

        return nil
    }

    private static func normalizedScheduleText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
    }

    private static func normalizedTaskText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
    }

    private static func hasWorkVerb(_ task: String) -> Bool {
        let lower = " \(task.lowercased()) "
        return workVerbs.contains { lower.contains(" \($0) ") }
    }

    private static let recurringPrefixes = [
        "every ",
        "each ",
        "daily ",
        "weekly ",
        "hourly ",
        "mondays ",
        "tuesdays ",
        "wednesdays ",
        "thursdays ",
        "fridays ",
        "saturdays ",
        "sundays ",
        "weekdays ",
        "weekends "
    ]

    private static let workVerbs = [
        "alert",
        "audit",
        "build",
        "check",
        "compare",
        "draft",
        "find",
        "list",
        "monitor",
        "notify",
        "scan",
        "send",
        "summarize",
        "watch",
        "write"
    ]
}
