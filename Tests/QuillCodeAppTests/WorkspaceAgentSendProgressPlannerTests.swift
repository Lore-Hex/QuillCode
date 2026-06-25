import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentSendProgressPlannerTests: XCTestCase {
    func testProgressPlanCarriesThreadAndKeepsComposerSending() throws {
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolRunning, summary: "Running tests")
        ])

        let plan = try XCTUnwrap(WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: thread.id,
            composer: ComposerState(draft: "keep draft", isSending: false)
        ))

        XCTAssertEqual(plan.thread.id, thread.id)
        XCTAssertEqual(plan.composer.draft, "keep draft")
        XCTAssertTrue(plan.composer.isSending)
        XCTAssertNil(plan.lastError)
    }

    func testProgressPlanUsesStreamingStatusForStreamingNotice() throws {
        var thread = ChatThread(title: "Streaming")
        thread.events.append(ThreadEvent(kind: .notice, summary: AgentRunner.streamingNotice))

        let plan = try XCTUnwrap(WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: thread.id,
            composer: ComposerState(draft: "", isSending: true)
        ))

        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.streaming)
    }

    func testProgressPlanUsesLatestThreadEventForStatus() throws {
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "Queued"),
            ThreadEvent(kind: .toolCompleted, summary: "Done")
        ])

        let plan = try XCTUnwrap(WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: thread.id,
            composer: ComposerState(draft: "", isSending: true)
        ))

        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.finishing)
    }

    func testProgressPlanIgnoresProgressFromDifferentThread() {
        let thread = ChatThread(title: "Other")

        let plan = WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: UUID(),
            composer: ComposerState(draft: "keep draft", isSending: true)
        )

        XCTAssertNil(plan)
    }
}
