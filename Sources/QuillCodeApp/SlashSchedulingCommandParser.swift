import Foundation

enum SlashSchedulingCommandParser {
    private static let threadFollowUpUsage = "Usage: /follow-up in 30 minutes, /follow-up Friday at 4 PM, or /follow-up daily"
    private static let workspaceScheduleUsage = "Usage: /workspace-check in 1 hour, /workspace-check Friday morning, or /workspace-check every 2 hours"

    static func parseThreadFollowUp(_ argument: String) -> SlashCommand {
        parseSchedule(argument, usage: threadFollowUpUsage, command: SlashCommand.threadFollowUp)
    }

    static func parseWorkspaceSchedule(_ argument: String) -> SlashCommand {
        parseSchedule(argument, usage: workspaceScheduleUsage, command: SlashCommand.workspaceSchedule)
    }

    private static func parseSchedule(
        _ argument: String,
        usage: String,
        command: (String) -> SlashCommand
    ) -> SlashCommand {
        let schedule = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        return schedule.isEmpty ? .invalid(usage) : command(schedule)
    }
}
