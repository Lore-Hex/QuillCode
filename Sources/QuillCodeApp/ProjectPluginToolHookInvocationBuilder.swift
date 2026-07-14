import Foundation
import QuillCodeCore
import QuillCodeTools

enum ProjectPluginToolHookEvent: String, Sendable, Hashable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"

    var treatsExitTwoAsDecision: Bool {
        self != .permissionRequest
    }
}

struct ProjectPluginToolHookInvocation: Sendable {
    var hook: ProjectPluginHook
    var call: ToolCall
}

enum ProjectPluginToolHookInvocationBuilder {
    static let maximumApprovalReasonCharacters = 4_096

    static func build(
        hook: ProjectPluginHook,
        event: ProjectPluginToolHookEvent,
        adapter: ProjectPluginToolCallAdapter,
        toolResult: ToolResult?,
        approvalReason: String? = nil,
        thread: ChatThread,
        workspaceRoot: URL,
        pluginDataBaseDirectory: URL?
    ) throws -> ProjectPluginToolHookInvocation {
        guard let command = hook.command else {
            throw ProjectPluginToolHookInvocationError.missingCommand
        }
        let environment = try ProjectPluginHookEnvironment.build(
            pluginID: hook.pluginID,
            pluginRootRelativePath: hook.pluginRootRelativePath,
            workspaceRoot: workspaceRoot,
            pluginDataBaseDirectory: pluginDataBaseDirectory
        )
        let standardInput = try inputJSON(
            event: event,
            adapter: adapter,
            toolResult: toolResult,
            approvalReason: approvalReason,
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        var arguments: [String: Any] = [
            "cmd": command,
            "environment": environment,
            "stdin": standardInput,
            "timeoutSeconds": hook.timeoutSeconds
        ]
        if environment.isEmpty {
            arguments.removeValue(forKey: "environment")
        }
        return ProjectPluginToolHookInvocation(
            hook: hook,
            call: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(arguments)
            )
        )
    }

    static func inputJSON(
        event: ProjectPluginToolHookEvent,
        adapter: ProjectPluginToolCallAdapter,
        toolResult: ToolResult?,
        approvalReason: String? = nil,
        thread: ChatThread,
        workspaceRoot: URL
    ) throws -> String {
        guard var toolInput = jsonValue(adapter.toolInputJSON) as? [String: Any] else {
            throw ProjectPluginToolHookInvocationError.invalidToolInput
        }
        if event == .permissionRequest,
           toolInput["description"] == nil,
           let approvalReason,
           !approvalReason.isEmpty {
            toolInput["description"] = String(
                approvalReason
                    .replacingOccurrences(of: "\0", with: "")
                    .prefix(maximumApprovalReasonCharacters)
            )
        }
        var payload = ProjectHookStandardInput.payload(
            eventName: event.rawValue,
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        payload["tool_name"] = adapter.canonicalName
        payload["tool_input"] = toolInput
        if event != .permissionRequest {
            payload["tool_use_id"] = adapter.call.id
        }
        if event == .postToolUse {
            guard let toolResult,
                  let response = try encodedJSONObject(toolResult)
            else {
                throw ProjectPluginToolHookInvocationError.missingToolResult
            }
            payload["tool_response"] = response
        }
        return try ProjectHookStandardInput.encoded(payload)
    }

    private static func encodedJSONObject<T: Encodable>(_ value: T) throws -> Any? {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func jsonValue(_ value: String) -> Any? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

}

enum ProjectPluginToolHookInvocationError: LocalizedError {
    case invalidToolInput
    case missingCommand
    case missingToolResult

    var errorDescription: String? {
        switch self {
        case .invalidToolInput:
            return "The tool input is not valid JSON."
        case .missingCommand:
            return "The hook command is missing."
        case .missingToolResult:
            return "PostToolUse requires a tool result."
        }
    }
}
