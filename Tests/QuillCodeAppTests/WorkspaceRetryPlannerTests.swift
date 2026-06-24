import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceRetryPlannerTests: XCTestCase {
    func testRetryDraftUsesLatestNonEmptyUserMessageAndPreservesOriginalText() {
        let thread = ChatThread(messages: [
            ChatMessage(role: .assistant, content: "Ready."),
            ChatMessage(role: .user, content: "run whoami"),
            ChatMessage(role: .user, content: "   "),
            ChatMessage(role: .assistant, content: "Done."),
            ChatMessage(role: .user, content: "  run pwd  ")
        ])

        XCTAssertEqual(WorkspaceRetryPlanner.retryDraft(in: thread), "  run pwd  ")
    }

    func testRetryRequiresUserMessageAndIdleComposer() {
        let assistantOnly = ChatThread(messages: [
            ChatMessage(role: .assistant, content: "I can help.")
        ])
        let retryable = ChatThread(messages: [
            ChatMessage(role: .user, content: "run tests")
        ])

        XCTAssertFalse(WorkspaceRetryPlanner.canRetryLastUserTurn(in: nil, isSending: false))
        XCTAssertFalse(WorkspaceRetryPlanner.canRetryLastUserTurn(in: assistantOnly, isSending: false))
        XCTAssertFalse(WorkspaceRetryPlanner.canRetryLastUserTurn(in: retryable, isSending: true))
        XCTAssertTrue(WorkspaceRetryPlanner.canRetryLastUserTurn(in: retryable, isSending: false))
    }
}
