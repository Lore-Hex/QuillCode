import Foundation

struct WorkspaceComposerSubmissionPlanner {
    enum Plan: Equatable {
        case ignore
        case slash(command: SlashCommand, originalPrompt: String)
        case agent(prompt: String)
    }

    static func plan(draft: String, hasAttachments: Bool = false) -> Plan {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty || hasAttachments else { return .ignore }

        // An attachment turns slash-looking text into model context rather than a local command.
        // This prevents a valid image from being discarded by a command that cannot consume it.
        if hasAttachments {
            return .agent(prompt: prompt)
        }

        if let command = SlashCommandParser.parse(prompt) {
            // `/skill name` is a registry entry that resolves to a normal agent turn (load + run the
            // named skill), so it goes through the identical send path as any typed message rather
            // than a bespoke dispatch branch. An empty `/skill` still falls through to `.slash` so
            // the shared invalid-usage transcript is shown.
            if case let .runSkill(skillPrompt) = command {
                return .agent(prompt: skillPrompt)
            }
            return .slash(command: command, originalPrompt: prompt)
        }

        return .agent(prompt: prompt)
    }
}
