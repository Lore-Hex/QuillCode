import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceTerminalLifecyclePlannerTests: XCTestCase {
    func testStartedClearsErrorAndShowsTerminalStatus() {
        let plan = WorkspaceTerminalLifecyclePlanner.started()

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.terminal)
    }

    func testMissingExecutionContextShowsFailedStatus() {
        let plan = WorkspaceTerminalLifecyclePlanner.missingExecutionContext()

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.failed)
    }

    func testStoppedAndCancelledShowStoppedStatus() {
        let stopped = WorkspaceTerminalLifecyclePlanner.stopped()
        let cancelled = WorkspaceTerminalLifecyclePlanner.cancelled()

        XCTAssertNil(stopped.lastError)
        XCTAssertEqual(stopped.agentStatus, TopBarAgentStatusLabel.stopped)
        XCTAssertNil(cancelled.lastError)
        XCTAssertEqual(cancelled.agentStatus, TopBarAgentStatusLabel.stopped)
    }

    func testFinishedShowsIdleForSuccessfulResult() {
        let plan = WorkspaceTerminalLifecyclePlanner.finished(result: ToolResult(ok: true, exitCode: 0))

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.idle)
    }

    func testFinishedShowsFailedForFailedResult() {
        let plan = WorkspaceTerminalLifecyclePlanner.finished(result: ToolResult(ok: false, exitCode: 1))

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.failed)
    }
}
