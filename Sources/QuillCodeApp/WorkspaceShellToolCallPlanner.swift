import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceShellToolCallPlanner {
    static func localEnvironmentAction(_ action: LocalEnvironmentAction) -> ToolCall {
        shellRunToolCall(
            command: action.command,
            environment: action.environment,
            timeoutSeconds: action.timeoutSeconds
        )
    }

    static func projectExtensionUpdate(_ manifest: ProjectExtensionManifest) -> ToolCall? {
        let command = manifest.updateCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else { return nil }
        return shellRunToolCall(
            command: command,
            environment: nil,
            timeoutSeconds: manifest.updateTimeoutSeconds
        )
    }

    private static func shellRunToolCall(
        command: String,
        environment: [String: String]?,
        timeoutSeconds: Int?
    ) -> ToolCall {
        var arguments: [String: Any] = ["cmd": command]
        if let environment {
            arguments["environment"] = environment
        }
        if let timeoutSeconds {
            arguments["timeoutSeconds"] = timeoutSeconds
        }
        return ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(arguments)
        )
    }
}
