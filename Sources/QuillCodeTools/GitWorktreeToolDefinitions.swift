import QuillCodeCore

public extension ToolDefinition {
    static let gitWorktreeList = gitWorktreeTool(
        name: "host.git.worktree.list",
        description: "List git worktrees for the project.",
        parametersJSON: GitToolParameterSchema.object(),
        risk: .read
    )

    static let gitWorktreeCreate = gitWorktreeTool(
        name: "host.git.worktree.create",
        description: "Create a sibling git worktree for the project, optionally with a new branch and base ref.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "base": .string(),
                "branch": .string(),
                "path": .string()
            ],
            required: ["path"]
        ),
        risk: .append
    )

    static let gitWorktreeOpen = gitWorktreeTool(
        name: "host.git.worktree.open",
        description: "Open a registered sibling git worktree for the project.",
        parametersJSON: GitToolParameterSchema.object(
            properties: ["path": .string()],
            required: ["path"]
        ),
        risk: .read
    )

    static let gitWorktreeRemove = gitWorktreeTool(
        name: "host.git.worktree.remove",
        description: "Remove a registered sibling git worktree for the project.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "force": .boolean(),
                "path": .string()
            ],
            required: ["path"]
        ),
        risk: .destructive
    )

    static let gitWorktreePrune = gitWorktreeTool(
        name: "host.git.worktree.prune",
        description: "Prune stale git worktree administrative records for the project.",
        parametersJSON: GitToolParameterSchema.object(properties: [
            "dryRun": .boolean(description: "Show stale worktree records without removing them."),
            "verbose": .boolean(description: "Print each pruned record.")
        ]),
        risk: .destructive
    )
}

private func gitWorktreeTool(
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
