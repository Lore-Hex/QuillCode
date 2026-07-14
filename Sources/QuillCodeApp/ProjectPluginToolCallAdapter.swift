import Foundation
import QuillCodeCore
import QuillCodeTools

enum ProjectPluginToolKind: Sendable, Hashable {
    case shell
    case patch
    case mcp
}

struct ProjectPluginToolCallAdapter: Sendable, Hashable {
    static let maximumMatcherCharacters = ProjectPluginHookMatcher.maximumPatternCharacters
    static let maximumToolNameCharacters = 256

    var call: ToolCall
    var kind: ProjectPluginToolKind
    var canonicalName: String
    var aliases: [String]
    var toolInputJSON: String

    static func make(for call: ToolCall) -> ProjectPluginToolCallAdapter? {
        guard let object = jsonObject(call.argumentsJSON) else { return nil }
        switch call.name {
        case ToolDefinition.shellRun.name:
            guard let command = object["cmd"] as? String else { return nil }
            var input = object
            input.removeValue(forKey: "cmd")
            input["command"] = command
            return adapter(
                call: call,
                kind: .shell,
                canonicalName: "Bash",
                aliases: ["Bash"],
                input: input
            )
        case ToolDefinition.applyPatch.name:
            guard let command = object["patch"] as? String else { return nil }
            return adapter(
                call: call,
                kind: .patch,
                canonicalName: "apply_patch",
                aliases: ["apply_patch", "Edit", "Write"],
                input: ["command": command]
            )
        case ToolDefinition.mcpCall.name:
            guard let serverID = normalizedNamePart(object["serverID"] as? String),
                  let toolName = normalizedNamePart(object["toolName"] as? String),
                  let input = mcpArguments(from: object)
            else { return nil }
            let canonicalName = "mcp__\(serverID)__\(toolName)"
            return adapter(
                call: call,
                kind: .mcp,
                canonicalName: canonicalName,
                aliases: [canonicalName],
                input: input
            )
        default:
            return nil
        }
    }

    func replacingToolInput(with updatedInputJSON: String) throws -> ToolCall {
        guard let updatedInput = Self.jsonObject(updatedInputJSON) else {
            throw ProjectPluginToolCallAdapterError.updatedInputMustBeObject
        }
        guard var original = Self.jsonObject(call.argumentsJSON) else {
            throw ProjectPluginToolCallAdapterError.invalidOriginalInput
        }

        switch kind {
        case .shell:
            original["cmd"] = try Self.requiredCommand(in: updatedInput)
        case .patch:
            original["patch"] = try Self.requiredCommand(in: updatedInput)
        case .mcp:
            original["arguments"] = updatedInput
            original.removeValue(forKey: "argumentsJSON")
        }
        return ToolCall(
            id: call.id,
            name: call.name,
            argumentsJSON: try Self.jsonString(original)
        )
    }

    func matches(_ matcher: String?) -> Bool {
        ProjectPluginHookMatcher.matches(matcher, candidates: aliases)
    }

    static func isValidMatcher(_ matcher: String?) -> Bool {
        ProjectPluginHookMatcher.isValid(matcher)
    }

    private static func adapter(
        call: ToolCall,
        kind: ProjectPluginToolKind,
        canonicalName: String,
        aliases: [String],
        input: [String: Any]
    ) -> ProjectPluginToolCallAdapter? {
        guard let toolInputJSON = try? jsonString(input) else { return nil }
        return ProjectPluginToolCallAdapter(
            call: call,
            kind: kind,
            canonicalName: canonicalName,
            aliases: aliases,
            toolInputJSON: toolInputJSON
        )
    }

    private static func mcpArguments(from object: [String: Any]) -> [String: Any]? {
        if let arguments = object["arguments"] as? [String: Any] {
            return arguments
        }
        guard let argumentsJSON = object["argumentsJSON"] as? String else { return [:] }
        return jsonObject(argumentsJSON)
    }

    private static func normalizedNamePart(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
                ? Character(String(scalar))
                : "_"
        }
        let result = String(normalized.prefix(maximumToolNameCharacters / 2))
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? nil : result
    }

    private static func requiredCommand(in object: [String: Any]) throws -> String {
        guard let command = object["command"] as? String else {
            throw ProjectPluginToolCallAdapterError.updatedCommandMissing
        }
        return command
    }

    private static func jsonObject(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ProjectPluginToolCallAdapterError.updatedInputMustBeObject
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

enum ProjectPluginToolCallAdapterError: LocalizedError, Equatable {
    case invalidOriginalInput
    case updatedInputMustBeObject
    case updatedCommandMissing

    var errorDescription: String? {
        switch self {
        case .invalidOriginalInput:
            return "The original tool input is not a JSON object."
        case .updatedInputMustBeObject:
            return "updatedInput must be a JSON object."
        case .updatedCommandMissing:
            return "updatedInput must include a string command."
        }
    }
}
