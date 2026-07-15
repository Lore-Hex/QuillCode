import Foundation

struct CLIOutputSchema: Sendable {
    static let maximumBytes = 262_144
    static let maximumValidationDepth = 64

    let schema: CLIJSONValue
    let compactJSON: String

    static func load(from url: URL) throws -> CLIOutputSchema {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw CLIError.invalidOutputSchema("\(url.path) is not a regular file.")
        }
        if let size = values.fileSize, size > maximumBytes {
            throw CLIError.outputSchemaTooLarge(limit: maximumBytes)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumBytes else { throw CLIError.outputSchemaTooLarge(limit: maximumBytes) }
        let schema: CLIJSONValue
        do {
            schema = try CLIJSONCodec.decode(data)
        } catch {
            throw CLIError.invalidOutputSchema("The file is not valid JSON: \(error.localizedDescription)")
        }
        guard schema.objectValue != nil || schema.boolValue != nil else {
            throw CLIError.invalidOutputSchema("The root must be a JSON object or boolean schema.")
        }
        return CLIOutputSchema(
            schema: schema,
            compactJSON: String(decoding: try CLIJSONCodec.encode(schema), as: UTF8.self)
        )
    }

    var modelInstruction: String {
        """
        The final answer must be exactly one JSON value matching this JSON Schema. Do not wrap it in Markdown.
        JSON Schema: \(compactJSON)
        """
    }

    func validate(finalMessage: String) throws {
        let payload = Self.unfencedJSON(finalMessage)
        let value: CLIJSONValue
        do {
            value = try CLIJSONCodec.decode(payload)
        } catch {
            throw CLIError.structuredOutputMismatch("The response is not valid JSON.")
        }
        let validator = CLIJSONSchemaValidator(root: schema)
        if let failure = validator.validate(value) {
            throw CLIError.structuredOutputMismatch(failure)
        }
    }

    private static func unfencedJSON(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return trimmed }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CLIJSONSchemaValidator {
    let root: CLIJSONValue

    func validate(_ value: CLIJSONValue) -> String? {
        validate(value, schema: root, path: "$", depth: 0)
    }

    private func validate(
        _ value: CLIJSONValue,
        schema: CLIJSONValue,
        path: String,
        depth: Int
    ) -> String? {
        guard depth <= CLIOutputSchema.maximumValidationDepth else {
            return "Schema nesting exceeds the supported depth at \(path)."
        }
        if let allowed = schema.boolValue {
            return allowed ? nil : "\(path) is rejected by a false schema."
        }
        guard let object = schema.objectValue else { return "Schema at \(path) is not an object." }

        if let reference = object["$ref"]?.stringValue {
            guard let resolved = resolve(reference: reference) else {
                return "Schema reference \(reference) at \(path) cannot be resolved."
            }
            if let failure = validate(value, schema: resolved, path: path, depth: depth + 1) {
                return failure
            }
        }
        if let constant = object["const"], constant != value {
            return "\(path) does not match the required constant."
        }
        if let options = object["enum"]?.arrayValue, !options.contains(value) {
            return "\(path) is not one of the allowed enum values."
        }
        if let failure = validateCombinators(value, object: object, path: path, depth: depth) {
            return failure
        }
        if let expected = object["type"], !matchesType(value, declaration: expected) {
            return "\(path) has type \(typeName(value)); expected \(typeDescription(expected))."
        }

        switch value {
        case .object(let instance):
            return validateObject(instance, schema: object, path: path, depth: depth)
        case .array(let instance):
            return validateArray(instance, schema: object, path: path, depth: depth)
        case .string(let instance):
            return validateString(instance, schema: object, path: path)
        case .number(let instance):
            return validateNumber(instance, schema: object, path: path)
        case .bool, .null:
            return nil
        }
    }

    private func validateCombinators(
        _ value: CLIJSONValue,
        object: [String: CLIJSONValue],
        path: String,
        depth: Int
    ) -> String? {
        if let schemas = object["allOf"]?.arrayValue {
            for schema in schemas {
                if let failure = validate(value, schema: schema, path: path, depth: depth + 1) {
                    return failure
                }
            }
        }
        if let schemas = object["anyOf"]?.arrayValue,
           !schemas.contains(where: { validate(value, schema: $0, path: path, depth: depth + 1) == nil }) {
            return "\(path) does not match any anyOf schema."
        }
        if let schemas = object["oneOf"]?.arrayValue {
            let matches = schemas.filter { validate(value, schema: $0, path: path, depth: depth + 1) == nil }
            if matches.count != 1 { return "\(path) must match exactly one oneOf schema." }
        }
        if let negated = object["not"], validate(value, schema: negated, path: path, depth: depth + 1) == nil {
            return "\(path) matches a forbidden schema."
        }
        return nil
    }

    private func validateObject(
        _ instance: [String: CLIJSONValue],
        schema: [String: CLIJSONValue],
        path: String,
        depth: Int
    ) -> String? {
        if let minimum = integer(schema["minProperties"]), instance.count < minimum {
            return "\(path) has fewer than \(minimum) properties."
        }
        if let maximum = integer(schema["maxProperties"]), instance.count > maximum {
            return "\(path) has more than \(maximum) properties."
        }
        let properties = schema["properties"]?.objectValue ?? [:]
        for name in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where instance[name] == nil {
            return "\(path) is missing required property \(name)."
        }
        for (name, value) in instance.sorted(by: { $0.key < $1.key }) {
            if let propertySchema = properties[name] {
                if let failure = validate(
                    value,
                    schema: propertySchema,
                    path: "\(path).\(name)",
                    depth: depth + 1
                ) {
                    return failure
                }
                continue
            }
            if schema["additionalProperties"]?.boolValue == false {
                return "\(path) contains unsupported property \(name)."
            }
            if let additional = schema["additionalProperties"], additional.objectValue != nil,
               let failure = validate(value, schema: additional, path: "\(path).\(name)", depth: depth + 1) {
                return failure
            }
        }
        return nil
    }

    private func validateArray(
        _ instance: [CLIJSONValue],
        schema: [String: CLIJSONValue],
        path: String,
        depth: Int
    ) -> String? {
        if let minimum = integer(schema["minItems"]), instance.count < minimum {
            return "\(path) has fewer than \(minimum) items."
        }
        if let maximum = integer(schema["maxItems"]), instance.count > maximum {
            return "\(path) has more than \(maximum) items."
        }
        if schema["uniqueItems"]?.boolValue == true, Set(instance).count != instance.count {
            return "\(path) must contain unique items."
        }
        if let itemSchema = schema["items"] {
            for (index, value) in instance.enumerated() {
                if let failure = validate(
                    value,
                    schema: itemSchema,
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                ) {
                    return failure
                }
            }
        }
        return nil
    }

    private func validateString(
        _ instance: String,
        schema: [String: CLIJSONValue],
        path: String
    ) -> String? {
        if let minimum = integer(schema["minLength"]), instance.count < minimum {
            return "\(path) is shorter than \(minimum) characters."
        }
        if let maximum = integer(schema["maxLength"]), instance.count > maximum {
            return "\(path) is longer than \(maximum) characters."
        }
        if let pattern = schema["pattern"]?.stringValue,
           (try? NSRegularExpression(pattern: pattern))?.firstMatch(
               in: instance,
               range: NSRange(instance.startIndex..., in: instance)
           ) == nil {
            return "\(path) does not match the required pattern."
        }
        return nil
    }

    private func validateNumber(
        _ instance: Double,
        schema: [String: CLIJSONValue],
        path: String
    ) -> String? {
        if let minimum = schema["minimum"]?.numberValue, instance < minimum {
            return "\(path) is less than \(minimum)."
        }
        if let maximum = schema["maximum"]?.numberValue, instance > maximum {
            return "\(path) is greater than \(maximum)."
        }
        if let minimum = schema["exclusiveMinimum"]?.numberValue, instance <= minimum {
            return "\(path) must be greater than \(minimum)."
        }
        if let maximum = schema["exclusiveMaximum"]?.numberValue, instance >= maximum {
            return "\(path) must be less than \(maximum)."
        }
        if let multiple = schema["multipleOf"]?.numberValue, multiple > 0 {
            let quotient = instance / multiple
            if abs(quotient.rounded() - quotient) > 1e-9 {
                return "\(path) is not a multiple of \(multiple)."
            }
        }
        return nil
    }

    private func resolve(reference: String) -> CLIJSONValue? {
        guard reference == "#" || reference.hasPrefix("#/") else { return nil }
        if reference == "#" { return root }
        return reference.dropFirst(2).split(separator: "/").reduce(Optional(root)) { current, token in
            guard let current else { return nil }
            let key = token.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            if let object = current.objectValue { return object[key] }
            if let array = current.arrayValue, let index = Int(key), array.indices.contains(index) {
                return array[index]
            }
            return nil
        }
    }

    private func matchesType(_ value: CLIJSONValue, declaration: CLIJSONValue) -> Bool {
        if let type = declaration.stringValue { return matchesType(value, type: type) }
        return declaration.arrayValue?.compactMap(\.stringValue).contains { matchesType(value, type: $0) } == true
    }

    private func matchesType(_ value: CLIJSONValue, type: String) -> Bool {
        switch (value, type) {
        case (.object, "object"), (.array, "array"), (.string, "string"),
             (.number, "number"), (.bool, "boolean"), (.null, "null"):
            true
        case (.number(let value), "integer"):
            value.isFinite && value.rounded() == value
        default:
            false
        }
    }

    private func typeName(_ value: CLIJSONValue) -> String {
        switch value {
        case .object: "object"
        case .array: "array"
        case .string: "string"
        case .number(let value): value.rounded() == value ? "integer" : "number"
        case .bool: "boolean"
        case .null: "null"
        }
    }

    private func typeDescription(_ value: CLIJSONValue) -> String {
        value.stringValue ?? value.arrayValue?.compactMap(\.stringValue).joined(separator: " or ") ?? "a valid type"
    }

    private func integer(_ value: CLIJSONValue?) -> Int? {
        guard let number = value?.numberValue, number.isFinite, number.rounded() == number else { return nil }
        return Int(number)
    }
}

extension CLIJSONValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .object(let value):
            hasher.combine(0)
            for key in value.keys.sorted() {
                hasher.combine(key)
                hasher.combine(value[key])
            }
        case .array(let value):
            hasher.combine(1)
            hasher.combine(value)
        case .string(let value):
            hasher.combine(2)
            hasher.combine(value)
        case .number(let value):
            hasher.combine(3)
            hasher.combine(value)
        case .bool(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .null:
            hasher.combine(5)
        }
    }
}
