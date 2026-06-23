import Foundation

struct MCPToolCallRequest {
    var serverID: String
    var toolName: String
    var toolArgumentsJSON: String

    init(argumentsJSON: String) throws {
        let object = try MCPRequestJSON.object(from: argumentsJSON, invalidError: MCPToolCallRequestError.invalidJSON)

        self.serverID = MCPRequestJSON.trimmedString(object["serverID"] ?? object["serverId"])
        self.toolName = MCPRequestJSON.trimmedString(object["toolName"] ?? object["name"])
        guard !serverID.isEmpty else { throw MCPToolCallRequestError.missingServerID }
        guard !toolName.isEmpty else { throw MCPToolCallRequestError.missingToolName }

        self.toolArgumentsJSON = MCPRequestJSON.argumentsJSON(from: object)
    }
}

enum MCPToolCallRequestError: Error, CustomStringConvertible {
    case invalidJSON
    case missingServerID
    case missingToolName

    var description: String {
        switch self {
        case .invalidJSON:
            return "MCP call arguments must be a JSON object."
        case .missingServerID:
            return "MCP call requires a non-empty serverID."
        case .missingToolName:
            return "MCP call requires a non-empty toolName."
        }
    }
}

struct MCPResourceReadRequest {
    var serverID: String
    var resourceIdentifier: String

    init(argumentsJSON: String) throws {
        let object = try MCPRequestJSON.object(
            from: argumentsJSON,
            invalidError: MCPResourceReadRequestError.invalidJSON
        )

        self.serverID = MCPRequestJSON.trimmedString(object["serverID"] ?? object["serverId"])
        self.resourceIdentifier = MCPRequestJSON.trimmedString(
            object["resourceURI"] ?? object["uri"] ?? object["resourceName"] ?? object["name"]
        )
        guard !serverID.isEmpty else { throw MCPResourceReadRequestError.missingServerID }
        guard !resourceIdentifier.isEmpty else { throw MCPResourceReadRequestError.missingResource }
    }

    func resourceURI(in summary: MCPServerProbeSummary?) -> String? {
        guard let summary else { return nil }
        let trimmed = resourceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if summary.resourceURIs.contains(trimmed) {
            return trimmed
        }
        if summary.resourceURIs.isEmpty && summary.resourceNames.contains(trimmed) {
            return trimmed
        }
        for (index, name) in summary.resourceNames.enumerated()
            where name == trimmed && summary.resourceURIs.indices.contains(index) {
            return summary.resourceURIs[index]
        }
        return nil
    }
}

enum MCPResourceReadRequestError: Error, CustomStringConvertible {
    case invalidJSON
    case missingServerID
    case missingResource

    var description: String {
        switch self {
        case .invalidJSON:
            return "MCP resource read arguments must be a JSON object."
        case .missingServerID:
            return "MCP resource read requires a non-empty serverID."
        case .missingResource:
            return "MCP resource read requires a non-empty resourceURI or resourceName."
        }
    }
}

struct MCPPromptGetRequest {
    var serverID: String
    var promptName: String
    var promptArgumentsJSON: String

    init(argumentsJSON: String) throws {
        let object = try MCPRequestJSON.object(from: argumentsJSON, invalidError: MCPPromptGetRequestError.invalidJSON)

        self.serverID = MCPRequestJSON.trimmedString(object["serverID"] ?? object["serverId"])
        self.promptName = MCPRequestJSON.trimmedString(object["promptName"] ?? object["name"])
        guard !serverID.isEmpty else { throw MCPPromptGetRequestError.missingServerID }
        guard !promptName.isEmpty else { throw MCPPromptGetRequestError.missingPromptName }

        self.promptArgumentsJSON = MCPRequestJSON.argumentsJSON(from: object)
    }
}

enum MCPPromptGetRequestError: Error, CustomStringConvertible {
    case invalidJSON
    case missingServerID
    case missingPromptName

    var description: String {
        switch self {
        case .invalidJSON:
            return "MCP prompt arguments must be a JSON object."
        case .missingServerID:
            return "MCP prompt get requires a non-empty serverID."
        case .missingPromptName:
            return "MCP prompt get requires a non-empty promptName."
        }
    }
}

private enum MCPRequestJSON {
    static func object<E: Error>(from json: String, invalidError: E) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            throw invalidError
        }
        return object
    }

    static func trimmedString(_ value: Any?) -> String {
        (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func argumentsJSON(from object: [String: Any]) -> String {
        if let argumentsJSON = object["argumentsJSON"] as? String,
           !argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return argumentsJSON
        }
        if let arguments = object["arguments"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return "{}"
    }
}
