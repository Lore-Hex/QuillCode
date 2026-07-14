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
        description: "Show unstaged changes, staged changes, one exact commit, or changes since a base branch. Select at most one comparison.",
        parametersJSON: GitToolParameterSchema.object(properties: [
            "staged": .boolean(description: "Show staged changes."),
            "commit": .string(description: "Show the patch introduced by this exact commit or SHA."),
            "baseBranch": .string(description: "Show changes from this branch's merge base through HEAD.")
        ]),
        risk: .read
    )

    static let gitFetch = gitTool(
        name: "host.git.fetch",
        description: "Fetch updates from a named git remote without changing the working tree.",
        parametersJSON: GitToolParameterSchema.object(properties: [
            "remote": .string(description: "Remote to fetch from. Defaults to origin."),
            "prune": .boolean(description: "Prune deleted remote-tracking branches.")
        ]),
        risk: .append
    )

    static let gitPull = gitTool(
        name: "host.git.pull",
        description: "Pull latest git changes for the project, using fast-forward only by default.",
        parametersJSON: GitToolParameterSchema.object(properties: [
            "remote": .string(description: "Remote to pull from. Omit to use the configured upstream."),
            "branch": .string(description: "Branch to pull. If set without remote, origin is used."),
            "ffOnly": .boolean(description: "Use --ff-only. Defaults to true.")
        ]),
        risk: .destructive
    )

    static let gitBranchList = gitTool(
        name: "host.git.branch.list",
        description: "List local branches and, by default, remote-tracking branches for the project.",
        parametersJSON: GitToolParameterSchema.object(properties: [
            "includeRemote": .boolean(description: "Include remote-tracking branches. Defaults to true.")
        ]),
        risk: .read
    )

    static let gitBranchSwitch = gitTool(
        name: "host.git.branch.switch",
        description: "Switch to an existing git branch, or create and switch to a new branch from an optional start point.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "branch": .string(description: "Branch name to switch to or create."),
                "create": .boolean(description: "Create the branch before switching. Defaults to false."),
                "startPoint": .string(description: "Optional start point used only when create is true.")
            ],
            required: ["branch"]
        ),
        risk: .destructive
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

    static let gitUnstageHunk = gitTool(
        name: "host.git.unstage_hunk",
        description: "Unstage one selected git diff hunk while preserving the working-tree change.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "path": .string(),
                "patch": .string()
            ],
            required: ["path", "patch"]
        ),
        risk: .destructive
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
