import Foundation

struct WorkspaceComposerSubmissionPlanner {
    enum Plan: Equatable {
        case ignore
        case slash(command: SlashCommand, originalPrompt: String)
        case agent(prompt: String)
    }

    static func plan(draft: String) -> Plan {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return .ignore }

        if let command = SlashCommandParser.parse(prompt) {
            return .slash(command: command, originalPrompt: prompt)
        }

        return .agent(prompt: prompt)
    }
}
