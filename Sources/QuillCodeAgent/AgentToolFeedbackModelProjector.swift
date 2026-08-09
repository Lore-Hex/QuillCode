import Foundation
import QuillCodeCore
import QuillCodeTools

/// Keeps the durable tool card lossless while bounding the observation replayed to the model.
/// Long web pages otherwise get copied into every subsequent request in the sliding history.
enum AgentToolFeedbackModelProjector {
    private static let sourceReadLimit = 12_000
    private static let delegatedOutputLimit = 12_000
    private static let genericOutputLimit = 4_000

    static func project(_ content: String) -> String {
        guard let data = content.data(using: .utf8),
              let feedback = try? JSONDecoder().decode(AgentToolFeedback.self, from: data)
        else {
            return AgentToolAnswerFormatters.truncated(content, maxCharacters: genericOutputLimit)
        }

        let call = feedback.toolCall
        let result = feedback.result
        let heading = "Tool observation: \(call.name)\(argumentSummary(for: call))"

        if call.name == ToolDefinition.fileRead.name
            || call.name == ToolDefinition.fileReadMany.name {
            return heading + "\n" + sourceReadObservation(result)
        }

        if call.name == ToolDefinition.subagentsRun.name,
           let formatted = AgentToolAnswerFormatters.all.lazy.compactMap({
               $0(call, result, feedback.followUpResult)
           }).first {
            return heading + "\n" + AgentToolAnswerFormatters.truncated(
                formatted,
                maxCharacters: delegatedOutputLimit
            )
        }

        if let formatted = AgentToolAnswerFormatters.all.lazy.compactMap({
            $0(call, result, feedback.followUpResult)
        }).first {
            return heading + "\n" + AgentToolAnswerFormatters.truncated(
                formatted,
                maxCharacters: genericOutputLimit
            )
        }

        return heading + "\n" + genericObservation(result)
    }

    private static func sourceReadObservation(_ result: ToolResult) -> String {
        guard result.ok else { return failureObservation(result) }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return "The read succeeded with no content." }
        return AgentToolAnswerFormatters.truncated(output, maxCharacters: sourceReadLimit)
    }

    private static func genericObservation(_ result: ToolResult) -> String {
        guard result.ok else { return failureObservation(result) }
        let output = AgentToolAnswerFormatterSupport.combinedOutput(result)
        guard !output.isEmpty else { return "The tool completed successfully." }
        return AgentToolAnswerFormatters.truncated(output, maxCharacters: genericOutputLimit)
    }

    private static func failureObservation(_ result: ToolResult) -> String {
        let details = [result.error, result.stderr.trimmedNonEmpty, result.stdout.trimmedNonEmpty]
            .compactMap { $0 }
            .joined(separator: "\n")
        guard !details.isEmpty else { return "The tool failed without diagnostic output." }
        return "The tool failed:\n" + AgentToolAnswerFormatters.truncated(
            details,
            maxCharacters: genericOutputLimit
        )
    }

    private static func argumentSummary(for call: ToolCall) -> String {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }

        let visibleKeys = ["path", "paths", "url", "query", "name", "cmd", "pattern"]
        var summary: [String: Any] = [:]
        for key in visibleKeys where object[key] != nil {
            summary[key] = object[key]
        }
        guard !summary.isEmpty,
              let encoded = try? JSONSerialization.data(
                  withJSONObject: summary,
                  options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: encoded, encoding: .utf8)
        else { return "" }
        return " \(AgentToolAnswerFormatters.truncated(text, maxCharacters: 1_000))"
    }
}
