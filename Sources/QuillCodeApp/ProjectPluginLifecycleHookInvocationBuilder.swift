import Foundation
import QuillCodeCore
import QuillCodeTools

struct ProjectPluginLifecycleHookInvocation: Sendable {
    var hook: ProjectPluginHook
    var call: ToolCall
}

enum ProjectPluginLifecycleHookInvocationBuilder {
    static func build(
        hook: ProjectPluginHook,
        event: ProjectPluginLifecycleHookEvent,
        sessionThread: ChatThread,
        workspaceRoot: URL,
        pluginDataBaseDirectory: URL?
    ) throws -> ProjectPluginLifecycleHookInvocation {
        guard let command = hook.command else {
            throw ProjectPluginLifecycleHookInvocationError.missingCommand
        }
        let environment = try ProjectPluginHookEnvironment.build(
            pluginID: hook.pluginID,
            pluginRootRelativePath: hook.pluginRootRelativePath,
            workspaceRoot: workspaceRoot,
            pluginDataBaseDirectory: pluginDataBaseDirectory
        )
        let inputThread = event.inputThread(sessionThread: sessionThread)
        var payload = ProjectHookStandardInput.payload(
            eventName: event.name,
            thread: inputThread,
            workspaceRoot: workspaceRoot,
            includesTurnID: event.includesTurnID
        )
        addEventFields(event, to: &payload)

        var arguments: [String: Any] = [
            "cmd": command,
            "stdin": try ProjectHookStandardInput.encoded(payload),
            "timeoutSeconds": hook.timeoutSeconds
        ]
        if !environment.isEmpty {
            arguments["environment"] = environment
        }
        return ProjectPluginLifecycleHookInvocation(
            hook: hook,
            call: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(arguments)
            )
        )
    }

    private static func addEventFields(
        _ event: ProjectPluginLifecycleHookEvent,
        to payload: inout [String: Any]
    ) {
        switch event {
        case .sessionStart(let source):
            payload["source"] = source.rawValue
        case .subagentStart(let context):
            payload["agent_id"] = context.agentID
            payload["agent_type"] = context.agentType
        case .subagentStop(let context, let stopHookActive, let lastAssistantMessage):
            payload["agent_id"] = context.agentID
            payload["agent_type"] = context.agentType
            payload["agent_transcript_path"] = context.transcriptPath ?? NSNull()
            payload["stop_hook_active"] = stopHookActive
            payload["last_assistant_message"] = lastAssistantMessage ?? NSNull()
        }
    }
}

enum ProjectPluginLifecycleHookInvocationError: LocalizedError {
    case missingCommand

    var errorDescription: String? {
        "The plugin hook command is missing."
    }
}
