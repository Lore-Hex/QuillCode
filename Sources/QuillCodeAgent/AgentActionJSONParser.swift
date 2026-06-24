import Foundation

public enum AgentActionJSONParser {
    public static func parse(_ text: String) throws -> AgentAction {
        let trimmed = AgentActionJSONExtractor.strippedFences(
            from: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard let object = AgentActionJSONExtractor.actionObject(in: trimmed, looksLikeAction: looksLikeActionObject) else {
            if let recovered = AgentShellCommandRecovery.recoveredAction(from: trimmed) {
                return recovered
            }
            throw TrustedRouterAgentError.invalidActionJSON(text)
        }
        let rawType = (object["type"] as? String) ?? (toolName(in: object) == nil ? nil : "tool")
        guard let type = rawType?.lowercased() else {
            throw TrustedRouterAgentError.invalidActionJSON(text)
        }
        switch type {
        case "say":
            return .say(stringValue(in: object, keys: ["text", "message", "content"]) ?? "")
        case "tool", "tool_call", "call_tool":
            guard let name = toolName(in: object) else {
                throw TrustedRouterAgentError.invalidActionJSON(text)
            }
            let arguments = AgentToolArgumentNormalizer.canonicalArguments(
                for: name,
                in: object,
                sourceText: trimmed
            )
            if !AgentToolArgumentNormalizer.hasMinimumRequiredArguments(
                for: name,
                arguments: arguments
            ) {
                throw TrustedRouterAgentError.emptyToolArguments(name)
            }
            let argumentsData = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
            return .tool(.init(name: name, argumentsJSON: String(decoding: argumentsData, as: UTF8.self)))
        default:
            throw TrustedRouterAgentError.invalidActionJSON(text)
        }
    }

    private static func looksLikeActionObject(_ object: [String: Any]) -> Bool {
        object["type"] is String || toolName(in: object) != nil
    }

    private static func toolName(in object: [String: Any]) -> String? {
        stringValue(in: object, keys: ["name", "tool", "toolName", "tool_name"])
    }

    private static func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = object[key] as? String else { continue }
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }
}
