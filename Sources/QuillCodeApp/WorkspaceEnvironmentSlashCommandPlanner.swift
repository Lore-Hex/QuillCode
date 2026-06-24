import Foundation
import QuillCodeCore

enum WorkspaceEnvironmentSlashCommandPlan: Equatable {
    case transcript(WorkspaceLocalCommandTranscript)
    case runAction(id: String)
}

struct WorkspaceEnvironmentSlashCommandPlanner {
    static func plan(
        query: String?,
        userText: String,
        actions: [LocalEnvironmentAction]
    ) -> WorkspaceEnvironmentSlashCommandPlan {
        guard let query = query?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return .transcript(WorkspaceSlashCommandTranscriptPlanner.environmentActions(
                userText: userText,
                actions: actions
            ))
        }

        guard let action = LocalEnvironmentActionMatcher.action(matching: query, in: actions) else {
            return .transcript(WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound(
                userText: userText,
                query: query
            ))
        }
        return .runAction(id: action.id)
    }
}
