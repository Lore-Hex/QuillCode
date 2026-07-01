import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceRunNotificationBuilderTests: XCTestCase {
    private func thread(
        title: String = "Refactor auth",
        messages: [ChatMessage] = [],
        events: [ThreadEvent] = []
    ) -> ChatThread {
        ChatThread(title: title, messages: messages, events: events)
    }

    private func approvalRequested(id: String, tool: String) -> ThreadEvent {
        let request = ApprovalRequest(
            id: id,
            toolCall: ToolCall(name: tool, argumentsJSON: "{}"),
            toolDefinition: nil,
            reason: "gate"
        )
        return ThreadEvent(
            kind: .approvalRequested,
            summary: "approval requested",
            payloadJSON: String(decoding: (try? JSONEncoder().encode(request)) ?? Data(), as: UTF8.self)
        )
    }

    private func approvalDecided(requestID: String) -> ThreadEvent {
        let decision = ApprovalDecision(requestID: requestID, verdict: .approve, rationale: "ok")
        return ThreadEvent(
            kind: .approvalDecided,
            summary: "approval decided",
            payloadJSON: String(decoding: (try? JSONEncoder().encode(decision)) ?? Data(), as: UTF8.self)
        )
    }

    func testFinishedRunFromAssistantAnswer() {
        let t = thread(messages: [ChatMessage(role: .assistant, content: "Done: added 6 tests.")])
        let note = WorkspaceRunNotificationBuilder.notification(thread: t, didFail: false)
        XCTAssertEqual(note?.kind, .finished)
        XCTAssertTrue(note?.body.contains("added 6 tests") == true, note?.body ?? "")
        XCTAssertEqual(note?.threadID, t.id)
    }

    func testFailedRunNotifies() {
        let t = thread(messages: [ChatMessage(role: .assistant, content: "partial")])
        let note = WorkspaceRunNotificationBuilder.notification(thread: t, didFail: true)
        XCTAssertEqual(note?.kind, .failed)
    }

    func testUndecidedApprovalIsNeedsApprovalAndBeatsAnswer() {
        let t = thread(
            messages: [ChatMessage(role: .assistant, content: "I plan to run it.")],
            events: [approvalRequested(id: "a1", tool: "host.shell.run")]
        )
        let note = WorkspaceRunNotificationBuilder.notification(thread: t, didFail: false)
        XCTAssertEqual(note?.kind, .needsApproval)
        XCTAssertTrue(note?.body.contains("host.shell.run") == true, note?.body ?? "")
        // Carries the request id so the notification's Approve/Skip actions can decide this exact gate.
        XCTAssertEqual(note?.approvalRequestID, "a1")
    }

    func testFinishedNotificationCarriesNoApprovalRequestID() {
        let t = thread(messages: [ChatMessage(role: .assistant, content: "done")])
        XCTAssertNil(WorkspaceRunNotificationBuilder.notification(thread: t, didFail: false)?.approvalRequestID)
    }

    func testDecidedApprovalDoesNotBlock() {
        // Requested AND decided -> not pending -> falls through to the finished answer.
        let t = thread(
            messages: [ChatMessage(role: .assistant, content: "All done.")],
            events: [approvalRequested(id: "a1", tool: "host.shell.run"), approvalDecided(requestID: "a1")]
        )
        let note = WorkspaceRunNotificationBuilder.notification(thread: t, didFail: false)
        XCTAssertEqual(note?.kind, .finished)
    }

    func testNoAnswerNoApprovalNoFailureIsSilent() {
        XCTAssertNil(WorkspaceRunNotificationBuilder.notification(thread: thread(), didFail: false))
    }
}
