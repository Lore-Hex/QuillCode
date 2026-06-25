import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentSendCompletionPlannerTests: XCTestCase {
    func testCompletedPlanCarriesThreadAndCompletedLifecycle() {
        let thread = ChatThread(title: "Run tests")
        let result = WorkspaceAgentSendSessionResult(thread: thread, savedMemory: false)

        let plan = WorkspaceAgentSendCompletionPlanner.completed(
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

        let plan = WorkspaceAgentSendCompletionPlanner.completed(
            result: result,
            composer: ComposerState(draft: "", isSending: true)
        )

        XCTAssertTrue(plan.shouldRefreshMemoryContext)
    }
}
