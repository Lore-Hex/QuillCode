import CoreFoundation
import Foundation
import QuillCodeCore

struct ProjectPluginCompactionHookSemanticOutput: Sendable, Hashable {
    var continues = true
    var stopReason: String?
    var systemMessage: String?
}

enum ProjectPluginCompactionHookOutputParser {
    static let maximumMessageCharacters = 4_096

    static func parse(_ result: ToolResult) throws -> ProjectPluginCompactionHookSemanticOutput {
        let stdout = normalized(result.stdout)
        guard !stdout.isEmpty else { return ProjectPluginCompactionHookSemanticOutput() }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(stdout.utf8))
        } catch {
            throw ProjectPluginCompactionHookOutputError.invalidJSON
        }
        guard let dictionary = object as? [String: Any] else {
            throw ProjectPluginCompactionHookOutputError.outputMustBeJSONObject
        }
        if dictionary["hookSpecificOutput"] != nil {
            throw ProjectPluginCompactionHookOutputError.unsupportedField("hookSpecificOutput")
        }
        _ = try bool("suppressOutput", in: dictionary) // Parsed for wire compatibility; intentionally inert.
        let continues = try bool("continue", in: dictionary) ?? true
        return ProjectPluginCompactionHookSemanticOutput(
            continues: continues,
            stopReason: try string("stopReason", in: dictionary).flatMap(boundedMessage),
            systemMessage: try string("systemMessage", in: dictionary).flatMap(boundedMessage)
        )
    }

    private static func string(_ key: String, in dictionary: [String: Any]) throws -> String? {
        guard let value = dictionary[key] else { return nil }
        guard let value = value as? String else {
            throw ProjectPluginCompactionHookOutputError.invalidType(key)
        }
        return value
    }

    private static func bool(_ key: String, in dictionary: [String: Any]) throws -> Bool? {
        guard let value = dictionary[key] else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            throw ProjectPluginCompactionHookOutputError.invalidType(key)
        }
        return number.boolValue
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boundedMessage(_ value: String) -> String? {
        let normalized = normalized(value)
        guard !normalized.isEmpty else { return nil }
        guard normalized.count > maximumMessageCharacters else { return normalized }
        return String(normalized.prefix(maximumMessageCharacters)) + "..."
    }
}

enum ProjectPluginCompactionHookOutputError: LocalizedError, Equatable {
    case invalidJSON
    case outputMustBeJSONObject
    case invalidType(String)
    case unsupportedField(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Hook output must be valid JSON."
        case .outputMustBeJSONObject:
            return "Hook output must be a JSON object."
        case .invalidType(let field):
            return "Hook output field \(field) has an invalid type."
        case .unsupportedField(let field):
            return "Unsupported hook output field: \(field)."
        }
    }
}
