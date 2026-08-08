import Foundation
import QuillCodeCore

/// Exposes the same path analysis used by the approval gate so the agent can correct an unsafe
/// shell proposal before it creates a denied tool card. This does not weaken review: an exact retry
/// still reaches the normal safety pipeline, and paths named by the user remain authorized by the
/// underlying policy.
public enum OutsideWorkspaceShellCommandPreflight {
    public static func offendingPaths(
        in call: ToolCall,
        userMessage: String,
        workspaceRoot: URL
    ) -> [String] {
        let context = SafetyContext(
            mode: .auto,
            userMessage: userMessage,
            toolCall: call,
            toolDefinition: nil,
            recentMessages: [],
            workspaceRoot: workspaceRoot
        )
        return StaticSafetyOutsideWorkspaceShellPolicy.violation(context)?.offendingPaths ?? []
    }
}
