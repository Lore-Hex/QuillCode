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

        if isDownloadCommand(lower), let path = downloadedPath(from: normalizedCommand) {
            if result.ok {
                return "Downloaded to `\(path)`."
            }
            let reason = output.isEmpty ? "the command failed with no output" : AgentToolAnswerFormatters.truncated(output)
            return "Download failed: \(reason)"
        }

        return nil
    }

    private static func isDownloadCommand(_ command: String) -> Bool {
        (command.contains("curl ") || command.hasPrefix("curl"))
            || (command.contains("wget ") || command.hasPrefix("wget"))
    }

    private static func downloadedPath(from command: String) -> String? {
        let patterns = [
            #"--output\s+('[^']+'|"[^"]+"|\S+)"#,
            #"\s-o\s+('[^']+'|"[^"]+"|\S+)"#,
            #">\s*('[^']+'|"[^"]+"|\S+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
                  let range = Range(match.range(at: 1), in: command)
            else {
                continue
            }
            return unquoted(String(command[range]))
        }
        return nil
    }

    private static func unquoted(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))
            || (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) {
            trimmed.removeFirst()
            trimmed.removeLast()
        }
        return trimmed
    }
}
