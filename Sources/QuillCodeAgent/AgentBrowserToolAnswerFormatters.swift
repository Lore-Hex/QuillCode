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
        var lines = browserAnswerLines(
            leadingLine: "Inspected `\(inspection.title)` at \(inspection.url).",
            inspection: inspection,
            includeDepth: true
        )
        if !inspection.comments.isEmpty {
            lines.append("Browser comments: \(inspection.comments.map(\.text).prefix(3).joined(separator: "; ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func browserOpenAnswer(_ inspection: BrowserInspectionToolOutput) -> String {
        browserAnswerLines(
            leadingLine: "Opened `\(inspection.title)` at \(inspection.url).",
            inspection: inspection,
            includeDepth: false
        )
        .joined(separator: "\n")
    }

    private static func browserAnswerLines(
        leadingLine: String,
        inspection: BrowserInspectionToolOutput,
        includeDepth: Bool
    ) -> [String] {
        var lines = [
            leadingLine,
            inspection.summary
        ]
        if includeDepth {
            lines.insert("Inspection depth: \(inspection.inspectionDepth.label).", at: 1)
        }
        if !inspection.outline.isEmpty {
            lines.append("Outline: \(inspection.outline.prefix(5).joined(separator: "; ")).")
        }
        if let textSnippet = inspection.textSnippet?.trimmedNonEmpty {
            lines.append("Text: \(AgentToolAnswerFormatters.truncated(textSnippet, maxCharacters: 320))")
        }
        return lines
    }
}
