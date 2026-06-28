import Foundation

public enum AgentActionJSONParser {
    public static func parse(_ text: String) throws -> AgentAction {
        let trimmed = AgentActionJSONExtractor.strippedFences(
            from: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard let envelope = AgentActionJSONExtractor.actionObject(in: trimmed, looksLikeAction: looksLikeActionEnvelope),
              let object = normalizedActionObject(from: envelope)
        else {
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

    private static func looksLikeActionEnvelope(_ object: [String: Any]) -> Bool {
        normalizedActionObject(from: object) != nil
    }

    private static func normalizedActionObject(from object: [String: Any]) -> [String: Any]? {
        if let direct = directActionObject(from: object) {
            return direct
        }
        return nestedActionObject(in: object)
    }

    private static func directActionObject(from object: [String: Any]) -> [String: Any]? {
        if toolName(in: object) != nil {
            return canonicalToolObject(from: object)
        }
        guard let type = (object["type"] as? String)?.lowercased() else {
            return nil
        }
        switch type {
        case "say":
            return object
        case "message":
            if let nested = nestedActionObject(in: object) {
                return nested
            }
            if let text = stringValue(in: object, keys: ["text", "message", "content"]) {
                return ["type": "say", "text": text]
            }
            return nil
        case "tool", "tool_call", "call_tool", "function", "function_call", "tool_use":
            return canonicalToolObject(from: object)
        default:
            return nil
        }
    }

    private static func nestedActionObject(in object: [String: Any]) -> [String: Any]? {
        for key in ["tool_calls", "toolCalls", "calls", "output"] {
            guard let actions = object[key] as? [Any] else { continue }
            for action in actions {
                guard let nested = action as? [String: Any],
                      let normalized = normalizedActionObject(from: nested)
                else {
                    continue
                }
                return normalized
            }
        }

        for key in ["message", "delta"] {
            guard let nested = object[key] as? [String: Any],
                  let normalized = normalizedActionObject(from: nested)
            else {
                continue
            }
            return normalized
        }

        guard let choices = object["choices"] as? [Any] else {
            return nil
        }
        for choice in choices {
            guard let nested = choice as? [String: Any],
                  let normalized = normalizedActionObject(from: nested)
            else {
                continue
            }
            return normalized
        }
        return nil
    }

    private static func canonicalToolObject(from object: [String: Any]) -> [String: Any]? {
        var canonical = object
        if let function = object["function"] as? [String: Any] {
            if toolName(in: canonical) == nil,
               let name = stringValue(in: function, keys: ["name", "tool", "toolName", "tool_name"]) {
                canonical["name"] = name
            }
            if canonical["arguments"] == nil,
               canonical["args"] == nil,
               canonical["input"] == nil,
               let arguments = firstValue(in: function, keys: ["arguments", "args", "input"]) {
                canonical["arguments"] = arguments
            }
        }
        guard toolName(in: canonical) != nil else {
            return nil
        }
        canonical["type"] = "tool"
        return canonical
    }

    private static func toolName(in object: [String: Any]) -> String? {
        stringValue(in: object, keys: ["name", "tool", "toolName", "tool_name"])
    }

    private static func firstValue(in object: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            guard let value = object[key] else { continue }
            return value
        }
        return nil
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
