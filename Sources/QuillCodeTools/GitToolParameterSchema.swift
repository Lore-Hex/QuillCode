enum GitToolParameterSchema {
    static func object(
        properties: [String: GitToolParameterProperty] = [:],
        required: [String] = []
    ) -> String {
        ToolParameterSchema.object(properties: properties, required: required)
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

typealias GitToolParameterProperty = ToolParameterProperty
