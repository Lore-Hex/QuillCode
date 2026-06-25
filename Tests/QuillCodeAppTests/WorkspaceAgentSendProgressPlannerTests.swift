import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentSendProgressPlannerTests: XCTestCase {
    func testProgressPlanCarriesThreadAndRunningComposerState() throws {
        var thread = ChatThread(title: "Run tests")
        thread.events.append(ThreadEvent(kind: .toolQueued, summary: "Run Shell"))

        let plan = try XCTUnwrap(WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: thread.id
        ))

        XCTAssertEqual(plan.thread.id, thread.id)
        XCTAssertTrue(plan.composerIsSending)
        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.queued)
    }

    func testProgressPlanUsesStreamingStatusForStreamingNotice() throws {
        var thread = ChatThread(title: "Streaming")
        thread.events.append(ThreadEvent(kind: .notice, summary: AgentRunner.streamingNotice))

        let plan = try XCTUnwrap(WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: thread.id
        ))

        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.streaming)
    }

    func testProgressPlanIgnoresProgressFromDifferentThread() {
        let thread = ChatThread(title: "Other")

        let plan = WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: UUID()
        )

        XCTAssertNil(plan)
    }
}
