import Foundation
import QuillCodeCore

struct AgentToolArgumentNormalizationRule: Sendable, Hashable {
    var toolNames: Set<String>
    var stringArguments: [AgentStringArgumentNormalization]
    var valueArguments: [AgentValueArgumentNormalization]

    init(
        toolNames: Set<String>,
        stringArguments: [AgentStringArgumentNormalization] = [],
        valueArguments: [AgentValueArgumentNormalization] = []
    ) {
        self.toolNames = toolNames
        self.stringArguments = stringArguments
        self.valueArguments = valueArguments
    }

    func applies(to toolName: String) -> Bool {
        toolNames.contains(toolName)
    }
}

struct AgentStringArgumentNormalization: Sendable, Hashable {
    var canonicalKey: String
    var aliases: [String]
}

struct AgentValueArgumentNormalization: Sendable, Hashable {
    var canonicalKey: String
    var aliases: [String]
}

enum AgentToolArgumentNormalizationRules {
    static let all: [AgentToolArgumentNormalizationRule] = [
        .init(
            toolNames: [ToolDefinition.shellRun.name],
            stringArguments: [
                .init(
                    canonicalKey: "cmd",
                    aliases: ["command", "shellCommand", "shell_command", "script"]
                )
            ]
        ),
        .init(
            toolNames: [ToolDefinition.fileWrite.name],
            stringArguments: [
                .init(
                    canonicalKey: "path",
                    aliases: ["file", "filename", "fileName", "filepath", "filePath"]
                ),
                .init(canonicalKey: "content", aliases: ["text", "contents", "body"])
            ]
        ),
        .init(
            toolNames: [ToolDefinition.fileRead.name],
            stringArguments: [
                .init(
                    canonicalKey: "path",
                    aliases: ["file", "filename", "fileName", "filepath", "filePath"]
                )
            ]
        ),
        .init(
            toolNames: [ToolDefinition.fileList.name],
            stringArguments: [
                .init(
                    canonicalKey: "path",
                    aliases: ["folder", "directory", "dir", "root", "scope"]
                )
            ],
            valueArguments: [
                .init(canonicalKey: "includeHidden", aliases: ["hidden", "showHidden", "show_hidden", "all"]),
                .init(canonicalKey: "maxEntries", aliases: ["limit", "max", "count", "max_entries"])
            ]
        ),
        .init(
            toolNames: [ToolDefinition.fileSearch.name],
            stringArguments: [
                .init(
                    canonicalKey: "query",
                    aliases: ["term", "text", "pattern", "needle", "search", "searchTerm", "search_term"]
                ),
                .init(
                    canonicalKey: "path",
                    aliases: ["folder", "directory", "dir", "root", "scope"]
                )
            ],
            valueArguments: [
                .init(canonicalKey: "maxResults", aliases: ["limit", "max", "count", "max_results"])
            ]
        ),
        .init(
            toolNames: [ToolDefinition.applyPatch.name],
            stringArguments: [.init(canonicalKey: "patch", aliases: ["diff"])]
        ),
        .init(
            toolNames: [ToolDefinition.memoryRemember.name],
            stringArguments: [.init(canonicalKey: "content", aliases: ["memory", "note", "text"])]
        ),
        .init(
            toolNames: [ToolDefinition.browserOpen.name],
            stringArguments: [.init(canonicalKey: "url", aliases: ["address", "href", "target", "page"])]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestCreate.name],
            stringArguments: [.init(canonicalKey: "title", aliases: ["name", "subject"])]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestList.name],
            stringArguments: [.init(canonicalKey: "state", aliases: ["status"])],
            valueArguments: [.init(canonicalKey: "limit", aliases: ["count", "max", "first"])]
        ),
        .init(
            toolNames: pullRequestToolNames,
            stringArguments: [
                .init(
                    canonicalKey: "selector",
                    aliases: ["number", "pr", "pullRequest", "pull_request", "url", "branch"]
                )
            ]
        ),
        .init(
            toolNames: [
                ToolDefinition.gitPullRequestComment.name,
                ToolDefinition.gitPullRequestReview.name,
                ToolDefinition.gitPullRequestReviewComment.name,
                ToolDefinition.gitPullRequestReviewReply.name
            ],
            stringArguments: [.init(canonicalKey: "body", aliases: ["comment", "message", "text", "content"])]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestReviewReply.name],
            valueArguments: [
                .init(
                    canonicalKey: "commentId",
                    aliases: ["comment_id", "commentID", "reviewCommentId", "review_comment_id", "replyTo", "reply_to"]
                )
            ]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestReviewThread.name],
            stringArguments: [
                .init(
                    canonicalKey: "threadId",
                    aliases: ["thread_id", "threadID", "reviewThreadId", "review_thread_id"]
                ),
                .init(canonicalKey: "action", aliases: ["state", "operation"])
            ]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestReviewers.name],
            valueArguments: [
                .init(
                    canonicalKey: "add",
                    aliases: [
                        "reviewers",
                        "reviewer",
                        "addReviewers",
                        "add_reviewers",
                        "requestReviewers",
                        "request_reviewers"
                    ]
                ),
                .init(
                    canonicalKey: "remove",
                    aliases: ["removeReviewers", "remove_reviewers", "unrequestReviewers", "unrequest_reviewers"]
                )
            ]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestLabels.name],
            valueArguments: [
                .init(
                    canonicalKey: "add",
                    aliases: ["labels", "label", "addLabels", "add_labels", "applyLabels", "apply_labels"]
                ),
                .init(
                    canonicalKey: "remove",
                    aliases: ["removeLabels", "remove_labels", "deleteLabels", "delete_labels"]
                )
            ]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestReview.name],
            stringArguments: [.init(canonicalKey: "action", aliases: ["review", "verdict", "decision"])]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestLifecycle.name],
            stringArguments: [.init(canonicalKey: "action", aliases: ["state", "operation", "lifecycle"])]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestMerge.name],
            stringArguments: [.init(canonicalKey: "method", aliases: ["strategy", "mergeMethod", "merge_method"])]
        ),
        .init(
            toolNames: [ToolDefinition.gitPullRequestCheckout.name],
            stringArguments: [.init(canonicalKey: "branch", aliases: ["localBranch", "local_branch", "checkoutBranch", "checkout_branch"])]
        ),
        .init(
            toolNames: [ToolDefinition.gitWorktreeCreate.name],
            stringArguments: [.init(canonicalKey: "path", aliases: ["folder", "directory"])]
        )
    ]

    static func matching(_ toolName: String) -> [AgentToolArgumentNormalizationRule] {
        all.filter { $0.applies(to: toolName) }
    }

    private static let pullRequestToolNames: Set<String> = [
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestLifecycle.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name,
        ToolDefinition.gitPullRequestReviewThreads.name,
        ToolDefinition.gitPullRequestMerge.name
    ]
}
