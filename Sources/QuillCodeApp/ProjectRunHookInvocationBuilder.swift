import Foundation
import QuillCodeCore

struct ProjectRunHookInvocation: Sendable {
    var hook: ProjectRunHook
    var call: ToolCall
}

enum ProjectRunHookInvocationBuilder {
    static func build(
        hook: ProjectRunHook,
        thread: ChatThread,
        prompt: String,
        workspaceRoot: URL,
        pluginDataBaseDirectory: URL?,
        stopHookActive: Bool = false
    ) throws -> ProjectRunHookInvocation {
        let standardInput = try inputJSON(
            timing: hook.timing,
            thread: thread,
            prompt: prompt,
            workspaceRoot: workspaceRoot,
            stopHookActive: stopHookActive
        )
        let environment = try ProjectPluginHookEnvironment.build(
            base: hook.environment ?? [:],
            pluginID: hook.pluginID,
            pluginRootRelativePath: hook.pluginRootRelativePath,
            workspaceRoot: workspaceRoot,
            pluginDataBaseDirectory: pluginDataBaseDirectory
        )
        return ProjectRunHookInvocation(
            hook: hook,
            call: WorkspaceShellToolCallPlanner.projectRunHook(
                hook,
                environment: environment,
                standardInput: standardInput
            )
        )
    }

    static func inputJSON(
        timing: ProjectRunHookTiming,
        thread: ChatThread,
        prompt: String,
        workspaceRoot: URL,
        stopHookActive: Bool = false
    ) throws -> String {
        var payload = ProjectHookStandardInput.payload(
            eventName: eventName(for: timing),
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        switch timing {
        case .beforeAgentRun:
            payload["prompt"] = prompt
        case .afterAgentRun:
            payload["stop_hook_active"] = stopHookActive
            payload["last_assistant_message"] = thread.messages
                .last(where: { $0.role == .assistant })?.content ?? ""
        }
        return try ProjectHookStandardInput.encoded(payload)
    }

    private static func eventName(for timing: ProjectRunHookTiming) -> String {
        switch timing {
        case .beforeAgentRun: return "UserPromptSubmit"
        case .afterAgentRun: return "Stop"
        }
    }

}
