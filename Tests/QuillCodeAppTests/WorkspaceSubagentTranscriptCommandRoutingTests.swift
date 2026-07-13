import XCTest
@testable import QuillCodeApp

final class WorkspaceSubagentTranscriptCommandRoutingTests: XCTestCase {
    func testDurableTranscriptCommandRoutesBeforeGenericDispatch() {
        let parentThreadID = UUID()
        let runID = UUID()
        let workerID = "worker-research-2"
        let command = WorkspaceCommandSurface(
            id: WorkspaceSubagentTranscriptCommand.openCommandID(
                parentThreadID: parentThreadID,
                runID: runID,
                workerID: workerID
            ),
            title: "View"
        )

        let action = makePlanner().action(for: command)

        XCTAssertEqual(
            action,
            .presentSubagentTranscript(
                parentThreadID: parentThreadID,
                runID: runID,
                workerID: workerID
            )
        )
    }

    func testMalformedTranscriptCommandDoesNotPresentDrilldown() {
        let command = WorkspaceCommandSurface(
            id: "activity-subagent-open:not-a-thread:not-a-run:worker",
            title: "View"
        )

        XCTAssertNil(makePlanner().action(for: command))
    }

    private func makePlanner() -> WorkspaceViewCommandPlanner {
        WorkspaceViewCommandPlanner(
            sidebar: SidebarSurface(items: [], selectedThreadID: nil),
            projects: ProjectListSurface(items: [], selectedProjectID: nil)
        )
    }
}
