import Foundation
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

enum AgentFinalAnswerBuilder {
    static func finalAnswer(
        for call: ToolCall,
        result: ToolResult,
        followUpReviewResult: ToolResult? = nil
    ) -> String {
        if !result.ok {
            let details = [result.error, result.stderr.trimmedNonEmpty]
                .compactMap { $0 }
                .joined(separator: "\n")
            if details.isEmpty {
                return "Command failed."
            }
            return "Command failed:\n\(truncated(details))"
        }

        if call.name == ToolDefinition.fileWrite.name {
            if let path = argument("path", in: call) {
                return "Wrote `\(path)`."
            }
            if let path = result.artifacts.first {
                return "Wrote `\(path)`."
            }
            return "Wrote the file."
        }

        if call.name == ToolDefinition.applyPatch.name {
            if let followUpReviewResult, !followUpReviewResult.ok {
                let details = [followUpReviewResult.error, followUpReviewResult.stderr.trimmedNonEmpty]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                if details.isEmpty {
                    return "Patch applied, but I could not refresh the review diff."
                }
                return "Patch applied, but I could not refresh the review diff:\n\(truncated(details))"
            }
            return followUpReviewResult == nil
                ? "Patch applied."
                : "Patch applied. Review the resulting diff below."
        }

        if call.name == ToolDefinition.planUpdate.name {
            return "Updated the task plan."
        }

        if call.name == ToolDefinition.memoryRemember.name {
            if let output = try? JSONHelpers.decode(MemoryRememberToolOutput.self, from: result.stdout) {
                return "Saved memory: \(output.title). It will be included as background context in future turns."
            }
            return "Saved memory."
        }

        if call.name == ToolDefinition.shellRun.name,
           let command = argument("cmd", in: call) {
            if let answer = shellAnswer(command: command, result: result) {
                return answer
            }
        }

        if call.name == ToolDefinition.browserInspect.name,
           let inspection = try? JSONHelpers.decode(BrowserInspectionToolOutput.self, from: result.stdout) {
            return browserInspectionAnswer(inspection)
        }

        if call.name == ToolDefinition.browserOpen.name,
           let inspection = try? JSONHelpers.decode(BrowserInspectionToolOutput.self, from: result.stdout) {
            return browserOpenAnswer(inspection)
        }

        if call.name == ToolDefinition.mcpReadResource.name {
            let output = result.stdout.trimmedNonEmpty
            return output.map { "MCP resource contents:\n\(truncated($0))" }
                ?? "MCP resource read completed with no text content."
        }

        if call.name == ToolDefinition.mcpGetPrompt.name {
            let output = result.stdout.trimmedNonEmpty
            return output.map { "MCP prompt:\n\(truncated($0))" }
                ?? "MCP prompt loaded."
        }

        if call.name == ToolDefinition.computerScreenshot.name,
           let screenshot = try? JSONHelpers.decode(ComputerScreenshotToolOutput.self, from: result.stdout) {
            return "Captured a screenshot (\(screenshot.width) x \(screenshot.height))."
        }

        if ToolDefinition.computerUseDefinitions.contains(where: { $0.name == call.name }) {
            let output = result.stdout.trimmedNonEmpty
            return output.map { "Computer Use completed: \($0)" } ?? "Computer Use action completed."
        }

        let output = [result.stdout, result.stderr]
            .compactMap(\.trimmedNonEmpty)
            .joined(separator: "\n")
        if output.isEmpty {
            return "Done."
        }
        return "Output:\n\(truncated(output))"
    }

    private static func browserInspectionAnswer(_ inspection: BrowserInspectionToolOutput) -> String {
        var lines = [
            "Inspected `\(inspection.title)` at \(inspection.url).",
            "Inspection depth: \(inspection.inspectionDepth.label).",
            inspection.summary
        ]
        if !inspection.outline.isEmpty {
            lines.append("Outline: \(inspection.outline.prefix(5).joined(separator: "; ")).")
        }
        if let textSnippet = inspection.textSnippet?.trimmedNonEmpty {
            lines.append("Text: \(truncated(textSnippet, maxCharacters: 320))")
        }
        if !inspection.comments.isEmpty {
            lines.append("Browser comments: \(inspection.comments.map(\.text).prefix(3).joined(separator: "; ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func browserOpenAnswer(_ inspection: BrowserInspectionToolOutput) -> String {
        var lines = [
            "Opened `\(inspection.title)` at \(inspection.url).",
            inspection.summary
        ]
        if !inspection.outline.isEmpty {
            lines.append("Outline: \(inspection.outline.prefix(5).joined(separator: "; ")).")
        }
        if let textSnippet = inspection.textSnippet?.trimmedNonEmpty {
            lines.append("Text: \(truncated(textSnippet, maxCharacters: 320))")
        }
        return lines.joined(separator: "\n")
    }

    private static func shellAnswer(command: String, result: ToolResult) -> String? {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedCommand.lowercased()
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = stdout.isEmpty ? stderr : stdout

        if lower == "whoami" {
            guard !stdout.isEmpty else { return "The command ran, but did not print a user name." }
            return "You are `\(firstLine(stdout))` in this workspace."
        }

        if lower.contains("openclaw") && (lower.contains("command -v") || lower.contains("which ")) {
            let firstLine = firstLine(output)
            if firstLine.isEmpty || firstLine == "not found" {
                return "openclaw is not installed or is not on PATH."
            }
            return "openclaw is installed at `\(firstLine)`."
        }

        if lower.hasPrefix("df ") || lower.contains(" df ") || lower.contains("df -h") {
            guard !output.isEmpty else { return "Disk usage command completed with no output." }
            return "Disk usage:\n\(truncated(output))"
        }

        return nil
    }

    private static func argument(_ key: String, in call: ToolCall) -> String? {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private static func truncated(_ text: String, maxCharacters: Int = 2_000) -> String {
        guard text.count > maxCharacters else { return text }
        let end = text.index(text.startIndex, offsetBy: maxCharacters)
        return "\(text[..<end])\n\n[truncated in chat; full output is in the tool card]"
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
