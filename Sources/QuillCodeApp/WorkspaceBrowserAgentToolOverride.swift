import Foundation
import QuillCodeAgent
import QuillCodeCore

enum WorkspaceBrowserAgentToolOverride {
    typealias MainActorExecutor = @MainActor @Sendable (ToolCall, URL) -> ToolResult?

    static func make(_ execute: @escaping MainActorExecutor) -> AgentToolExecutionOverride {
        { call, workspaceRoot in
            await MainActor.run {
                execute(call, workspaceRoot)
            }
        }
    }
}
