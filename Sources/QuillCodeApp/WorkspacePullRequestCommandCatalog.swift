import QuillCodeCore

struct WorkspacePullRequestCommandDescriptor: Equatable {
    let id: String
    let title: String
    let keywords: [String]
    let systemImage: String
    let toolName: String?
    let draft: String?

    init(
        id: String,
        title: String,
        keywords: [String],
        systemImage: String,
        toolName: String? = nil,
        draft: String? = nil
    ) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.systemImage = systemImage
        self.toolName = toolName
        self.draft = draft
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
            draft: "Create a pull request titled "
        ),
        .init(
            id: "git-pr-view",
            title: "View pull request",
            keywords: ["github", "pr", "view", "comments", "review"],
            systemImage: "doc.text.magnifyingglass",
            toolName: ToolDefinition.gitPullRequestView.name
        ),
        .init(
            id: "git-pr-checks",
            title: "Pull request checks",
            keywords: ["github", "pr", "checks", "ci", "status"],
            systemImage: "checklist",
            toolName: ToolDefinition.gitPullRequestChecks.name
        ),
        .init(
            id: "git-pr-diff",
            title: "Pull request diff",
            keywords: ["github", "pr", "pr diff", "pull request diff", "diff", "review", "changes"],
            systemImage: "doc.text.magnifyingglass",
            toolName: ToolDefinition.gitPullRequestDiff.name
        ),
        .init(
            id: "git-pr-checkout",
            title: "Checkout pull request",
            keywords: ["github", "pr", "checkout", "switch", "branch"],
            systemImage: "arrow.down.doc",
            draft: "Checkout pull request "
        ),
        .init(
            id: "git-pr-reviewers",
            title: "Request pull request reviewers",
            keywords: ["github", "pr", "reviewer", "reviewers", "request review"],
            systemImage: "person.2.badge.gearshape",
            draft: "Request reviewers for the current pull request: "
        ),
        .init(
            id: "git-pr-comment",
            title: "Comment on pull request",
            keywords: ["github", "pr", "comment", "comment pull", "reply", "discussion"],
            systemImage: "bubble.left.and.text.bubble.right",
            draft: "Comment on the current pull request: "
        ),
        .init(
            id: "git-pr-review",
            title: "Review pull request",
            keywords: ["github", "pr", "review", "approve", "approve pr", "request changes"],
            systemImage: "checkmark.seal",
            draft: "Review the current pull request: approve"
        ),
        .init(
            id: "git-pr-review-comment",
            title: "Comment on pull request line",
            keywords: ["github", "pr", "review", "inline", "line comment", "review comment"],
            systemImage: "text.bubble",
            draft: "Comment on a pull request line: "
        ),
        .init(
            id: "git-pr-review-reply",
            title: "Reply to pull request line comment",
            keywords: ["github", "pr", "review", "reply", "inline reply", "review comment reply"],
            systemImage: "arrowshape.turn.up.left",
            draft: "Reply to pull request review comment: "
        ),
        .init(
            id: "git-pr-review-threads",
            title: "List pull request review threads",
            keywords: ["github", "pr", "review", "thread", "threads", "unresolved", "ids", "browse"],
            systemImage: "list.bullet.rectangle",
            toolName: ToolDefinition.gitPullRequestReviewThreads.name
        ),
        .init(
            id: "git-pr-review-thread",
            title: "Resolve pull request review thread",
            keywords: ["github", "pr", "review", "thread", "resolve", "unresolve"],
            systemImage: "checkmark.bubble",
            draft: "Resolve pull request review thread: "
        ),
        .init(
            id: "git-pr-labels",
            title: "Label pull request",
            keywords: ["github", "pr", "label", "labels", "triage"],
            systemImage: "tag",
            draft: "Label the current pull request: "
        ),
        .init(
            id: "git-pr-merge",
            title: "Merge pull request",
            keywords: ["github", "pr", "merge", "automerge", "merge train"],
            systemImage: "arrow.triangle.merge",
            draft: "Merge the current pull request with squash"
        )
    ]

    static let toolNameByCommandID = dictionary(\.toolName)
    static let draftByCommandID = dictionary(\.draft)
    static let systemImageByCommandID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0.systemImage) })

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
