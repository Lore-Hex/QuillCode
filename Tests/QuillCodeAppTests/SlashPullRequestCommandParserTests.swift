import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class SlashPullRequestCommandParserTests: XCTestCase {
    func testEmptyPullRequestCommandPrefillsCreateDraft() {
        XCTAssertEqual(SlashPullRequestCommandParser.parse(""), .workspaceCommand("git-pr-create"))
        XCTAssertEqual(SlashCommandParser.parse("/pr"), .workspaceCommand("git-pr-create"))
    }

    func testFillPullRequestCommandRoutesToAutoFillCreate() {
        XCTAssertEqual(SlashPullRequestCommandParser.parse("fill"), .workspaceCommand("git-pr-fill"))
        XCTAssertEqual(SlashPullRequestCommandParser.parse("autofill"), .workspaceCommand("git-pr-fill"))
        XCTAssertEqual(SlashPullRequestCommandParser.parse("create --fill"), .workspaceCommand("git-pr-fill"))
        XCTAssertEqual(SlashPullRequestCommandParser.parse("create fill"), .workspaceCommand("git-pr-fill"))
        XCTAssertEqual(SlashCommandParser.parse("/pr fill"), .workspaceCommand("git-pr-fill"))
    }

    func testReadOnlyPullRequestCommandsBuildToolCallsWithSelectors() throws {
        try assertToolCall(
            SlashPullRequestCommandParser.parse("list all 25"),
            name: ToolDefinition.gitPullRequestList.name,
            arguments: ["state": "all", "limit": 25]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("ls --state merged --limit 10"),
            name: ToolDefinition.gitPullRequestList.name,
            arguments: ["state": "merged", "limit": 10]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("view #456"),
            name: ToolDefinition.gitPullRequestView.name,
            arguments: ["selector": "#456"]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("checks https://github.com/Lore-Hex/QuillCode/pull/239"),
            name: ToolDefinition.gitPullRequestChecks.name,
            arguments: ["selector": "https://github.com/Lore-Hex/QuillCode/pull/239"]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("diff Lore-Hex/QuillCode#239"),
            name: ToolDefinition.gitPullRequestDiff.name,
            arguments: ["selector": "Lore-Hex/QuillCode#239"]
        )
    }

    func testCommentAndReviewCommandsSplitSelectorFromBody() throws {
        try assertToolCall(
            SlashPullRequestCommandParser.parse("comment 456 ship the settings split"),
            name: ToolDefinition.gitPullRequestComment.name,
            arguments: ["selector": "456", "body": "ship the settings split"]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("review request-changes 456 tighten tests"),
            name: ToolDefinition.gitPullRequestReview.name,
            arguments: ["selector": "456", "action": "request_changes", "body": "tighten tests"]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("approve 456"),
            name: ToolDefinition.gitPullRequestReview.name,
            arguments: ["selector": "456", "action": "approve"]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("review-comment 456 Sources/App.swift 42 Please cover this branch"),
            name: ToolDefinition.gitPullRequestReviewComment.name,
            arguments: [
                "selector": "456",
                "path": "Sources/App.swift",
                "line": 42,
                "body": "Please cover this branch"
            ]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("review-comment Sources/App.swift 42 Please cover this branch"),
            name: ToolDefinition.gitPullRequestReviewComment.name,
            arguments: [
                "path": "Sources/App.swift",
                "line": 42,
                "body": "Please cover this branch"
            ]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("review-reply 456 99 Updated this, thanks"),
            name: ToolDefinition.gitPullRequestReviewReply.name,
            arguments: [
                "selector": "456",
                "commentId": 99,
                "body": "Updated this, thanks"
            ]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("review-reply 99 Updated this, thanks"),
            name: ToolDefinition.gitPullRequestReviewReply.name,
            arguments: [
                "commentId": 99,
                "body": "Updated this, thanks"
            ]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("review-threads 456"),
            name: ToolDefinition.gitPullRequestReviewThreads.name,
            arguments: ["selector": "456"]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("threads"),
            name: ToolDefinition.gitPullRequestReviewThreads.name,
            arguments: [:]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("resolve-thread PRRT_kwDOExample"),
            name: ToolDefinition.gitPullRequestReviewThread.name,
            arguments: ["threadId": "PRRT_kwDOExample", "action": "resolve"]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("review-thread unresolve PRRT_kwDOExample"),
            name: ToolDefinition.gitPullRequestReviewThread.name,
            arguments: ["threadId": "PRRT_kwDOExample", "action": "unresolve"]
        )
    }

    func testReviewerLabelAndMergeCommandsBuildStructuredArguments() throws {
        try assertToolCall(
            SlashPullRequestCommandParser.parse("reviewers add alice bob"),
            name: ToolDefinition.gitPullRequestReviewers.name,
            arguments: ["add": ["alice", "bob"]]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("labels add 456 merge-train, needs review"),
            name: ToolDefinition.gitPullRequestLabels.name,
            arguments: ["selector": "456", "add": ["merge-train", "needs review"]]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("merge 456 rebase auto delete-branch"),
            name: ToolDefinition.gitPullRequestMerge.name,
            arguments: ["selector": "456", "method": "rebase", "auto": true, "deleteBranch": true]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("close 456"),
            name: ToolDefinition.gitPullRequestLifecycle.name,
            arguments: ["selector": "456", "action": "close"]
        )
        try assertToolCall(
            SlashPullRequestCommandParser.parse("reopen"),
            name: ToolDefinition.gitPullRequestLifecycle.name,
            arguments: ["action": "reopen"]
        )
    }

    func testInvalidPullRequestSubcommandsReturnUsageMessages() {
        XCTAssertEqual(
            SlashPullRequestCommandParser.parse("comment"),
            .invalid("Usage: /pr comment OptionalPRSelector comment text")
        )
        XCTAssertEqual(
            SlashPullRequestCommandParser.parse("review squash"),
            .invalid("Unknown pull request review action 'squash'. Use approve, comment, or request_changes.")
        )
        XCTAssertEqual(
            SlashPullRequestCommandParser.parse("list draft"),
            .invalid("Usage: /pr list [open|closed|merged|all] [limit]")
        )
        XCTAssertEqual(
            SlashPullRequestCommandParser.parse("list open 10 --limit 20"),
            .invalid("Usage: /pr list [open|closed|merged|all] [limit]")
        )
        XCTAssertEqual(
            SlashPullRequestCommandParser.parse("unknown"),
            .invalid("Unknown pull request command 'unknown'. Use create, fill, list, view, checks, diff, checkout, comment, review, review-comment, review-reply, review-threads, review-thread, reviewers, labels, close, reopen, or merge.")
        )
    }

    private func assertToolCall(
        _ command: SlashCommand,
        name: String,
        arguments expectedArguments: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case .toolCall(let call) = command else {
            return XCTFail("Expected tool call, got \(command)", file: file, line: line)
        }
        XCTAssertEqual(call.name, name, file: file, line: line)
        let arguments = try decodedArguments(call)
        XCTAssertTrue(
            NSDictionary(dictionary: arguments).isEqual(to: expectedArguments),
            "Expected \(expectedArguments), got \(arguments)",
            file: file,
            line: line
        )
    }

    private func decodedArguments(_ call: ToolCall) throws -> [String: Any] {
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
