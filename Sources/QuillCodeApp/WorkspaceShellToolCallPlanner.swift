import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceShellToolCallPlanner {
    static func localEnvironmentAction(_ action: LocalEnvironmentAction) -> ToolCall {
        shellRunToolCall(
            command: action.command,
            environment: action.environment,
            timeoutSeconds: action.timeoutSeconds,
            standardInput: nil,
            workingDirectory: nil
        )
    }

    static func projectRunHook(
        _ hook: ProjectRunHook,
        environment: [String: String],
        standardInput: String
    ) -> ToolCall {
        shellRunToolCall(
            command: hook.command,
            environment: environment,
            timeoutSeconds: hook.timeoutSeconds,
            standardInput: standardInput,
            workingDirectory: hook.workingDirectory
        )
    }

    static func worktreeSetupScript(_ script: WorktreeSetupScript) -> ToolCall {
        shellRunToolCall(
            command: script.command,
            environment: script.environment,
            timeoutSeconds: script.timeoutSeconds,
            standardInput: nil,
            workingDirectory: nil
        )
    }

    static func command(
        _ rawCommand: String?,
        timeoutSeconds: Int?
    ) -> ToolCall? {
        let command = rawCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !command.isEmpty else { return nil }
        return shellRunToolCall(
            command: command,
            environment: nil,
            timeoutSeconds: timeoutSeconds,
            standardInput: nil,
            workingDirectory: nil
        )
    }

    private static func shellRunToolCall(
        command: String,
        environment: [String: String]?,
        timeoutSeconds: Int?,
        standardInput: String?,
        workingDirectory: String?
    ) -> ToolCall {
        var arguments: [String: Any] = ["cmd": command]
        if let environment {
            arguments["environment"] = environment
        }
        if let timeoutSeconds {
            arguments["timeoutSeconds"] = timeoutSeconds
        }
        if let standardInput {
            arguments["stdin"] = standardInput
        }
        if let workingDirectory {
            arguments["cwd"] = workingDirectory
        }
        return ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(arguments)
        )
    }
}
