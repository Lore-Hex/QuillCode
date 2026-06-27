import QuillCodeCore

private func pullRequestSlash(
    usage: String,
    title: String,
    detail: String,
    insertText: String,
    aliases: [String]
) -> SlashCommandDefinition {
    SlashCommandDefinition(
        usage: usage,
        title: title,
        detail: detail,
        insertText: insertText,
        aliases: aliases
    )
}

struct WorkspacePullRequestCommandDescriptor: Equatable {
    let id: String
    let title: String
    let keywords: [String]
    let systemImage: String
    let toolName: String?
    let draft: String?
    let slash: SlashCommandDefinition?

    init(
        id: String,
        title: String,
        keywords: [String],
        systemImage: String,
        toolName: String? = nil,
        draft: String? = nil,
        slash: SlashCommandDefinition? = nil
    ) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.systemImage = systemImage
        self.toolName = toolName
        self.draft = draft
        self.slash = slash
    }

    func command(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: id,
            title: title,
            category: WorkspaceCommandPalette.gitCategory,
            keywords: keywords,
            isEnabled: isEnabled
        )
    }
}

enum WorkspacePullRequestCommandCatalog {
    static let descriptors: [WorkspacePullRequestCommandDescriptor] = [
        .init(
            id: "git-pr-create",
            title: "Create pull request",
            keywords: ["github", "pr", "pull request", "review"],
            systemImage: "arrow.up.doc",
            draft: "Create a pull request titled ",
            slash: pullRequestSlash(
                usage: "/pr create",
                title: "Create pull request",
                detail: "Draft a pull request request in the composer.",
                insertText: "/pr create",
                aliases: ["pull-request", "pullrequest"]
            )
        ),
        .init(
            id: "git-pr-view",
            title: "View pull request",
            keywords: ["github", "pr", "view", "comments", "review"],
            systemImage: "doc.text.magnifyingglass",
            toolName: ToolDefinition.gitPullRequestView.name,
            slash: pullRequestSlash(
                usage: "/pr view [selector]",
                title: "View pull request",
                detail: "View the current or selected pull request with comments.",
                insertText: "/pr view ",
                aliases: ["pr show", "pull request view"]
            )
        ),
        .init(
            id: "git-pr-checks",
            title: "Pull request checks",
            keywords: ["github", "pr", "checks", "ci", "status"],
            systemImage: "checklist",
            toolName: ToolDefinition.gitPullRequestChecks.name,
            slash: pullRequestSlash(
                usage: "/pr checks [selector]",
                title: "Pull request checks",
                detail: "Show CI status for the current or selected pull request.",
                insertText: "/pr checks ",
                aliases: ["pr ci", "pull request status"]
            )
        ),
        .init(
            id: "git-pr-diff",
            title: "Pull request diff",
            keywords: ["github", "pr", "pr diff", "pull request diff", "diff", "review", "changes"],
            systemImage: "doc.text.magnifyingglass",
            toolName: ToolDefinition.gitPullRequestDiff.name,
            slash: pullRequestSlash(
                usage: "/pr diff [selector]",
                title: "Pull request diff",
                detail: "Show the unified diff for the current or selected pull request.",
                insertText: "/pr diff ",
                aliases: ["pr changes", "pull request diff"]
            )
        ),
        .init(
            id: "git-pr-checkout",
            title: "Checkout pull request",
            keywords: ["github", "pr", "checkout", "switch", "branch"],
            systemImage: "arrow.down.doc",
            draft: "Checkout pull request ",
            slash: pullRequestSlash(
                usage: "/pr checkout selector",
                title: "Checkout pull request",
                detail: "Check out a pull request branch.",
                insertText: "/pr checkout ",
                aliases: ["pr switch"]
            )
        ),
        .init(
            id: "git-pr-reviewers",
            title: "Request pull request reviewers",
            keywords: ["github", "pr", "reviewer", "reviewers", "request review"],
            systemImage: "person.2.badge.gearshape",
            draft: "Request reviewers for the current pull request: ",
            slash: pullRequestSlash(
                usage: "/pr reviewers add|remove login",
                title: "Manage pull request reviewers",
                detail: "Request or remove pull request reviewers.",
                insertText: "/pr reviewers add ",
                aliases: ["request reviewer", "remove reviewer"]
            )
        ),
        .init(
            id: "git-pr-comment",
            title: "Comment on pull request",
            keywords: ["github", "pr", "comment", "comment pull", "reply", "discussion"],
            systemImage: "bubble.left.and.text.bubble.right",
            draft: "Comment on the current pull request: ",
            slash: pullRequestSlash(
                usage: "/pr comment body",
                title: "Comment on pull request",
                detail: "Post a top-level comment on the current pull request.",
                insertText: "/pr comment ",
                aliases: ["pr reply"]
            )
        ),
        .init(
            id: "git-pr-review",
            title: "Review pull request",
            keywords: ["github", "pr", "review", "approve", "approve pr", "request changes"],
            systemImage: "checkmark.seal",
            draft: "Review the current pull request: approve",
            slash: pullRequestSlash(
                usage: "/pr review approve|comment|request_changes",
                title: "Review pull request",
                detail: "Submit an approve, comment, or request_changes review.",
                insertText: "/pr review approve",
                aliases: ["pr approve", "request changes"]
            )
        ),
        .init(
            id: "git-pr-review-comment",
            title: "Comment on pull request line",
            keywords: ["github", "pr", "review", "inline", "line comment", "review comment"],
            systemImage: "text.bubble",
            draft: "Comment on a pull request line: ",
            slash: pullRequestSlash(
                usage: "/pr review-comment path line body",
                title: "Inline pull request comment",
                detail: "Post an inline review comment on a pull request diff line.",
                insertText: "/pr review-comment ",
                aliases: ["pr inline", "line comment", "review comment"]
            )
        ),
        .init(
            id: "git-pr-review-reply",
            title: "Reply to pull request line comment",
            keywords: ["github", "pr", "review", "reply", "inline reply", "review comment reply"],
            systemImage: "arrowshape.turn.up.left",
            draft: "Reply to pull request review comment: ",
            slash: pullRequestSlash(
                usage: "/pr review-reply commentId body",
                title: "Reply to inline review comment",
                detail: "Reply to an existing pull request line comment.",
                insertText: "/pr review-reply ",
                aliases: ["inline reply", "review reply"]
            )
        ),
        .init(
            id: "git-pr-review-threads",
            title: "List pull request review threads",
            keywords: ["github", "pr", "review", "thread", "threads", "unresolved", "ids", "browse"],
            systemImage: "list.bullet.rectangle",
            toolName: ToolDefinition.gitPullRequestReviewThreads.name,
            slash: pullRequestSlash(
                usage: "/pr review-threads [selector]",
                title: "List review threads",
                detail: "List review-thread IDs and first comment IDs for reply or resolve actions.",
                insertText: "/pr review-threads ",
                aliases: ["pr threads", "review thread ids"]
            )
        ),
        .init(
            id: "git-pr-review-thread",
            title: "Resolve pull request review thread",
            keywords: ["github", "pr", "review", "thread", "resolve", "unresolve"],
            systemImage: "checkmark.bubble",
            draft: "Resolve pull request review thread: ",
            slash: pullRequestSlash(
                usage: "/pr review-thread resolve|unresolve threadId",
                title: "Resolve review thread",
                detail: "Resolve or unresolve a pull request review thread.",
                insertText: "/pr review-thread resolve ",
                aliases: ["resolve thread", "unresolve thread"]
            )
        ),
        .init(
            id: "git-pr-labels",
            title: "Label pull request",
            keywords: ["github", "pr", "label", "labels", "triage"],
            systemImage: "tag",
            draft: "Label the current pull request: ",
            slash: pullRequestSlash(
                usage: "/pr labels add|remove label",
                title: "Manage pull request labels",
                detail: "Add or remove pull request labels. Use commas for labels with spaces.",
                insertText: "/pr labels add ",
                aliases: ["pr label", "triage label"]
            )
        ),
        .init(
            id: "git-pr-merge",
            title: "Merge pull request",
            keywords: ["github", "pr", "merge", "automerge", "merge train"],
            systemImage: "arrow.triangle.merge",
            draft: "Merge the current pull request with squash",
            slash: pullRequestSlash(
                usage: "/pr merge [squash|merge|rebase]",
                title: "Merge pull request",
                detail: "Merge or enable auto-merge for the current pull request.",
                insertText: "/pr merge squash",
                aliases: ["automerge", "merge train"]
            )
        )
    ]

    static let toolNameByCommandID = dictionary(\.toolName)
    static let draftByCommandID = dictionary(\.draft)
    static let systemImageByCommandID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0.systemImage) })
    static let slashDefinitions = descriptors.compactMap(\.slash)

    static func commands(isEnabled: Bool) -> [WorkspaceCommandSurface] {
        descriptors.map { $0.command(isEnabled: isEnabled) }
    }

    static func systemImage(for commandID: String) -> String? {
        systemImageByCommandID[commandID]
    }

    private static func dictionary(_ value: KeyPath<WorkspacePullRequestCommandDescriptor, String?>) -> [String: String] {
        Dictionary(uniqueKeysWithValues: descriptors.compactMap { descriptor in
            descriptor[keyPath: value].map { (descriptor.id, $0) }
        })
    }
}
