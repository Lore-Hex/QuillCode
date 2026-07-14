import CoreFoundation
import Foundation
import QuillCodeCore

struct ProjectRunHookSemanticOutput: Sendable, Equatable {
    var additionalContext: String?
    var systemMessage: String?
    var continues = true
    var stopReason: String?
    var blockReason: String?
}

enum ProjectRunHookOutputParser {
    static let maximumContextCharacters = 32_768
    static let maximumMessageCharacters = 4_096

    static func parse(
        timing: ProjectRunHookTiming,
        result: ToolResult
    ) throws -> ProjectRunHookSemanticOutput {
        if result.exitCode == 2 {
            let fallback = timing == .beforeAgentRun
                ? "The hook blocked this prompt."
                : "The hook requested another agent turn."
            return ProjectRunHookSemanticOutput(
                blockReason: boundedMessage(result.stderr) ?? fallback
            )
        }

        let stdout = normalized(result.stdout)
        guard !stdout.isEmpty else { return ProjectRunHookSemanticOutput() }

        guard let object = try? JSONSerialization.jsonObject(with: Data(stdout.utf8)) else {
            guard timing == .beforeAgentRun else {
                throw ProjectRunHookOutputError.stopOutputMustBeJSON
            }
            return ProjectRunHookSemanticOutput(
                additionalContext: bounded(stdout, limit: maximumContextCharacters)
            )
        }
        guard let dictionary = object as? [String: Any] else {
            throw ProjectRunHookOutputError.outputMustBeJSONObject
        }
        return try parseJSON(dictionary, timing: timing)
    }

    private static func parseJSON(
        _ dictionary: [String: Any],
        timing: ProjectRunHookTiming
    ) throws -> ProjectRunHookSemanticOutput {
        let continues = try bool("continue", in: dictionary) ?? true
        _ = try bool("suppressOutput", in: dictionary)
        let stopReason = try string("stopReason", in: dictionary).flatMap(boundedMessage)
        let systemMessage = try string("systemMessage", in: dictionary).flatMap(boundedMessage)

        var blockReason: String?
        if let decision = try string("decision", in: dictionary) {
            guard decision == "block" else {
                throw ProjectRunHookOutputError.unsupportedDecision(decision)
            }
            guard let reason = try string("reason", in: dictionary).flatMap(boundedMessage) else {
                throw ProjectRunHookOutputError.missingBlockReason
            }
            blockReason = reason
        }

        var additionalContext: String?
        if let hookSpecific = dictionary["hookSpecificOutput"] {
            guard timing == .beforeAgentRun else {
                throw ProjectRunHookOutputError.hookSpecificOutputUnsupported
            }
            guard let hookSpecific = hookSpecific as? [String: Any] else {
                throw ProjectRunHookOutputError.invalidType("hookSpecificOutput")
            }
            let eventName = try requiredString("hookEventName", in: hookSpecific)
            guard eventName == "UserPromptSubmit" else {
                throw ProjectRunHookOutputError.eventMismatch(eventName)
            }
            additionalContext = try string("additionalContext", in: hookSpecific)
                .map { bounded($0, limit: maximumContextCharacters) }
                .flatMap(nonEmpty)
        }

        return ProjectRunHookSemanticOutput(
            additionalContext: additionalContext,
            systemMessage: systemMessage,
            continues: continues,
            stopReason: stopReason,
            blockReason: blockReason
        )
    }

    private static func string(_ key: String, in dictionary: [String: Any]) throws -> String? {
        guard let value = dictionary[key] else { return nil }
        guard let value = value as? String else {
            throw ProjectRunHookOutputError.invalidType(key)
        }
        return value
    }

    private static func requiredString(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let value = try string(key, in: dictionary), !value.isEmpty else {
            throw ProjectRunHookOutputError.missingField(key)
        }
        return value
    }

    private static func bool(_ key: String, in dictionary: [String: Any]) throws -> Bool? {
        guard let value = dictionary[key] else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            throw ProjectRunHookOutputError.invalidType(key)
        }
        return number.boolValue
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\0", with: "")
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

enum ProjectRunHookOutputError: LocalizedError, Equatable {
    case stopOutputMustBeJSON
    case outputMustBeJSONObject
    case invalidType(String)
    case missingField(String)
    case missingBlockReason
    case unsupportedDecision(String)
    case hookSpecificOutputUnsupported
    case eventMismatch(String)

    var errorDescription: String? {
        switch self {
        case .stopOutputMustBeJSON:
            return "Stop hook output must be a JSON object."
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
        case .hookSpecificOutputUnsupported:
            return "hookSpecificOutput is only valid for UserPromptSubmit hooks."
        case .eventMismatch(let event):
            return "Hook output event does not match UserPromptSubmit: \(event)."
        }
    }
}
