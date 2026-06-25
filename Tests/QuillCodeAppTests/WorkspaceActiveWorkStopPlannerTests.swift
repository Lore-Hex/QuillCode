import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceActiveWorkStopPlannerTests: XCTestCase {
    func testCancelClearsErrorAndStopsWhenWorkspaceWorkWasActive() {
        let plan = WorkspaceActiveWorkStopPlanner.cancel(stoppedWork: WorkspaceStoppedActiveWork(
            hadRunningMCPServers: false,
            hadActiveWork: true
        ))

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.stopped)
    }

    func testCancelClearsErrorWithoutRefreshingStatusWhenNoWorkStopped() {
        let plan = WorkspaceActiveWorkStopPlanner.cancel(stoppedWork: WorkspaceStoppedActiveWork(
            hadRunningMCPServers: false,
            hadActiveWork: false
        ))

        XCTAssertNil(plan.lastError)
        XCTAssertNil(plan.agentStatus)
    }

    func testDisconnectAllReturnsNilWhenThereIsNothingToStopOrDetach() {
        let plan = WorkspaceActiveWorkStopPlanner.disconnectAll(
            stoppedWork: WorkspaceStoppedActiveWork(
                hadRunningMCPServers: false,
                hadActiveWork: false
            ),
            shouldDetachRemoteProject: false
        )

        XCTAssertNil(plan)
    }

    func testDisconnectAllStopsWhenWorkspaceWorkWasActive() throws {
        let plan = try XCTUnwrap(WorkspaceActiveWorkStopPlanner.disconnectAll(
            stoppedWork: WorkspaceStoppedActiveWork(
                hadRunningMCPServers: false,
                hadActiveWork: true
            ),
            shouldDetachRemoteProject: false
        ))

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.stopped)
    }

    func testDisconnectAllStopsWhenMCPServersWereRunning() throws {
        let plan = try XCTUnwrap(WorkspaceActiveWorkStopPlanner.disconnectAll(
            stoppedWork: WorkspaceStoppedActiveWork(
                hadRunningMCPServers: true,
                hadActiveWork: false
            ),
            shouldDetachRemoteProject: false
        ))

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.stopped)
    }

    func testDisconnectAllReturnsIdleWhenOnlyRemoteProjectDetached() throws {
        let plan = try XCTUnwrap(WorkspaceActiveWorkStopPlanner.disconnectAll(
            stoppedWork: WorkspaceStoppedActiveWork(
                hadRunningMCPServers: false,
                hadActiveWork: false
            ),
            shouldDetachRemoteProject: true
        ))

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.idle)
    }
}
