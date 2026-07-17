import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

extension AppServerSession {
    func userShellFeedbackMessage(
        launch: UserShellLaunch,
        result: ToolResult,
        completedAt: Date
    ) -> ChatMessage {
        let arguments = CLIJSONValue.object(["cmd": .string(launch.command)])
        let argumentsJSON = (try? CLIJSONCodec.encode(arguments))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let feedback = AgentToolFeedback(
            toolCall: ToolCall(
                id: launch.itemID,
                name: ToolDefinition.shellRun.name,
                argumentsJSON: argumentsJSON
            ),
            result: result
        )
        let content = (try? JSONEncoder().encode(feedback))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return ChatMessage(
            role: .tool,
            content: content,
            turnID: launch.turnID,
            createdAt: completedAt
        )
    }

    func cappedUserShellResult(_ result: ToolResult) -> ToolResult {
        ToolResult(
            ok: result.ok,
            stdout: ShellOutputCapper.cap(result.stdout).text,
            stderr: ShellOutputCapper.cap(result.stderr).text,
            exitCode: result.exitCode,
            error: result.error,
            artifacts: result.artifacts
        )
    }

    func userShellItem(
        launch: UserShellLaunch,
        status: String,
        aggregatedOutput: String?,
        exitCode: Int32?,
        durationMilliseconds: Double?
    ) -> CLIJSONValue {
        .object([
            "type": .string("commandExecution"),
            "id": .string(launch.itemID),
            "command": .string(
                "\(launch.shellExecutablePath) -lc \(shellSingleQuoted(launch.command))"
            ),
            "cwd": .string(launch.cwd.path),
            "processId": .null,
            "source": .string("userShell"),
            "status": .string(status),
            "commandActions": .array([.object([
                "type": .string("unknown"),
                "command": .string(launch.command)
            ])]),
            "aggregatedOutput": aggregatedOutput.map(CLIJSONValue.string) ?? .null,
            "exitCode": exitCode.map { .number(Double($0)) } ?? .null,
            "durationMs": durationMilliseconds.map(CLIJSONValue.number) ?? .null
        ])
    }

    func userShellLifecycleParams(
        launch: UserShellLaunch,
        item: CLIJSONValue,
        timestampKey: String,
        date: Date
    ) -> CLIJSONValue {
        .object([
            "threadId": .string(AppServerThreadProjection.identifier(launch.threadID)),
            "turnId": .string(launch.turnID),
            "item": item,
            timestampKey: .number((date.timeIntervalSince1970 * 1_000).rounded())
        ])
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
