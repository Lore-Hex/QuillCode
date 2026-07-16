enum AppServerResponseItemValidator {
    static func validate(_ value: CLIJSONValue, index: Int) throws {
        do {
            try validateResponseItem(value)
            try validateInlineImages(in: value)
        } catch let error as AppServerResponseItemValidationError {
            throw AppServerRPCError.invalidRequest(
                "items[\(index)] is not a valid response item: \(error.description)"
            )
        } catch let error as AppServerRPCError {
            throw error
        }
    }

    static func typeDescription(_ value: CLIJSONValue) -> String {
        switch value {
        case .object: return "invalid type: map"
        case .array: return "invalid type: sequence"
        case .string(let value): return "invalid type: string \"\(value)\""
        case .number(let value): return "invalid type: floating point `\(value)`"
        case .bool(let value): return "invalid type: boolean `\(value)`"
        case .null: return "invalid type: null"
        }
    }

    private static func validateResponseItem(_ value: CLIJSONValue) throws {
        guard let object = value.objectValue else {
            throw AppServerResponseItemValidationError(
                "\(typeDescription(value)), expected internally tagged enum ResponseItem"
            )
        }
        guard let typeValue = object["type"] else {
            throw AppServerResponseItemValidationError("missing field `type`")
        }
        guard let type = typeValue.stringValue else {
            throw AppServerResponseItemValidationError(
                "\(typeDescription(typeValue)), expected variant identifier"
            )
        }

        switch type {
        case "message":
            try requireString("role", in: object)
            try requireArray("content", in: object).forEach(validateContentItem)
            try validateMessagePhase(in: object)
        case "agent_message":
            try requireStrings(["author", "recipient"], in: object)
            try requireArray("content", in: object).forEach(validateAgentMessageContent)
        case "reasoning":
            _ = try requireArray("summary", in: object)
            try validateOptionalArray("content", in: object)
            try validateOptionalString("encrypted_content", in: object)
        case "local_shell_call":
            try requireString("status", in: object)
            _ = try requireObject("action", in: object)
        case "function_call":
            try requireStrings(["name", "arguments", "call_id"], in: object)
            try validateOptionalString("namespace", in: object)
        case "tool_search_call":
            try requireString("execution", in: object)
            _ = try require("arguments", in: object)
        case "function_call_output":
            try requireString("call_id", in: object)
            try validateToolOutput(try require("output", in: object))
        case "custom_tool_call":
            try requireStrings(["call_id", "name", "input"], in: object)
        case "custom_tool_call_output":
            try requireString("call_id", in: object)
            try validateToolOutput(try require("output", in: object))
        case "tool_search_output":
            try requireStrings(["status", "execution"], in: object)
            _ = try requireArray("tools", in: object)
        case "image_generation_call":
            try requireStrings(["status", "result"], in: object)
        case "compaction", "compaction_summary":
            try requireString("encrypted_content", in: object)
        case "context_compaction":
            try validateOptionalString("encrypted_content", in: object)
        case "web_search_call", "compaction_trigger":
            break
        default:
            break
        }
    }

    private static func validateMessagePhase(in object: [String: CLIJSONValue]) throws {
        guard let phase = object["phase"], phase != .null else { return }
        let value = try string(phase, field: "phase")
        guard value == "commentary" || value == "final_answer" else {
            throw AppServerResponseItemValidationError(
                "unknown variant `\(value)`, expected `commentary` or `final_answer`"
            )
        }
    }

    private static func validateContentItem(_ value: CLIJSONValue) throws {
        guard let object = value.objectValue else {
            throw AppServerResponseItemValidationError(
                "\(typeDescription(value)), expected internally tagged enum ContentItem"
            )
        }
        let type = try string(try require("type", in: object), field: "type")
        switch type {
        case "input_text", "output_text":
            try requireString("text", in: object)
        case "input_image":
            try requireString("image_url", in: object)
            try validateImageDetail(in: object)
        default:
            throw AppServerResponseItemValidationError("unknown variant `\(type)`")
        }
    }

    private static func validateImageDetail(in object: [String: CLIJSONValue]) throws {
        guard let detail = object["detail"], detail != .null else { return }
        let value = try string(detail, field: "detail")
        guard ["auto", "low", "high", "original"].contains(value) else {
            throw AppServerResponseItemValidationError("unknown image detail `\(value)`")
        }
    }

    private static func validateAgentMessageContent(_ value: CLIJSONValue) throws {
        guard let object = value.objectValue else {
            throw AppServerResponseItemValidationError("agent message content must be an object")
        }
        let type = try string(try require("type", in: object), field: "type")
        switch type {
        case "input_text": try requireString("text", in: object)
        case "encrypted_content": try requireString("encrypted_content", in: object)
        default: throw AppServerResponseItemValidationError("unknown variant `\(type)`")
        }
    }

    private static func validateToolOutput(_ value: CLIJSONValue) throws {
        switch value {
        case .string:
            return
        case .array(let items):
            for item in items {
                guard let object = item.objectValue,
                      let type = object["type"]?.stringValue,
                      ["input_text", "input_image", "encrypted_content"].contains(type) else {
                    throw AppServerResponseItemValidationError("invalid tool output content item")
                }
            }
        default:
            throw AppServerResponseItemValidationError("tool output must be a string or sequence")
        }
    }

    private static func validateInlineImages(in value: CLIJSONValue) throws {
        switch value {
        case .object(let object):
            if object["type"]?.stringValue == "input_image",
               let url = object["image_url"]?.stringValue,
               !url.hasPrefix("data:") {
                throw AppServerRPCError.invalidRequest(
                    "remote image URLs are not supported; use an inline data URL instead"
                )
            }
            try object.values.forEach(validateInlineImages)
        case .array(let values):
            try values.forEach(validateInlineImages)
        case .string, .number, .bool, .null:
            break
        }
    }

    private static func require(
        _ field: String,
        in object: [String: CLIJSONValue]
    ) throws -> CLIJSONValue {
        guard let value = object[field] else {
            throw AppServerResponseItemValidationError("missing field `\(field)`")
        }
        return value
    }

    private static func requireString(_ field: String, in object: [String: CLIJSONValue]) throws {
        _ = try string(try require(field, in: object), field: field)
    }

    private static func requireStrings(_ fields: [String], in object: [String: CLIJSONValue]) throws {
        try fields.forEach { try requireString($0, in: object) }
    }

    private static func requireArray(
        _ field: String,
        in object: [String: CLIJSONValue]
    ) throws -> [CLIJSONValue] {
        let value = try require(field, in: object)
        guard let array = value.arrayValue else {
            throw AppServerResponseItemValidationError("field `\(field)` must be a sequence")
        }
        return array
    }

    private static func requireObject(
        _ field: String,
        in object: [String: CLIJSONValue]
    ) throws -> [String: CLIJSONValue] {
        let value = try require(field, in: object)
        guard let object = value.objectValue else {
            throw AppServerResponseItemValidationError("field `\(field)` must be an object")
        }
        return object
    }

    private static func string(_ value: CLIJSONValue, field: String) throws -> String {
        guard let string = value.stringValue else {
            throw AppServerResponseItemValidationError("field `\(field)` must be a string")
        }
        return string
    }

    private static func validateOptionalString(
        _ field: String,
        in object: [String: CLIJSONValue]
    ) throws {
        guard let value = object[field], value != .null else { return }
        _ = try string(value, field: field)
    }

    private static func validateOptionalArray(
        _ field: String,
        in object: [String: CLIJSONValue]
    ) throws {
        guard let value = object[field], value != .null else { return }
        guard value.arrayValue != nil else {
            throw AppServerResponseItemValidationError("field `\(field)` must be a sequence")
        }
    }
}

private struct AppServerResponseItemValidationError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
