import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentTranscriptRefreshTrackerTests: XCTestCase {
    func testReconcilerClassifiesAssistantAndReasoningTailUpdatesAsIncremental() {
        let assistant = ChatMessage(role: .assistant, content: "Draft")
        let notice = ThreadEvent(kind: .notice, summary: "Thinking: one")
        var live = ChatThread(messages: [assistant], events: [notice])
        var snapshot = live
        snapshot.messages[0].content = "Draft continued"
        snapshot.events[0].summary = "Thinking: two"

        let mutation = WorkspaceAgentProgressThreadReconciler.reconcile(snapshot, into: &live)

        XCTAssertEqual(mutation.messageMutation, .replacedAssistantTail(messageID: assistant.id))
        XCTAssertFalse(mutation.eventsAffectTranscript)
        XCTAssertFalse(mutation.contextAffectsTranscript)
        XCTAssertEqual(live, snapshot)
    }

    func testReconcilerForcesRebuildWhenAssistantTailHasPersistedMessageEvent() {
        let assistant = ChatMessage(role: .assistant, content: "Finished")
        var live = ChatThread(
            messages: [assistant],
            events: [ThreadEvent(kind: .message, summary: assistant.content)]
        )
        var snapshot = live
        snapshot.messages[0].content = "Changed after persistence"

        let mutation = WorkspaceAgentProgressThreadReconciler.reconcile(snapshot, into: &live)

        XCTAssertEqual(mutation.messageMutation, .replacedAssistantTail(messageID: assistant.id))
        XCTAssertTrue(mutation.eventsAffectTranscript)
    }

    func testReconcilerForcesRebuildForToolLifecycleChanges() {
        var live = ChatThread(
            messages: [ChatMessage(role: .user, content: "Run")],
            events: [ThreadEvent(kind: .toolQueued, summary: "queued")]
        )
        var snapshot = live
        snapshot.events.append(ThreadEvent(kind: .toolRunning, summary: "running"))

        let mutation = WorkspaceAgentProgressThreadReconciler.reconcile(snapshot, into: &live)

        XCTAssertEqual(mutation.messageMutation, .unchanged)
        XCTAssertTrue(mutation.eventsAffectTranscript)
    }

    func testCoalescedAppendThenReplaceRetainsSingleTailPatch() {
        let threadID = UUID()
        let messageID = UUID()
        let append = WorkspaceAgentTranscriptRefreshPlan.appendAssistantTail(
            threadID: threadID,
            messageID: messageID
        )
        let replace = WorkspaceAgentTranscriptRefreshPlan.replaceAssistantTail(
            threadID: threadID,
            messageID: messageID
        )

        XCTAssertEqual(append.combined(with: replace), append)
        XCTAssertEqual(replace.combined(with: append), .rebuild)
    }

    func testTrackerFallsBackWithoutAnAuthoritativePublishedBaseline() {
        let threadID = UUID()
        var tracker = WorkspaceAgentTranscriptRefreshTracker()
        tracker.record(
            WorkspaceAgentProgressThreadMutation(
                threadID: threadID,
                messageMutation: .unchanged,
                eventsAffectTranscript: false,
                contextAffectsTranscript: false
            ),
            selectedThreadID: threadID
        )

        XCTAssertEqual(tracker.consume(selectedThreadID: threadID), .rebuild)
    }
}
