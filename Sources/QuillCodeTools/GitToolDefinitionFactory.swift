import QuillCodeCore

enum GitToolDefinitionFactory {
    static func definition(
        name: String,
        description: String,
        parametersJSON: String,
        risk: ToolRiskClass
    ) -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            parametersJSON: parametersJSON,
            host: .local,
            risk: risk
        )
    }

    static func pullRequestDescription(_ summary: String) -> String {
        summary + " Optional selector may be a PR number, URL, or branch."
    }
}
