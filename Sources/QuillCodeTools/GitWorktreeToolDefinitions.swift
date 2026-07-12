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
        description: "Create a sibling git worktree, optionally as a detached managed task with safe local-change transfer.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "base": .string(),
                "branch": .string(),
                "managed": .boolean(
                    description: "Create a detached task worktree and transfer bounded staged, unstaged, and allowed local files."
                ),
                "path": .string()
            ],
            required: ["path"]
        ),
        risk: .append
    )

    static let gitWorktreeCreateBranch = gitWorktreeTool(
        name: "host.git.worktree.branch.create",
        description: "Create a new branch in the current detached managed worktree and keep working there.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "branch": .string(description: "New branch name for the current detached worktree.")
            ],
            required: ["branch"]
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

    static let gitWorktreeHandoff = gitWorktreeTool(
        name: "host.git.worktree.handoff",
        description: "Move uncommitted task changes between a local checkout and its managed worktree.",
        parametersJSON: GitToolParameterSchema.object(
            properties: ["destination": .string()],
            required: ["destination"]
        ),
        risk: .destructive
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
