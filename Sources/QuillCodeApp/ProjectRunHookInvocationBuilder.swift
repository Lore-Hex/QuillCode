import Foundation
import QuillCodeCore
import QuillCodePersistence

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
        pluginDataBaseDirectory: URL?
    ) throws -> ProjectRunHookInvocation {
        let standardInput = try inputJSON(
            timing: hook.timing,
            thread: thread,
            prompt: prompt,
            workspaceRoot: workspaceRoot
        )
        let environment = try environment(
            for: hook,
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
        workspaceRoot: URL
    ) throws -> String {
        let userTurnID = thread.messages.last(where: { $0.role == .user })?.id ?? thread.id
        var payload: [String: Any] = [
            "session_id": stableID(thread.id),
            "transcript_path": NSNull(),
            "cwd": workspaceRoot.standardizedFileURL.resolvingSymlinksInPath().path,
            "hook_event_name": eventName(for: timing),
            "model": thread.model,
            "turn_id": stableID(userTurnID),
            "permission_mode": permissionMode(for: thread.mode)
        ]
        switch timing {
        case .beforeAgentRun:
            payload["prompt"] = prompt
        case .afterAgentRun:
            payload["stop_hook_active"] = false
            payload["last_assistant_message"] = thread.messages
                .last(where: { $0.role == .assistant })?.content ?? ""
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func environment(
        for hook: ProjectRunHook,
        workspaceRoot: URL,
        pluginDataBaseDirectory: URL?
    ) throws -> [String: String] {
        var environment = hook.environment ?? [:]
        guard let pluginID = hook.pluginID,
              let rootRelativePath = hook.pluginRootRelativePath
        else { return environment }
        guard let pluginDataBaseDirectory else {
            throw ProjectRunHookInvocationError.pluginDataUnavailable
        }

        let workspaceRoot = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let pluginRootCandidate = workspaceRoot
            .appendingPathComponent(rootRelativePath, isDirectory: true)
            .standardizedFileURL
        let candidateValues = try pluginRootCandidate.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        let pluginRoot = pluginRootCandidate
            .resolvingSymlinksInPath()
        guard WorkspaceBoundary.isWithin(pluginRoot, root: workspaceRoot),
              candidateValues.isDirectory == true,
              candidateValues.isSymbolicLink != true
        else {
            throw ProjectRunHookInvocationError.invalidPluginRoot
        }
        let pluginData = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: pluginDataBaseDirectory,
            workspaceRoot: workspaceRoot,
            pluginID: pluginID
        )
        environment["PLUGIN_ROOT"] = pluginRoot.path
        environment["PLUGIN_DATA"] = pluginData.path
        environment["CLAUDE_PLUGIN_ROOT"] = pluginRoot.path
        environment["CLAUDE_PLUGIN_DATA"] = pluginData.path
        return environment
    }

    private static func eventName(for timing: ProjectRunHookTiming) -> String {
        switch timing {
        case .beforeAgentRun: return "UserPromptSubmit"
        case .afterAgentRun: return "Stop"
        }
    }

    private static func permissionMode(for mode: AgentMode) -> String {
        switch mode {
        case .plan: return "plan"
        case .auto: return "dontAsk"
        case .review, .readOnly: return "default"
        }
    }

    private static func stableID(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}

private enum ProjectRunHookInvocationError: LocalizedError {
    case invalidPluginRoot
    case pluginDataUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPluginRoot:
            return "Plugin root is missing or outside the current workspace."
        case .pluginDataUnavailable:
            return "Private plugin data storage is unavailable."
        }
    }
}
