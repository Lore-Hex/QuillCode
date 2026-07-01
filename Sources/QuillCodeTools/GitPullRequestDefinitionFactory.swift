import QuillCodeCore

enum GitPullRequestDefinitionFactory {
    static func tool(
        name: String,
        description: String,
        parametersJSON: String,
        risk: ToolRiskClass
    ) -> ToolDefinition {
        GitToolDefinitionFactory.definition(
            name: name,
            description: description,
            parametersJSON: parametersJSON,
            risk: risk
        )
    }

    static func described(_ summary: String) -> String {
        GitToolDefinitionFactory.pullRequestDescription(summary)
    }

    static func selectorParameters(
        extra: [String: GitToolParameterProperty] = [:],
        required: [String] = []
    ) -> String {
        GitToolParameterSchema.object(
            properties: GitToolParameterSchema.selectorProperties(extra),
            required: required
        )
    }
}
