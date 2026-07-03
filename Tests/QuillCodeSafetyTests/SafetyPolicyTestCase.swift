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
    let gitFetch = ToolDefinition(
        name: "host.git.fetch",
        description: "Fetch remote refs",
        parametersJSON: "{}",
        host: .local,
        risk: .append
    )
    let gitPull = ToolDefinition(
        name: "host.git.pull",
        description: "Pull latest changes",
        parametersJSON: "{}",
        host: .local,
        risk: .destructive
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

    func review(
        _ tool: ToolDefinition,
        argumentsJSON: String = "{}",
        mode: AgentMode = .auto,
        userMessage: String,
        recentMessages: [ChatMessage]? = nil
    ) async -> SafetyReview {
        await StaticSafetyReviewer().review(.init(
            mode: mode,
            userMessage: userMessage,
            toolCall: ToolCall(name: tool.name, argumentsJSON: argumentsJSON),
            toolDefinition: tool,
            recentMessages: recentMessages ?? [.init(role: .user, content: userMessage)]
        ))
    }

    func assertVerdict(
        _ verdict: ApprovalVerdict,
        tool: ToolDefinition,
        argumentsJSON: String = "{}",
        mode: AgentMode = .auto,
        userMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let review = await review(
            tool,
            argumentsJSON: argumentsJSON,
            mode: mode,
            userMessage: userMessage
        )
        XCTAssertEqual(review.verdict, verdict, review.rationale, file: file, line: line)
    }

    func assertNotVerdict(
        _ verdict: ApprovalVerdict,
        tool: ToolDefinition,
        argumentsJSON: String = "{}",
        userMessage: String,
        because reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let review = await review(tool, argumentsJSON: argumentsJSON, userMessage: userMessage)
        XCTAssertNotEqual(review.verdict, verdict, reason, file: file, line: line)
    }

    func shellArgumentsJSON(_ command: String) -> String {
        struct ShellArguments: Encodable {
            var cmd: String
        }

        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(ShellArguments(cmd: command)),
            let string = String(data: data, encoding: .utf8)
        else {
            XCTFail("Failed to encode shell command arguments.")
            return #"{"cmd":""}"#
        }
        return string
    }
}
