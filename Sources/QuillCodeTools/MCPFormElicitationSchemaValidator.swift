import Foundation

/// Validates the typed form subset exposed by Codex app-server.
///
/// Keeping this strict prevents malformed or unrenderable MCP schemas from crossing into an app
/// client. Rich OpenAI forms deliberately bypass this validator and remain opaque JSON.
enum MCPFormElicitationSchemaValidator {
    static func validate(_ value: MCPJSONValue) throws {
        let root = try object(value, context: "requestedSchema")
        try requireOnly(root, keys: ["$schema", "type", "properties", "required"], context: "requestedSchema")
        if let schemaURI = root["$schema"] {
            _ = try nullableString(schemaURI, context: "$schema")
        }
        guard root["type"]?.stringValue == "object" else {
            throw invalid("requestedSchema.type must be 'object'.")
        }

        let properties = try object(required(root, "properties"), context: "requestedSchema.properties")
        guard properties.count <= 256 else {
            throw invalid("requestedSchema contains too many properties.")
        }
        for (name, schema) in properties {
            guard !name.isEmpty, name.count <= 256 else {
                throw invalid("requestedSchema contains an invalid property name.")
            }
            try validateProperty(schema, context: "requestedSchema.properties.\(name)")
        }

        if let requiredValue = root["required"], requiredValue != .null {
            let names = try stringArray(requiredValue, context: "requestedSchema.required")
            guard Set(names).count == names.count,
                  names.allSatisfy({ properties[$0] != nil })
            else {
                throw invalid("requestedSchema.required must contain unique property names.")
            }
        }
    }

    private static func validateProperty(_ value: MCPJSONValue, context: String) throws {
        let schema = try object(value, context: context)
        guard let type = schema["type"]?.stringValue else {
            throw invalid("\(context).type is required.")
        }
        switch type {
        case "string": try validateString(schema, context: context)
        case "number", "integer": try validateNumber(schema, context: context)
        case "boolean": try validateBoolean(schema, context: context)
        case "array": try validateArray(schema, context: context)
        default: throw invalid("\(context).type '\(type)' is unsupported.")
        }
    }

    private static func validateString(_ schema: [String: MCPJSONValue], context: String) throws {
        if schema["oneOf"] != nil {
            try requireOnly(schema, keys: ["type", "title", "description", "oneOf", "default"], context: context)
            let options = try constOptions(required(schema, "oneOf"), context: "\(context).oneOf")
            try validateDefaultString(schema["default"], options: options, context: context)
            try validateLabels(schema, context: context)
            return
        }
        if schema["enum"] != nil {
            try requireOnly(
                schema,
                keys: ["type", "title", "description", "enum", "enumNames", "default"],
                context: context
            )
            let options = try nonemptyUniqueStrings(required(schema, "enum"), context: "\(context).enum")
            if let names = schema["enumNames"], names != .null {
                let labels = try stringArray(names, context: "\(context).enumNames")
                guard labels.count == options.count else {
                    throw invalid("\(context).enumNames must match enum count.")
                }
            }
            try validateDefaultString(schema["default"], options: options, context: context)
            try validateLabels(schema, context: context)
            return
        }

        try requireOnly(
            schema,
            keys: ["type", "title", "description", "minLength", "maxLength", "format", "default"],
            context: context
        )
        try validateLabels(schema, context: context)
        let minimum = try optionalUnsignedInteger(schema["minLength"], context: "\(context).minLength")
        let maximum = try optionalUnsignedInteger(schema["maxLength"], context: "\(context).maxLength")
        try validateRange(minimum: minimum, maximum: maximum, context: context)
        if let format = schema["format"], format != .null {
            guard ["email", "uri", "date", "date-time"].contains(try string(format, context: "\(context).format")) else {
                throw invalid("\(context).format is unsupported.")
            }
        }
        if let value = schema["default"] { _ = try nullableString(value, context: "\(context).default") }
    }

    private static func validateNumber(_ schema: [String: MCPJSONValue], context: String) throws {
        try requireOnly(
            schema,
            keys: ["type", "title", "description", "minimum", "maximum", "default"],
            context: context
        )
        try validateLabels(schema, context: context)
        let minimum = try optionalNumber(schema["minimum"], context: "\(context).minimum")
        let maximum = try optionalNumber(schema["maximum"], context: "\(context).maximum")
        try validateRange(minimum: minimum, maximum: maximum, context: context)
        if let value = schema["default"] { _ = try nullableNumber(value, context: "\(context).default") }
    }

    private static func validateBoolean(_ schema: [String: MCPJSONValue], context: String) throws {
        try requireOnly(schema, keys: ["type", "title", "description", "default"], context: context)
        try validateLabels(schema, context: context)
        if let value = schema["default"], value != .null {
            guard case .bool = value else { throw invalid("\(context).default must be a boolean.") }
        }
    }

    private static func validateArray(_ schema: [String: MCPJSONValue], context: String) throws {
        try requireOnly(
            schema,
            keys: ["type", "title", "description", "minItems", "maxItems", "items", "default"],
            context: context
        )
        try validateLabels(schema, context: context)
        let minimum = try optionalUnsignedInteger(schema["minItems"], context: "\(context).minItems")
        let maximum = try optionalUnsignedInteger(schema["maxItems"], context: "\(context).maxItems")
        try validateRange(minimum: minimum, maximum: maximum, context: context)

        let items = try object(required(schema, "items"), context: "\(context).items")
        let options: [String]
        if let anyOf = items["anyOf"] ?? items["oneOf"] {
            try requireOnly(items, keys: [items["anyOf"] == nil ? "oneOf" : "anyOf"], context: "\(context).items")
            options = try constOptions(anyOf, context: "\(context).items")
        } else {
            try requireOnly(items, keys: ["type", "enum"], context: "\(context).items")
            guard items["type"]?.stringValue == "string" else {
                throw invalid("\(context).items.type must be 'string'.")
            }
            options = try nonemptyUniqueStrings(required(items, "enum"), context: "\(context).items.enum")
        }

        if let defaultValue = schema["default"], defaultValue != .null {
            let defaults = try stringArray(defaultValue, context: "\(context).default")
            guard defaults.allSatisfy(options.contains) else {
                throw invalid("\(context).default must use declared options.")
            }
        }
    }

    private static func validateLabels(_ schema: [String: MCPJSONValue], context: String) throws {
        for key in ["title", "description"] {
            if let value = schema[key] { _ = try nullableString(value, context: "\(context).\(key)") }
        }
    }

    private static func validateDefaultString(
        _ value: MCPJSONValue?,
        options: [String],
        context: String
    ) throws {
        guard let value, value != .null else { return }
        let selected = try string(value, context: "\(context).default")
        guard options.contains(selected) else {
            throw invalid("\(context).default must be one of the declared options.")
        }
    }

    private static func constOptions(_ value: MCPJSONValue, context: String) throws -> [String] {
        guard case .array(let values) = value, !values.isEmpty else {
            throw invalid("\(context) must be a non-empty array.")
        }
        let options = try values.map { value -> String in
            let option = try object(value, context: context)
            try requireOnly(option, keys: ["const", "title"], context: context)
            _ = try string(required(option, "title"), context: "\(context).title")
            return try string(required(option, "const"), context: "\(context).const")
        }
        guard Set(options).count == options.count else {
            throw invalid("\(context) contains duplicate values.")
        }
        return options
    }

    private static func nonemptyUniqueStrings(_ value: MCPJSONValue, context: String) throws -> [String] {
        let values = try stringArray(value, context: context)
        guard !values.isEmpty, Set(values).count == values.count else {
            throw invalid("\(context) must contain unique values.")
        }
        return values
    }

    private static func stringArray(_ value: MCPJSONValue, context: String) throws -> [String] {
        guard case .array(let values) = value, values.count <= 256 else {
            throw invalid("\(context) must be an array.")
        }
        return try values.map { try string($0, context: context) }
    }

    private static func object(_ value: MCPJSONValue, context: String) throws -> [String: MCPJSONValue] {
        guard case .object(let object) = value else { throw invalid("\(context) must be an object.") }
        return object
    }

    private static func required(_ object: [String: MCPJSONValue], _ key: String) throws -> MCPJSONValue {
        guard let value = object[key] else { throw invalid("\(key) is required.") }
        return value
    }

    private static func requireOnly(
        _ object: [String: MCPJSONValue],
        keys: Set<String>,
        context: String
    ) throws {
        let unknown = Set(object.keys).subtracting(keys)
        guard unknown.isEmpty else {
            throw invalid("\(context) contains unsupported field '\(unknown.sorted()[0])'.")
        }
    }

    private static func string(_ value: MCPJSONValue, context: String) throws -> String {
        guard case .string(let string) = value, string.count <= 16_384 else {
            throw invalid("\(context) must be a bounded string.")
        }
        return string
    }

    private static func nullableString(_ value: MCPJSONValue, context: String) throws -> String? {
        if value == .null { return nil }
        return try string(value, context: context)
    }

    private static func optionalNumber(_ value: MCPJSONValue?, context: String) throws -> Double? {
        guard let value else { return nil }
        return try nullableNumber(value, context: context)
    }

    private static func nullableNumber(_ value: MCPJSONValue, context: String) throws -> Double? {
        if value == .null { return nil }
        guard case .number(let number) = value, number.isFinite else {
            throw invalid("\(context) must be a finite number.")
        }
        return number
    }

    private static func optionalUnsignedInteger(_ value: MCPJSONValue?, context: String) throws -> UInt64? {
        guard let value, value != .null else { return nil }
        guard case .number(let number) = value,
              number.isFinite,
              number >= 0,
              number.rounded(.towardZero) == number,
              number <= Double(UInt32.max)
        else {
            throw invalid("\(context) must be a nonnegative integer.")
        }
        return UInt64(number)
    }

    private static func validateRange<T: Comparable>(minimum: T?, maximum: T?, context: String) throws {
        if let minimum, let maximum, minimum > maximum {
            throw invalid("\(context) minimum cannot exceed maximum.")
        }
    }

    private static func invalid(_ message: String) -> MCPProbeError {
        .invalidMessage("Invalid MCP elicitation schema: \(message)")
    }
}
