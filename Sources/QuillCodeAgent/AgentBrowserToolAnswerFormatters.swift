import QuillCodeCore

enum AgentBrowserToolAnswerFormatters {
    static func browserInspectAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.browserInspect.name,
              let inspection = try? JSONHelpers.decode(BrowserInspectionToolOutput.self, from: result.stdout)
        else {
            return nil
        }
        return browserInspectionAnswer(inspection)
    }

    static func browserOpenAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.browserOpen.name,
              let inspection = try? JSONHelpers.decode(BrowserInspectionToolOutput.self, from: result.stdout)
        else {
            return nil
        }
        return browserOpenAnswer(inspection)
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
            lines.append("Text: \(AgentToolAnswerFormatters.truncated(textSnippet, maxCharacters: 320))")
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
            lines.append("Text: \(AgentToolAnswerFormatters.truncated(textSnippet, maxCharacters: 320))")
        }
        return lines.joined(separator: "\n")
    }
}
