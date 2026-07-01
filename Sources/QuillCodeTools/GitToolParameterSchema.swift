import Foundation

enum GitToolParameterSchema {
    static func object(
        properties: [String: GitToolParameterProperty] = [:],
        required: [String] = []
    ) -> String {
        let schema = ObjectSchema(properties: properties, required: required)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(schema),
            let json = String(data: data, encoding: .utf8)
        else {
            return #"{"properties":{},"type":"object"}"#
        }
        return json
    }

    static func selectorProperties(
        _ extra: [String: GitToolParameterProperty] = [:]
    ) -> [String: GitToolParameterProperty] {
        var properties = ["selector": selector]
        for (name, property) in extra {
            properties[name] = property
        }
        return properties
    }

    static let selector = GitToolParameterProperty.string(
        description: "Optional pull request number, URL, or branch. Omit to use the current branch."
    )
}

struct GitToolParameterProperty: Encodable {
    var type: String
    var description: String?
    var allowedValues: [String]?
    var arrayItemType: String?

    static func string(description: String? = nil) -> Self {
        Self(type: "string", description: description)
    }

    static func integer(description: String? = nil) -> Self {
        Self(type: "integer", description: description)
    }

    static func boolean(description: String? = nil) -> Self {
        Self(type: "boolean", description: description)
    }

    static func stringEnum(_ values: [String], description: String? = nil) -> Self {
        Self(type: "string", description: description, allowedValues: values)
    }

    static func stringArray(description: String? = nil) -> Self {
        Self(type: "array", description: description, arrayItemType: "string")
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case allowedValues = "enum"
        case items
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(allowedValues, forKey: .allowedValues)
        if let arrayItemType {
            try container.encode(ArrayItem(type: arrayItemType), forKey: .items)
        }
    }
}

private struct ObjectSchema: Encodable {
    var type = "object"
    var properties: [String: GitToolParameterProperty]
    var required: [String]?

    init(properties: [String: GitToolParameterProperty], required: [String]) {
        self.properties = properties
        self.required = required.isEmpty ? nil : required
    }
}

private struct ArrayItem: Encodable {
    var type: String
}
