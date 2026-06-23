import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceComposerCancellationPlannerTests: XCTestCase {
    func testCancelledSendSeedsEmptyThreadWithPromptAndNotice() {
        var thread = ChatThread()

        WorkspaceComposerCancellationPlanner.applyCancelledSend(
            userPrompt: "run a long task",
            to: &thread
        )

        XCTAssertEqual(thread.title, "run a long task")
        XCTAssertEqual(thread.messages.map(\.role), [.user])
        XCTAssertEqual(thread.messages.first?.content, "run a long task")
        XCTAssertEqual(thread.events.map(\.kind), [.notice])
        XCTAssertEqual(thread.events.first?.summary, WorkspaceComposerCancellationPlanner.stoppedSummary)
    }

    func testCancelledPendingToolAddsToolFailureBeforeNotice() {
        var thread = ChatThread(
            messages: [ChatMessage(role: .user, content: "do work")],
            events: [ThreadEvent(kind: .toolRunning, summary: "Run Shell")]
        )

        WorkspaceComposerCancellationPlanner.applyCancelledSend(
            userPrompt: "do work",
            to: &thread
        )

        XCTAssertEqual(thread.messages.count, 1)
        XCTAssertEqual(thread.events.map(\.kind), [.toolRunning, .toolFailed, .notice])
        XCTAssertEqual(thread.events[1].summary, WorkspaceComposerCancellationPlanner.stoppedSummary)
        XCTAssertEqual(thread.events[1].payloadJSON, WorkspaceComposerCancellationPlanner.stoppedPayloadJSON)
        XCTAssertEqual(thread.events[2].summary, WorkspaceComposerCancellationPlanner.stoppedSummary)
    }

    func testCancelledSendDoesNotDuplicatePromptOrNotice() {
        var thread = ChatThread(
            messages: [ChatMessage(role: .user, content: "stop this")],
            events: [ThreadEvent(kind: .notice, summary: WorkspaceComposerCancellationPlanner.stoppedSummary)]
        )

        WorkspaceComposerCancellationPlanner.applyCancelledSend(
            userPrompt: "stop this",
            to: &thread
        )

        XCTAssertEqual(thread.messages.count, 1)
        XCTAssertEqual(thread.events.count, 1)
        XCTAssertEqual(thread.events.first?.summary, WorkspaceComposerCancellationPlanner.stoppedSummary)
    }
}
