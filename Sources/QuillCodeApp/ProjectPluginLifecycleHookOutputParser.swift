import CoreFoundation
import Foundation
import QuillCodeCore

enum ProjectPluginLifecycleHookOutputParser {
    static let maximumContextCharacters = 32_768
    static let maximumMessageCharacters = 4_096

    static func parse(
        event: ProjectPluginLifecycleHookEvent,
        result: ToolResult
    ) throws -> ProjectPluginLifecycleHookSemanticOutput {
        if result.exitCode == 2 {
            guard case .subagentStop = event else {
                throw ProjectPluginLifecycleHookOutputError.unsupportedExitCode
            }
            return ProjectPluginLifecycleHookSemanticOutput(
                continuationReason: boundedMessage(result.stderr)
                    ?? "Run one more focused pass inside the subagent."
            )
        }

        let stdout = normalized(result.stdout)
        guard !stdout.isEmpty else { return ProjectPluginLifecycleHookSemanticOutput() }
        guard let object = try? JSONSerialization.jsonObject(with: Data(stdout.utf8)) else {
            guard event.acceptsPlainTextContext else {
                throw ProjectPluginLifecycleHookOutputError.subagentStopOutputMustBeJSON
            }
            return ProjectPluginLifecycleHookSemanticOutput(
                additionalContext: bounded(stdout, limit: maximumContextCharacters)
            )
        }
        guard let dictionary = object as? [String: Any] else {
            throw ProjectPluginLifecycleHookOutputError.outputMustBeJSONObject
        }
        return try parseJSON(dictionary, event: event)
    }

    private static func parseJSON(
        _ dictionary: [String: Any],
        event: ProjectPluginLifecycleHookEvent
    ) throws -> ProjectPluginLifecycleHookSemanticOutput {
        let continues = try bool("continue", in: dictionary) ?? true
        _ = try bool("suppressOutput", in: dictionary) // Parsed for wire compatibility; intentionally inert.
        let stopReason = try string("stopReason", in: dictionary).flatMap(boundedMessage)
        let systemMessage = try string("systemMessage", in: dictionary).flatMap(boundedMessage)

        var continuationReason: String?
        if let decision = try string("decision", in: dictionary) {
            guard case .subagentStop = event else {
                throw ProjectPluginLifecycleHookOutputError.unsupportedDecision(decision)
            }
            guard decision == "block" else {
                throw ProjectPluginLifecycleHookOutputError.unsupportedDecision(decision)
            }
            guard let reason = try string("reason", in: dictionary).flatMap(boundedMessage) else {
                throw ProjectPluginLifecycleHookOutputError.missingBlockReason
            }
            continuationReason = reason
        }

        var additionalContext: String?
        if let rawSpecific = dictionary["hookSpecificOutput"] {
            guard event.acceptsPlainTextContext else {
                throw ProjectPluginLifecycleHookOutputError.hookSpecificOutputUnsupported
            }
            guard let specific = rawSpecific as? [String: Any] else {
                throw ProjectPluginLifecycleHookOutputError.invalidType("hookSpecificOutput")
            }
            let reportedEvent = try requiredString("hookEventName", in: specific)
            guard reportedEvent == event.name else {
                throw ProjectPluginLifecycleHookOutputError.eventMismatch(reportedEvent)
            }
            additionalContext = try string("additionalContext", in: specific)
                .map { bounded($0, limit: maximumContextCharacters) }
                .flatMap(nonEmpty)
        }

        return ProjectPluginLifecycleHookSemanticOutput(
            additionalContext: additionalContext,
            systemMessage: systemMessage,
            continues: continues,
            stopReason: stopReason,
            continuationReason: continuationReason
        )
    }

    private static func string(_ key: String, in dictionary: [String: Any]) throws -> String? {
        guard let value = dictionary[key] else { return nil }
        guard let value = value as? String else {
            throw ProjectPluginLifecycleHookOutputError.invalidType(key)
        }
        return value
    }

    private static func requiredString(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let value = try string(key, in: dictionary).flatMap(nonEmpty) else {
            throw ProjectPluginLifecycleHookOutputError.missingField(key)
        }
        return value
    }

    private static func bool(_ key: String, in dictionary: [String: Any]) throws -> Bool? {
        guard let value = dictionary[key] else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            throw ProjectPluginLifecycleHookOutputError.invalidType(key)
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

enum ProjectPluginLifecycleHookOutputError: LocalizedError, Equatable {
    case unsupportedExitCode
    case subagentStopOutputMustBeJSON
    case outputMustBeJSONObject
    case invalidType(String)
    case missingField(String)
    case missingBlockReason
    case unsupportedDecision(String)
    case hookSpecificOutputUnsupported
    case eventMismatch(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedExitCode:
            return "Only SubagentStop hooks can request continuation with exit code 2."
        case .subagentStopOutputMustBeJSON:
            return "SubagentStop hook output must be a JSON object."
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
            return "hookSpecificOutput is not valid for SubagentStop hooks."
        case .eventMismatch(let event):
            return "Hook output event does not match this lifecycle hook: \(event)."
        }
    }
}
