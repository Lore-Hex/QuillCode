import CoreFoundation
import Foundation
import QuillCodeCore

enum ProjectPluginToolHookDecision: Sendable, Hashable {
    case allow
    case deny
}

struct ProjectPluginToolHookSemanticOutput: Sendable, Hashable {
    var decision: ProjectPluginToolHookDecision? = nil
    var decisionReason: String? = nil
    var updatedInputJSON: String? = nil
    var additionalContext: String? = nil
    var systemMessage: String? = nil
    var replacementFeedback: String? = nil
}

enum ProjectPluginToolHookOutputParser {
    static let maximumContextCharacters = 32_768
    static let maximumMessageCharacters = 4_096
    static let maximumUpdatedInputBytes = 262_144

    static func parse(
        event: ProjectPluginToolHookEvent,
        result: ToolResult
    ) throws -> ProjectPluginToolHookSemanticOutput {
        if result.exitCode == 2, event.treatsExitTwoAsDecision {
            let fallback = event == .preToolUse
                ? "The hook blocked this tool call."
                : "The hook rejected the tool result."
            let feedback = boundedMessage(result.stderr) ?? fallback
            return event == .preToolUse
                ? ProjectPluginToolHookSemanticOutput(
                    decision: .deny,
                    decisionReason: feedback
                )
                : ProjectPluginToolHookSemanticOutput(replacementFeedback: feedback)
        }

        let stdout = normalized(result.stdout)
        guard !stdout.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: Data(stdout.utf8))
        else {
            // Standard tool hooks ignore plain stdout.
            return ProjectPluginToolHookSemanticOutput()
        }
        guard let dictionary = object as? [String: Any] else {
            throw ProjectPluginToolHookOutputError.outputMustBeJSONObject
        }
        return try parseJSON(dictionary, event: event)
    }

    private static func parseJSON(
        _ dictionary: [String: Any],
        event: ProjectPluginToolHookEvent
    ) throws -> ProjectPluginToolHookSemanticOutput {
        let systemMessage = try string("systemMessage", in: dictionary).flatMap(boundedMessage)
        switch event {
        case .preToolUse:
            return try parsePreToolUse(dictionary, systemMessage: systemMessage)
        case .postToolUse:
            return try parsePostToolUse(dictionary, systemMessage: systemMessage)
        case .permissionRequest:
            return try parsePermissionRequest(dictionary, systemMessage: systemMessage)
        }
    }

    private static func parsePermissionRequest(
        _ dictionary: [String: Any],
        systemMessage: String?
    ) throws -> ProjectPluginToolHookSemanticOutput {
        for unsupported in ["continue", "stopReason", "suppressOutput"]
            where dictionary[unsupported] != nil {
                throw ProjectPluginToolHookOutputError.unsupportedField(unsupported)
        }

        var output = ProjectPluginToolHookSemanticOutput(systemMessage: systemMessage)
        guard let rawSpecific = dictionary["hookSpecificOutput"] else { return output }
        guard let specific = rawSpecific as? [String: Any] else {
            throw ProjectPluginToolHookOutputError.invalidType("hookSpecificOutput")
        }
        try validateEvent(.permissionRequest, in: specific)
        for unsupported in ["updatedInput", "updatedPermissions", "interrupt"]
            where specific[unsupported] != nil {
                throw ProjectPluginToolHookOutputError.unsupportedField(unsupported)
        }
        guard let rawDecision = specific["decision"] else { return output }
        guard let decision = rawDecision as? [String: Any] else {
            throw ProjectPluginToolHookOutputError.invalidType("decision")
        }
        let behavior = try requiredString("behavior", in: decision)
        switch behavior {
        case "allow":
            output.decision = .allow
        case "deny":
            output.decision = .deny
            output.decisionReason = try string("message", in: decision)
                .flatMap(boundedMessage)
                ?? "The permission hook denied this tool call."
        default:
            throw ProjectPluginToolHookOutputError.unsupportedDecision(behavior)
        }
        return output
    }

    private static func parsePreToolUse(
        _ dictionary: [String: Any],
        systemMessage: String?
    ) throws -> ProjectPluginToolHookSemanticOutput {
        if dictionary["suppressOutput"] != nil {
            throw ProjectPluginToolHookOutputError.unsupportedField("suppressOutput")
        }
        if dictionary["stopReason"] != nil {
            throw ProjectPluginToolHookOutputError.unsupportedField("stopReason")
        }
        if try bool("continue", in: dictionary) == false {
            throw ProjectPluginToolHookOutputError.unsupportedField("continue")
        }

        var output = ProjectPluginToolHookSemanticOutput(systemMessage: systemMessage)
        if let legacyDecision = try string("decision", in: dictionary) {
            guard legacyDecision == "block" else {
                throw ProjectPluginToolHookOutputError.unsupportedDecision(legacyDecision)
            }
            output.decision = .deny
            output.decisionReason = try requiredBoundedReason(in: dictionary)
        }

        guard let rawSpecific = dictionary["hookSpecificOutput"] else { return output }
        guard let specific = rawSpecific as? [String: Any] else {
            throw ProjectPluginToolHookOutputError.invalidType("hookSpecificOutput")
        }
        try validateEvent(.preToolUse, in: specific)
        output.additionalContext = try string("additionalContext", in: specific)
            .map { bounded($0, limit: maximumContextCharacters) }
            .flatMap(nonEmpty)

        if let decision = try string("permissionDecision", in: specific) {
            switch decision {
            case "allow": output.decision = .allow
            case "deny": output.decision = .deny
            case "ask": throw ProjectPluginToolHookOutputError.unsupportedDecision(decision)
            default: throw ProjectPluginToolHookOutputError.unsupportedDecision(decision)
            }
            output.decisionReason = try string("permissionDecisionReason", in: specific)
                .flatMap(boundedMessage) ?? output.decisionReason
        }

        if let updatedInput = specific["updatedInput"] {
            guard output.decision == .allow else {
                throw ProjectPluginToolHookOutputError.updatedInputRequiresAllow
            }
            output.updatedInputJSON = try encodedUpdatedInput(updatedInput)
        }
        if output.decision == .deny, output.decisionReason == nil {
            output.decisionReason = "The hook blocked this tool call."
        }
        return output
    }

    private static func parsePostToolUse(
        _ dictionary: [String: Any],
        systemMessage: String?
    ) throws -> ProjectPluginToolHookSemanticOutput {
        if dictionary["suppressOutput"] != nil {
            throw ProjectPluginToolHookOutputError.unsupportedField("suppressOutput")
        }
        if dictionary["updatedMCPToolOutput"] != nil {
            throw ProjectPluginToolHookOutputError.unsupportedField("updatedMCPToolOutput")
        }

        var output = ProjectPluginToolHookSemanticOutput(systemMessage: systemMessage)
        if let decision = try string("decision", in: dictionary) {
            guard decision == "block" else {
                throw ProjectPluginToolHookOutputError.unsupportedDecision(decision)
            }
            output.replacementFeedback = try requiredBoundedReason(in: dictionary)
        }
        if try bool("continue", in: dictionary) == false {
            output.replacementFeedback = try string("stopReason", in: dictionary)
                .flatMap(boundedMessage)
                ?? output.replacementFeedback
                ?? "The hook stopped after this tool result."
        }

        if let rawSpecific = dictionary["hookSpecificOutput"] {
            guard let specific = rawSpecific as? [String: Any] else {
                throw ProjectPluginToolHookOutputError.invalidType("hookSpecificOutput")
            }
            try validateEvent(.postToolUse, in: specific)
            for unsupported in ["permissionDecision", "permissionDecisionReason", "updatedInput"]
                where specific[unsupported] != nil {
                throw ProjectPluginToolHookOutputError.unsupportedField(unsupported)
            }
            output.additionalContext = try string("additionalContext", in: specific)
                .map { bounded($0, limit: maximumContextCharacters) }
                .flatMap(nonEmpty)
        }
        return output
    }

    private static func validateEvent(
        _ event: ProjectPluginToolHookEvent,
        in dictionary: [String: Any]
    ) throws {
        let name = try requiredString("hookEventName", in: dictionary)
        guard name == event.rawValue else {
            throw ProjectPluginToolHookOutputError.eventMismatch(name)
        }
    }

    private static func encodedUpdatedInput(_ value: Any) throws -> String {
        guard value is [String: Any], JSONSerialization.isValidJSONObject(value) else {
            throw ProjectPluginToolHookOutputError.updatedInputMustBeObject
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= maximumUpdatedInputBytes else {
            throw ProjectPluginToolHookOutputError.updatedInputTooLarge
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func requiredBoundedReason(in dictionary: [String: Any]) throws -> String {
        guard let reason = try string("reason", in: dictionary).flatMap(boundedMessage) else {
            throw ProjectPluginToolHookOutputError.missingBlockReason
        }
        return reason
    }

    private static func requiredString(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let value = try string(key, in: dictionary), !value.isEmpty else {
            throw ProjectPluginToolHookOutputError.missingField(key)
        }
        return value
    }

    private static func string(_ key: String, in dictionary: [String: Any]) throws -> String? {
        guard let value = dictionary[key] else { return nil }
        guard let value = value as? String else {
            throw ProjectPluginToolHookOutputError.invalidType(key)
        }
        return value
    }

    private static func bool(_ key: String, in dictionary: [String: Any]) throws -> Bool? {
        guard let value = dictionary[key] else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            throw ProjectPluginToolHookOutputError.invalidType(key)
        }
        return number.boolValue
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundedMessage(_ value: String) -> String? {
        nonEmpty(bounded(normalized(value), limit: maximumMessageCharacters))
    }

    private static func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "..."
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}

enum ProjectPluginToolHookOutputError: LocalizedError, Equatable {
    case outputMustBeJSONObject
    case invalidType(String)
    case missingField(String)
    case missingBlockReason
    case unsupportedDecision(String)
    case unsupportedField(String)
    case updatedInputRequiresAllow
    case updatedInputMustBeObject
    case updatedInputTooLarge
    case eventMismatch(String)

    var errorDescription: String? {
        switch self {
        case .outputMustBeJSONObject:
            return "Hook output must be a JSON object."
        case .invalidType(let field):
            return "Hook output field \(field) has an invalid type."
        case .missingField(let field):
            return "Hook output is missing \(field)."
        case .missingBlockReason:
            return "A blocking hook decision must include a reason."
        case .unsupportedDecision(let decision):
            return "Unsupported hook decision: \(decision)."
        case .unsupportedField(let field):
            return "Unsupported hook output field: \(field)."
        case .updatedInputRequiresAllow:
            return "updatedInput requires permissionDecision allow."
        case .updatedInputMustBeObject:
            return "updatedInput must be a JSON object."
        case .updatedInputTooLarge:
            return "updatedInput exceeds the supported size."
        case .eventMismatch(let event):
            return "Hook output event does not match the active event: \(event)."
        }
    }
}
