import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceLocalCommandTranscriptAppenderTests: XCTestCase {
    func testAppendSetsDefaultTitleAndAddsUserAssistantMessages() {
        var thread = ChatThread(title: "New chat")
        let transcript = WorkspaceLocalCommandTranscript(
            userText: "/status",
            assistantText: "Project: QuillCode",
            title: "Status"
        )

        WorkspaceLocalCommandTranscriptAppender.append(transcript, to: &thread)

        XCTAssertEqual(thread.title, "Status")
        XCTAssertEqual(thread.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(thread.messages.map(\.content), ["/status", "Project: QuillCode"])
    }

    func testAppendPreservesExistingTitleAndMessages() {
        var thread = ChatThread(
            title: "Existing chat",
            messages: [ChatMessage(role: .user, content: "previous")]
        )
        let transcript = WorkspaceLocalCommandTranscript(
            userText: "/mode review",
            assistantText: "Mode set to Review.",
            title: "Set mode"
        )

        WorkspaceLocalCommandTranscriptAppender.append(transcript, to: &thread)

        XCTAssertEqual(thread.title, "Existing chat")
        XCTAssertEqual(thread.messages.map(\.role), [.user, .user, .assistant])
        XCTAssertEqual(thread.messages.map(\.content), ["previous", "/mode review", "Mode set to Review."])
    }
}
