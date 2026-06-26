import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceToolRunCoordinatorTests: XCTestCase {
    func testCoordinatorCreatesFirstThreadRunsToolAndRecordsEvents() throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf coordinator"])
        )

        let result = WorkspaceToolRunCoordinator(
            model: model,
            workspaceRoot: workspaceRoot
        ).run(call)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "coordinator")
        XCTAssertEqual(model.root.threads.count, 1)
        XCTAssertEqual(model.root.topBar.agentStatus, TopBarAgentStatusLabel.idle)
        XCTAssertEqual(
            model.selectedThread?.events.map(\.kind),
            [.toolQueued, .toolRunning, .toolCompleted]
        )
    }
}
