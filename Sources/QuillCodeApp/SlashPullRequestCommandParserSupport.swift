import Foundation
import QuillCodeCore
import QuillCodeTools

extension SlashPullRequestCommandParser {
    static func selectorAndBody(from argument: String) -> (selector: String?, body: String) {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace).first else {
            return (nil, "")
        }
        let firstToken = String(first)
        guard looksLikePullRequestSelector(firstToken) else {
            return (nil, trimmed)
        }
        let bodyStart = trimmed.index(trimmed.startIndex, offsetBy: firstToken.count)
        let body = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (normalizedPullRequestSelector(firstToken), body)
    }

    static func pullRequestLabels(from body: String) -> [String] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains(",") {
            return trimmed.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func looksLikePullRequestSelector(_ token: String) -> Bool {
        let normalized = normalizedPullRequestSelector(token)
        guard !normalized.isEmpty else { return false }
        if normalized.allSatisfy(\.isNumber) {
            return true
        }
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return true
        }
        return normalized.contains("/") && !normalized.hasPrefix("-")
    }

    static func normalizedPullRequestSelector(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
    }

    static func pullRequestTool(_ definition: ToolDefinition, selector: String) -> SlashCommand {
        pullRequestTool(definition, arguments: compact(["selector": selector]))
    }

    static func pullRequestTool(_ definition: ToolDefinition, arguments: [String: Any]) -> SlashCommand {
        .toolCall(ToolCall(name: definition.name, argumentsJSON: ToolArguments.json(arguments)))
    }

    static func compact(_ values: [String: Any?]) -> [String: Any] {
        values.compactMapValues { value in
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return value
        }
    }
}
