import QuillCodeCore

public extension ToolDefinition {
    static let gitStatus = gitTool(
        name: "host.git.status",
        description: "Show git status for the project.",
        parametersJSON: GitToolParameterSchema.object(),
        risk: .read
    )

    static let gitDiff = gitTool(
        name: "host.git.diff",
        description: "Show git diff for the project.",
        parametersJSON: GitToolParameterSchema.object(properties: [
            "staged": .boolean()
        ]),
        risk: .read
    )

    static let gitStage = gitTool(
        name: "host.git.stage",
        description: "Stage one file path inside the project.",
        parametersJSON: GitToolParameterSchema.object(
            properties: ["path": .string()],
            required: ["path"]
        ),
        risk: .append
    )

    static let gitRestore = gitTool(
        name: "host.git.restore",
        description: "Restore one file path inside the project from git.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "path": .string(),
                "staged": .boolean()
            ],
            required: ["path"]
        ),
        risk: .destructive
    )

    static let gitStageHunk = gitTool(
        name: "host.git.stage_hunk",
        description: "Stage one selected git diff hunk inside the project.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "path": .string(),
                "patch": .string()
            ],
            required: ["path", "patch"]
        ),
        risk: .append
    )

    static let gitRestoreHunk = gitTool(
        name: "host.git.restore_hunk",
        description: "Restore one selected git diff hunk inside the project.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "path": .string(),
                "patch": .string()
            ],
            required: ["path", "patch"]
        ),
        risk: .destructive
    )

    static let gitCommit = gitTool(
        name: "host.git.commit",
        description: "Create a git commit from already staged project changes.",
        parametersJSON: GitToolParameterSchema.object(
            properties: ["message": .string()],
            required: ["message"]
        ),
        risk: .append
    )

    static let gitPush = gitTool(
        name: "host.git.push",
        description: "Push a project branch to a named git remote.",
        parametersJSON: GitToolParameterSchema.object(properties: [
            "branch": .string(description: "Branch to push. Defaults to the current branch."),
            "remote": .string(description: "Remote to push to. Defaults to origin."),
            "setUpstream": .boolean(description: "Set upstream tracking for the pushed branch.")
        ]),
        risk: .append
    )
}

private func gitTool(
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
