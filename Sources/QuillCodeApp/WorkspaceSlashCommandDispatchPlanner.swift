import Foundation
import QuillCodeCore

enum WorkspaceSlashCommandDispatchAction: Equatable {
    case appendTranscript(WorkspaceLocalCommandTranscript)
    case newChat
    case setMode(AgentMode, userText: String)
    case setModel(String, userText: String)
    case renameThread(String, userText: String)
    case renameProject(String, userText: String)
    case addSSHProject(String, userText: String)
    case remember(String, userText: String)
    case threadFollowUp(String, userText: String)
    case workspaceSchedule(String, userText: String)
    case workspaceCommand(String, userText: String)
    case toolCall(ToolCall)
    case environmentAction(String?, userText: String)
}

struct WorkspaceSlashCommandDispatchPlanner {
    static func action(
        for command: SlashCommand,
        userText: String,
        statusText: String
    ) -> WorkspaceSlashCommandDispatchAction {
        switch command {
        case .help:
            return .appendTranscript(WorkspaceSlashCommandTranscriptPlanner.help(userText: userText))
        case .status:
            return .appendTranscript(WorkspaceSlashCommandTranscriptPlanner.status(
                userText: userText,
                statusText: statusText
            ))
        case .newChat:
            return .newChat
        case .mode(let mode):
            return .setMode(mode, userText: userText)
        case .model(let model):
            return .setModel(model, userText: userText)
        case .renameThread(let title):
            return .renameThread(title, userText: userText)
        case .renameProject(let name):
            return .renameProject(name, userText: userText)
        case .sshProject(let address):
            return .addSSHProject(address, userText: userText)
        case .remember(let content):
            return .remember(content, userText: userText)
        case .threadFollowUp(let scheduleText):
            return .threadFollowUp(scheduleText, userText: userText)
        case .workspaceSchedule(let scheduleText):
            return .workspaceSchedule(scheduleText, userText: userText)
        case .workspaceCommand(let commandID):
            return .workspaceCommand(commandID, userText: userText)
        case .toolCall(let call):
            return .toolCall(call)
        case .environmentAction(let query):
            return .environmentAction(query, userText: userText)
        case .invalid(let message):
            return .appendTranscript(WorkspaceSlashCommandTranscriptPlanner.invalid(
                userText: userText,
                message: message
            ))
        case .unknown(let name):
            return .appendTranscript(WorkspaceSlashCommandTranscriptPlanner.unknown(
                userText: userText,
                name: name
            ))
        }
    }
}
