import QuillCodeCore
import QuillCodeTools

enum AgentWebToolAnswerFormatters {
    static func webFetchAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.webFetch.name else {
            return nil
        }
        let url = AgentToolAnswerFormatterSupport.argument("url", in: call) ?? "the page"
        if !result.ok {
            let details = [result.error, result.stderr.trimmedNonEmpty]
                .compactMap { $0?.trimmedNonEmpty }
                .joined(separator: "\n")
            return details.isEmpty
                ? "Could not fetch \(url)."
                : "Could not fetch \(url): \(AgentToolAnswerFormatters.truncated(details))"
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            return "Fetched \(url), but it returned no readable content."
        }
        return AgentToolAnswerFormatters.truncated(output)
    }

    static func webSearchAnswer(
        call: ToolCall,
        result: ToolResult,
        followUpReviewResult _: ToolResult?
    ) -> String? {
        guard call.name == ToolDefinition.webSearch.name else {
            return nil
        }
        let query = AgentToolAnswerFormatterSupport.argument("query", in: call) ?? "the query"
        if !result.ok {
            let details = [result.error, result.stderr.trimmedNonEmpty]
                .compactMap { $0?.trimmedNonEmpty }
                .joined(separator: "\n")
            return details.isEmpty
                ? "Could not search for \(query)."
                : "Could not search for \(query): \(AgentToolAnswerFormatters.truncated(details))"
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            return "Searched for \(query), but found no results."
        }
        return AgentToolAnswerFormatters.truncated(output)
    }
}
