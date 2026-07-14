import Foundation

public struct ToolCall: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var argumentsJSON: String

    public init(id: String = "tool-\(UUID().uuidString)", name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public extension ToolCall {
    static let redactedEnvironmentValue = "<redacted>"
    static let redactedMemoryContentValue = "<redacted memory content>"
    static let redactedStandardInputValue = "<redacted standard input>"

    func redactedForTranscript() -> ToolCall {
        let redactedArguments = Self.redactedArgumentsJSON(argumentsJSON, toolName: name)
        guard redactedArguments != argumentsJSON else {
            return self
        }
        return ToolCall(id: id, name: name, argumentsJSON: redactedArguments)
    }

    static func redactedArgumentsJSON(_ argumentsJSON: String, toolName: String? = nil) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return argumentsJSON
        }

        var didRedact = false
        for key in ["environment", "env"] where object[key] != nil {
            object[key] = redactedEnvironmentPayload(object[key])
            didRedact = true
        }
        for key in ["stdin", "standardInput", "standard_input"] where object[key] != nil {
            object[key] = redactedStandardInputValue
            didRedact = true
        }
        if toolName == ToolDefinition.memoryRemember.name {
            for key in ["content", "reason"] where object[key] != nil {
                object[key] = redactedMemoryContentValue
                didRedact = true
            }
        }
        guard didRedact,
              JSONSerialization.isValidJSONObject(object),
              let output = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              )
        else {
            return argumentsJSON
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func redactedEnvironmentPayload(_ payload: Any?) -> Any {
        guard let environment = payload as? [String: Any] else {
            return redactedEnvironmentValue
        }
        return Dictionary(uniqueKeysWithValues: environment.keys.sorted().map {
            ($0, redactedEnvironmentValue)
        })
    }
}
