import Foundation
import QuillCodeCore

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
            return "Command failed:\n\(AgentToolAnswerFormatters.truncated(details))"
        }

        for formatter in AgentToolAnswerFormatters.all {
            if let answer = formatter(call, result, followUpReviewResult) {
                return answer
            }
        }

        return defaultAnswer(result)
    }

    private static func defaultAnswer(_ result: ToolResult) -> String {
        let output = [result.stdout, result.stderr]
            .compactMap(\.trimmedNonEmpty)
            .joined(separator: "\n")
        if output.isEmpty {
            return "Done."
        }
        return "Output:\n\(AgentToolAnswerFormatters.truncated(output))"
    }
}
