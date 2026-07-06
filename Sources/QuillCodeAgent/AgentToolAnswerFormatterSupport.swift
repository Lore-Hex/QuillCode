import Foundation
import QuillCodeCore

enum AgentToolAnswerFormatterSupport {
    static func argument(_ key: String, in call: ToolCall) -> String? {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func boolArgument(_ key: String, in call: ToolCall) -> Bool? {
        guard let data = call.argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key]
        else {
            return nil
        }
        if let bool = value as? Bool {
            return bool
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    /// The failure detail for a tool result: the error message plus any stderr, each trimmed, with
    /// empty entries dropped, newline-joined. "" when there is nothing to show.
    static func failureDetail(_ result: ToolResult) -> String {
        [result.error, result.stderr]
            .compactMap { $0?.trimmedNonEmpty }
            .joined(separator: "\n")
    }

    /// stdout and stderr combined: each trimmed, empty dropped, newline-joined.
    static func combinedOutput(_ result: ToolResult) -> String {
        [result.stdout, result.stderr]
            .compactMap(\.trimmedNonEmpty)
            .joined(separator: "\n")
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
