import Foundation
import QuillCodeAgent
import QuillCodeCore

enum WorkspaceBrowserAgentToolOverride {
    typealias MainActorExecutor = @MainActor @Sendable (ToolCall, URL) async -> ToolResult?

    static func make(_ execute: @escaping MainActorExecutor) -> AgentToolExecutionOverride {
        { call, workspaceRoot in
            await execute(call, workspaceRoot)
        }
    }
}
