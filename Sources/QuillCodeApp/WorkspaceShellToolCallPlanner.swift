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
        projectExtensionCommand(
            manifest.updateCommand,
            timeoutSeconds: manifest.updateTimeoutSeconds
        )
    }

    static func projectExtensionInstall(_ manifest: ProjectExtensionManifest) -> ToolCall? {
        projectExtensionCommand(
            manifest.installCommand,
            timeoutSeconds: manifest.installTimeoutSeconds
        )
    }

    private static func projectExtensionCommand(
        _ rawCommand: String?,
        timeoutSeconds: Int?
    ) -> ToolCall? {
        let command = rawCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else { return nil }
        return shellRunToolCall(command: command, environment: nil, timeoutSeconds: timeoutSeconds)
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
