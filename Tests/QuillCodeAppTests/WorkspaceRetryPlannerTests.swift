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

    func testImageOnlyUserMessageIsRetryable() throws {
        let attachment = try XCTUnwrap(ChatAttachment(
            displayName: "screen.png",
            format: .png,
            localURL: URL(fileURLWithPath: "/tmp/screen.png"),
            byteCount: 8
        ))
        let thread = ChatThread(messages: [
            ChatMessage(role: .user, content: "", attachments: [attachment])
        ])

        XCTAssertTrue(WorkspaceRetryPlanner.canRetryLastUserTurn(in: thread, isSending: false))
        XCTAssertEqual(WorkspaceRetryPlanner.retryMessage(in: thread)?.attachments, [attachment])
    }
}
