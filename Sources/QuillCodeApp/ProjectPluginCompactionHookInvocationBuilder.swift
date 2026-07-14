import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum ProjectPluginCompactionHookEvent: String, Sendable, Hashable {
    case preCompact = "PreCompact"
    case postCompact = "PostCompact"
}

struct ProjectPluginCompactionHookInvocation: Sendable {
    var hook: ProjectPluginHook
    var call: ToolCall
}

enum ProjectPluginCompactionHookInvocationBuilder {
    static func build(
        hook: ProjectPluginHook,
        event: ProjectPluginCompactionHookEvent,
        trigger: AgentCompactionTrigger,
        thread: ChatThread,
        workspaceRoot: URL,
        pluginDataBaseDirectory: URL?
    ) throws -> ProjectPluginCompactionHookInvocation {
        guard let command = hook.command else {
            throw ProjectPluginCompactionHookInvocationError.missingCommand
        }
        let environment = try ProjectPluginHookEnvironment.build(
            pluginID: hook.pluginID,
            pluginRootRelativePath: hook.pluginRootRelativePath,
            workspaceRoot: workspaceRoot,
            pluginDataBaseDirectory: pluginDataBaseDirectory
        )
        var payload = ProjectHookStandardInput.payload(
            eventName: event.rawValue,
            thread: thread,
            workspaceRoot: workspaceRoot,
            includesPermissionMode: false
        )
        payload["trigger"] = trigger.rawValue
        var arguments: [String: Any] = [
            "cmd": command,
            "stdin": try ProjectHookStandardInput.encoded(payload),
            "timeoutSeconds": hook.timeoutSeconds
        ]
        if !environment.isEmpty {
            arguments["environment"] = environment
        }
        return ProjectPluginCompactionHookInvocation(
            hook: hook,
            call: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(arguments)
            )
        )
    }
}

enum ProjectPluginCompactionHookInvocationError: LocalizedError {
    case missingCommand

    var errorDescription: String? {
        "The plugin hook command is missing."
    }
}
