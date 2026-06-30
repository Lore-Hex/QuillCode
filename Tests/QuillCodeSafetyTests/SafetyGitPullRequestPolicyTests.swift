import XCTest
import QuillCodeCore
@testable import QuillCodeSafety

final class SafetyGitPullRequestPolicyTests: SafetyPolicyTestCase {
    func testAutoApprovesUserRequestedGitCommit() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: gitCommit.name, argumentsJSON: #"{"message":"Add hello file"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "commit these changes with message Add hello file",
            toolCall: call,
            toolDefinition: gitCommit,
            recentMessages: [.init(role: .user, content: "commit these changes with message Add hello file")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesRememberEvenWhenMemoryMentionsCommandVerbs() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: memoryRemember.name,
            argumentsJSON: #"{"content":"make small reviewable commits"}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "remember to make small reviewable commits",
            toolCall: call,
            toolDefinition: memoryRemember,
            recentMessages: [.init(role: .user, content: "remember to make small reviewable commits")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoClarifiesNegatedRememberIntent() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: memoryRemember.name,
            argumentsJSON: #"{"content":"make small reviewable commits"}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "don't remember this",
            toolCall: call,
            toolDefinition: memoryRemember,
            recentMessages: [.init(role: .user, content: "don't remember this")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.clarify)
    }

    func testAutoApprovesUserRequestedGitPush() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: gitPush.name, argumentsJSON: #"{"remote":"origin"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "push this branch",
            toolCall: call,
            toolDefinition: gitPush,
            recentMessages: [.init(role: .user, content: "push this branch")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoClarifiesNegatedGitPushIntent() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: gitPush.name, argumentsJSON: #"{"remote":"origin"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "do not push this branch",
            toolCall: call,
            toolDefinition: gitPush,
            recentMessages: [.init(role: .user, content: "do not push this branch")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.clarify)
    }

    func testAutoApprovesUserRequestedPullRequest() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: gitPullRequestCreate.name, argumentsJSON: #"{"title":"Add PR tool"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "create a pull request titled Add PR tool",
            toolCall: call,
            toolDefinition: gitPullRequestCreate,
            recentMessages: [.init(role: .user, content: "create a pull request titled Add PR tool")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoDoesNotAutoApprovePushForBarePullRequestMention() async {
        let reviewer = StaticSafetyReviewer()
        // "summarize the pull request" is a read-ish request — it must NOT auto-approve an
        // outward-facing git.push via the PR policy's default fallback.
        let call = ToolCall(name: gitPush.name, argumentsJSON: #"{}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "summarize the pull request for me",
            toolCall: call,
            toolDefinition: gitPush,
            recentMessages: [.init(role: .user, content: "summarize the pull request for me")]
        ))
        XCTAssertNotEqual(review.verdict, ApprovalVerdict.approve, "a bare PR mention must not auto-approve git.push")
    }

    func testAutoApprovesPushForExplicitOpenPullRequest() async {
        let reviewer = StaticSafetyReviewer()
        // An explicit open/push intent still auto-approves git.push (the create rule).
        let call = ToolCall(name: gitPush.name, argumentsJSON: #"{}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "open a pull request and push the branch",
            toolCall: call,
            toolDefinition: gitPush,
            recentMessages: [.init(role: .user, content: "open a pull request and push the branch")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve, review.rationale)
    }

    func testAutoDoesNotAutoApproveCreateForCommentOnPullRequest() async {
        let reviewer = StaticSafetyReviewer()
        // "create a comment on the pr" is a COMMENT intent — the co-occurring word "create" must not
        // auto-approve opening a brand-new PR. The comment rule takes priority over the create intent.
        let call = ToolCall(name: gitPullRequestCreate.name, argumentsJSON: #"{"title":"x"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "create a comment on the pull request",
            toolCall: call,
            toolDefinition: gitPullRequestCreate,
            recentMessages: [.init(role: .user, content: "create a comment on the pull request")]
        ))
        XCTAssertNotEqual(review.verdict, ApprovalVerdict.approve, "a comment request must not auto-approve git.pr.create")
    }

    func testAutoDoesNotAutoApprovePushForOpenPullRequestToRead() async {
        let reviewer = StaticSafetyReviewer()
        // "open the pull request to read it" is a READ intent — the co-occurring word "open" must not
        // auto-approve git.push. The view rule takes priority.
        let call = ToolCall(name: gitPush.name, argumentsJSON: #"{}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "open the pull request to read it",
            toolCall: call,
            toolDefinition: gitPush,
            recentMessages: [.init(role: .user, content: "open the pull request to read it")]
        ))
        XCTAssertNotEqual(review.verdict, ApprovalVerdict.approve, "a read request must not auto-approve git.push")
    }

    func testAutoApprovesUserRequestedPullRequestComment() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestComment.name,
            argumentsJSON: #"{"selector":"42","body":"Ready for review."}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "comment on PR 42 saying Ready for review.",
            toolCall: call,
            toolDefinition: gitPullRequestComment,
            recentMessages: [.init(role: .user, content: "comment on PR 42 saying Ready for review.")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesUserRequestedPullRequestCheckout() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestCheckout.name,
            argumentsJSON: #"{"selector":"42"}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "checkout PR 42",
            toolCall: call,
            toolDefinition: gitPullRequestCheckout,
            recentMessages: [.init(role: .user, content: "checkout PR 42")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesUserRequestedPullRequestReviewerRequest() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestReviewers.name,
            argumentsJSON: #"{"selector":"42","add":["alice"]}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "request review from alice on PR 42",
            toolCall: call,
            toolDefinition: gitPullRequestReviewers,
            recentMessages: [.init(role: .user, content: "request review from alice on PR 42")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesUserRequestedPullRequestLabels() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestLabels.name,
            argumentsJSON: #"{"selector":"42","add":["merge-train"]}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "label PR 42 merge-train",
            toolCall: call,
            toolDefinition: gitPullRequestLabels,
            recentMessages: [.init(role: .user, content: "label PR 42 merge-train")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesUserRequestedPullRequestReview() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestReview.name,
            argumentsJSON: #"{"selector":"42","action":"request_changes","body":"Please add tests."}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "request changes on PR 42 saying Please add tests.",
            toolCall: call,
            toolDefinition: gitPullRequestReview,
            recentMessages: [.init(role: .user, content: "request changes on PR 42 saying Please add tests.")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesUserRequestedPullRequestInlineCommentAndReply() async {
        let reviewer = StaticSafetyReviewer()
        let inlineComment = ToolCall(
            name: gitPullRequestReviewComment.name,
            argumentsJSON: #"{"selector":"42","path":"Sources/App.swift","line":12,"body":"Please cover this."}"#
        )
        let inlineReview = await reviewer.review(.init(
            mode: .auto,
            userMessage: "comment on PR 42 line 12 saying Please cover this.",
            toolCall: inlineComment,
            toolDefinition: gitPullRequestReviewComment,
            recentMessages: [.init(role: .user, content: "comment on PR 42 line 12 saying Please cover this.")]
        ))
        XCTAssertEqual(inlineReview.verdict, ApprovalVerdict.approve)

        let reply = ToolCall(
            name: gitPullRequestReviewReply.name,
            argumentsJSON: #"{"selector":"42","commentId":99,"body":"Updated this."}"#
        )
        let replyReview = await reviewer.review(.init(
            mode: .auto,
            userMessage: "reply to review comment 99 on PR 42 saying Updated this.",
            toolCall: reply,
            toolDefinition: gitPullRequestReviewReply,
            recentMessages: [.init(role: .user, content: "reply to review comment 99 on PR 42 saying Updated this.")]
        ))
        XCTAssertEqual(replyReview.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesUserRequestedPullRequestReviewThreadResolution() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestReviewThread.name,
            argumentsJSON: #"{"threadId":"PRRT_kwDOExample","action":"resolve"}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "resolve the review thread PRRT_kwDOExample",
            toolCall: call,
            toolDefinition: gitPullRequestReviewThread,
            recentMessages: [.init(role: .user, content: "resolve the review thread PRRT_kwDOExample")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesUserRequestedPullRequestReviewThreadListing() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestReviewThreads.name,
            argumentsJSON: #"{"selector":"42"}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "show unresolved review threads and IDs on PR 42",
            toolCall: call,
            toolDefinition: gitPullRequestReviewThreads,
            recentMessages: [.init(role: .user, content: "show unresolved review threads and IDs on PR 42")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesUserRequestedPullRequestMerge() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestMerge.name,
            argumentsJSON: #"{"selector":"42","method":"squash","auto":true}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "auto merge PR 42 when checks pass",
            toolCall: call,
            toolDefinition: gitPullRequestMerge,
            recentMessages: [.init(role: .user, content: "auto merge PR 42 when checks pass")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoClarifiesPullRequestMergeWhenUserOnlyAsksToView() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(
            name: gitPullRequestMerge.name,
            argumentsJSON: #"{"selector":"42","method":"squash","auto":false}"#
        )
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "show pull request 42",
            toolCall: call,
            toolDefinition: gitPullRequestMerge,
            recentMessages: [.init(role: .user, content: "show pull request 42")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.clarify)
    }

    func testAutoDoesNotTreatPullRequestTokenAsBlanketIntentForPush() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: gitPush.name, argumentsJSON: #"{"remote":"origin","branch":"main"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "show PR 42",
            toolCall: call,
            toolDefinition: gitPush,
            recentMessages: [.init(role: .user, content: "show PR 42")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.clarify)
    }

    func testAutoDoesNotTreatBarePullRequestTokenAsBlanketIntentForPush() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: gitPush.name, argumentsJSON: #"{"remote":"origin","branch":"main"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "PR 42",
            toolCall: call,
            toolDefinition: gitPush,
            recentMessages: [.init(role: .user, content: "PR 42")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.clarify)
    }

    func testAutoApprovesUserRequestedWorktree() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: gitWorktreeCreate.name, argumentsJSON: #"{"path":"quillcode-feature","branch":"feature"}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "create a worktree for this feature",
            toolCall: call,
            toolDefinition: gitWorktreeCreate,
            recentMessages: [.init(role: .user, content: "create a worktree for this feature")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }

    func testAutoApprovesExplicitComputerUseClick() async {
        let reviewer = StaticSafetyReviewer()
        let call = ToolCall(name: computerClick.name, argumentsJSON: #"{"x":42,"y":84}"#)
        let review = await reviewer.review(.init(
            mode: .auto,
            userMessage: "click 42 84",
            toolCall: call,
            toolDefinition: computerClick,
            recentMessages: [.init(role: .user, content: "click 42 84")]
        ))
        XCTAssertEqual(review.verdict, ApprovalVerdict.approve)
    }
}
