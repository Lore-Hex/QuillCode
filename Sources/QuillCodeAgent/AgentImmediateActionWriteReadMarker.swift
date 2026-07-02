import Foundation
import QuillCodeCore
import QuillCodeTools

/// Immediate-action tool calls are parsed from the user's explicit command before any LLM is
/// consulted. When that parsed action is a file write, the write target is user-authored rather
/// than model-invented, so mark that exact target as known to this thread's edit session.
///
/// Model-produced tool calls never pass through this helper and still need to read existing
/// files before overwriting them.
enum AgentImmediateActionWriteReadMarker {
    static func markIfNeeded(_ action: AgentAction, thread: ChatThread, workspaceRoot: URL) {
        guard case .tool(let call) = action,
              call.name == ToolDefinition.fileWrite.name,
              let arguments = try? ToolArguments(call.argumentsJSON),
              let path = try? arguments.requiredString("path"),
              let url = try? FileWorkspacePathResolver(workspaceRoot: workspaceRoot).resolve(path)
        else {
            return
        }
        FileEditSessionGuard.session(for: thread.id).markRead(url)
    }
}
