import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

class SafetyPolicyTestCase: XCTestCase {
    let shellRun = ToolDefinition(
        name: "host.shell.run",
        description: "Run shell",
        parametersJSON: "{}",
        host: .local,
        risk: .destructive
    )
    let fileWrite = ToolDefinition(
        name: "host.file.write",
        description: "Write file",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitCommit = ToolDefinition(
        name: "host.git.commit",
        description: "Commit staged changes",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPush = ToolDefinition(
        name: "host.git.push",
        description: "Push branch",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitStatus = ToolDefinition(
        name: "host.git.status",
        description: "Get git status",
        parametersJSON: "{}",
        host: .local,
        risk: .read
    )
    let gitPullRequestCreate = ToolDefinition(
        name: "host.git.pr.create",
        description: "Create pull request",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestComment = ToolDefinition(
        name: "host.git.pr.comment",
        description: "Comment on pull request",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestCheckout = ToolDefinition(
        name: "host.git.pr.checkout",
        description: "Checkout pull request",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestReviewers = ToolDefinition(
        name: "host.git.pr.reviewers",
        description: "Request pull request reviewers",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestLabels = ToolDefinition(
        name: "host.git.pr.labels",
        description: "Label pull request",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestReview = ToolDefinition(
        name: "host.git.pr.review",
        description: "Review pull request",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestReviewComment = ToolDefinition(
        name: "host.git.pr.review_comment",
        description: "Inline pull request review comment",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestReviewReply = ToolDefinition(
        name: "host.git.pr.review_reply",
        description: "Reply to inline pull request review comment",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestReviewThreads = ToolDefinition(
        name: "host.git.pr.review_threads",
        description: "List pull request review threads",
        parametersJSON: "{}",
        host: .local,
        risk: .read
    )
    let gitPullRequestReviewThread = ToolDefinition(
        name: "host.git.pr.review_thread",
        description: "Update pull request review thread",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPullRequestMerge = ToolDefinition(
        name: "host.git.pr.merge",
        description: "Merge pull request",
        parametersJSON: "{}",
        host: .local,
        risk: .destructive
    )
    let gitWorktreeCreate = ToolDefinition(
        name: "host.git.worktree.create",
        description: "Create a worktree",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let computerClick = ToolDefinition(
        name: "host.computer.click",
        description: "Click a point on the desktop",
        parametersJSON: "{}",
        host: .computer,
        risk: .destructive
    )
    let memoryRemember = ToolDefinition(
        name: "host.memory.remember",
        description: "Remember a preference",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let mcpCall = ToolDefinition(
        name: "host.mcp.call",
        description: "Call an MCP tool",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let applyPatch = ToolDefinition(
        name: "host.apply_patch",
        description: "Apply a patch",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
}
