import Foundation
import QuillCodeCore
import QuillCodeTools

enum AgentShellToolAnswerFormatters {
    static func shellRunAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.shellRun.name,
              let command = AgentToolAnswerFormatterSupport.argument("cmd", in: call)
        else {
            return nil
        }
        return shellAnswer(command: command, result: result)
    }

    private static func shellAnswer(command: String, result: ToolResult) -> String? {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedCommand.lowercased()
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = stdout.isEmpty ? stderr : stdout

        if lower == "whoami" {
            guard !stdout.isEmpty else { return "The command ran, but did not print a user name." }
            return "You are `\(AgentToolAnswerFormatterSupport.firstLine(stdout))` in this workspace."
        }

        if lower.contains("openclaw") && (lower.contains("command -v") || lower.contains("which ")) {
            let firstLine = AgentToolAnswerFormatterSupport.firstLine(output)
            if firstLine.isEmpty || firstLine == "not found" {
                return "openclaw is not installed or is not on PATH."
            }
            return "openclaw is installed at `\(firstLine)`."
        }

        if lower.hasPrefix("df ") || lower.contains(" df ") || lower.contains("df -h") {
            guard !output.isEmpty else { return "Disk usage command completed with no output." }
            return "Disk usage:\n\(AgentToolAnswerFormatters.truncated(output))"
        }

        return nil
    }
}
