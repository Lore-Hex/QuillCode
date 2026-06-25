import Foundation
import QuillCodeCore

enum SlashCommand: Equatable {
    case help
    case status
    case newChat
    case mode(AgentMode)
    case model(String)
    case renameThread(String)
    case renameProject(String)
    case sshProject(String)
    case remember(String)
    case editMemory(id: String, content: String)
    case threadFollowUp(String)
    case workspaceSchedule(String)
    case workspaceCommand(String)
    case worktreeCreate(WorkspaceWorktreeCreateRequest)
    case worktreeOpen(WorkspaceWorktreeOpenRequest)
    case worktreeRemove(WorkspaceWorktreeRemoveRequest)
    case worktreePrune(WorkspaceWorktreePruneRequest)
    case toolCall(ToolCall)
    case environmentAction(String?)
    case invalid(String)
    case unknown(String)
}

enum SlashCommandParser {
    static func parse(_ input: String) -> SlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let commandText = String(trimmed.dropFirst())
        let parts = commandText.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let name = parts.first?.lowercased() else {
            return .help
        }
        let argument = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch name {
        case "?", "help":
            return .help
        case "status":
            return .status
        case let threadCommand where SlashThreadCommandParser.supports(threadCommand):
            return SlashThreadCommandParser.parse(name: threadCommand, argument: argument)
        case "follow-up", "followup", "schedule", "remind":
            return SlashSchedulingCommandParser.parseThreadFollowUp(argument)
        case "workspace-check", "workspacecheck", "workspace-schedule", "project-check", "repo-check":
            return SlashSchedulingCommandParser.parseWorkspaceSchedule(argument)
        case "project":
            return SlashProjectCommandParser.parse(argument)
        case "ssh", "remote":
            return SlashRemoteProjectCommandParser.parse(argument)
        case "terminal", "term", "shell":
            return SlashTerminalCommandParser.parse(argument)
        case let workspaceCommand where SlashWorkspaceCommandParser.supports(workspaceCommand):
            return SlashWorkspaceCommandParser.parse(name: workspaceCommand, argument: argument)
        case let memoryCommand where SlashMemoryCommandParser.supports(memoryCommand):
            return SlashMemoryCommandParser.parse(name: memoryCommand, argument: argument)
        case "pr", "pull-request", "pullrequest":
            return SlashPullRequestCommandParser.parse(argument)
        case let environmentCommand where SlashEnvironmentCommandParser.supports(environmentCommand):
            return SlashEnvironmentCommandParser.parse(argument)
        case "mode":
            return SlashModeCommandParser.parse(argument)
        case "model":
            return SlashModelCommandParser.parse(argument)
        default:
            return .unknown(name)
        }
    }
}
