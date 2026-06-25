import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentSendTerminalPlannerTests: XCTestCase {
    func testCompletedPlanCarriesThreadAndCompletedLifecycle() {
        let thread = ChatThread(title: "Run tests")
        let result = WorkspaceAgentSendSessionResult(thread: thread, savedMemory: false)

        let plan = WorkspaceAgentSendTerminalPlanner.completed(
            result: result,
            composer: ComposerState(draft: "", isSending: true)
        )

        XCTAssertEqual(plan.thread.id, thread.id)
        XCTAssertFalse(plan.shouldRefreshMemoryContext)
        XCTAssertFalse(plan.lifecycle.composer.isSending)
        XCTAssertNil(plan.lifecycle.lastError)
        XCTAssertEqual(plan.lifecycle.agentStatus, TopBarAgentStatusLabel.idle)
    }

    func testCompletedPlanRequestsMemoryRefreshWhenMemoryWasSaved() {
        let result = WorkspaceAgentSendSessionResult(
            thread: ChatThread(title: "Memory"),
            savedMemory: true
        )

        let plan = WorkspaceAgentSendTerminalPlanner.completed(
            result: result,
            composer: ComposerState(draft: "", isSending: true)
        )

        XCTAssertTrue(plan.shouldRefreshMemoryContext)
    }

    func testCancelledPlanStopsComposerWithoutError() {
        let plan = WorkspaceAgentSendTerminalPlanner.cancelled(
            composer: ComposerState(draft: "", isSending: true)
        )

        XCTAssertFalse(plan.lifecycle.composer.isSending)
        XCTAssertNil(plan.lifecycle.lastError)
        XCTAssertEqual(plan.lifecycle.agentStatus, TopBarAgentStatusLabel.stopped)
    }

    func testFailedPlanStopsComposerAndCapturesError() {
        let plan = WorkspaceAgentSendTerminalPlanner.failed(
            SampleError.nope,
            composer: ComposerState(draft: "", isSending: true)
        )

        XCTAssertFalse(plan.lifecycle.composer.isSending)
        XCTAssertEqual(plan.lifecycle.lastError, "nope")
        XCTAssertEqual(plan.lifecycle.agentStatus, TopBarAgentStatusLabel.failed)
    }

    private enum SampleError: Error {
        case nope
    }
}
