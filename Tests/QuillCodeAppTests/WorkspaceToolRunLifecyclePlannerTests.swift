import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceToolRunLifecyclePlannerTests: XCTestCase {
    func testStartedClearsErrorAndShowsRunningStatus() {
        let plan = WorkspaceToolRunLifecyclePlanner.started()

        XCTAssertNil(plan.lastError)
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.running)
    }

    func testFinishedReturnsPrimaryResultAndIdleWhenAllToolResultsPass() {
        let execution = WorkspaceToolCallExecution(
            primary: WorkspaceRecordedToolResult(
                call: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: "{}"),
                result: ToolResult(ok: true, stdout: "done")
            ),
            followUps: [
                WorkspaceRecordedToolResult(
                    call: ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"),
                    result: ToolResult(ok: true, stdout: "diff")
                )
            ]
        )

        let plan = WorkspaceToolRunLifecyclePlanner.finished(execution: execution)

        XCTAssertEqual(plan.result.stdout, "done")
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.idle)
    }

    func testFinishedShowsFailedWhenFollowUpFails() {
        let execution = WorkspaceToolCallExecution(
            primary: WorkspaceRecordedToolResult(
                call: ToolCall(name: ToolDefinition.applyPatch.name, argumentsJSON: "{}"),
                result: ToolResult(ok: true, stdout: "patched")
            ),
            followUps: [
                WorkspaceRecordedToolResult(
                    call: ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"),
                    result: ToolResult(ok: false, error: "diff failed")
                )
            ]
        )

        let plan = WorkspaceToolRunLifecyclePlanner.finished(execution: execution)

        XCTAssertEqual(plan.result.stdout, "patched")
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.failed)
    }

    func testFinishedShowsFailedWhenPrimaryFails() {
        let execution = WorkspaceToolCallExecution(
            primary: WorkspaceRecordedToolResult(
                call: ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: "{}"),
                result: ToolResult(ok: false, error: "command failed")
            ),
            followUps: []
        )

        let plan = WorkspaceToolRunLifecyclePlanner.finished(execution: execution)

        XCTAssertEqual(plan.result.error, "command failed")
        XCTAssertEqual(plan.agentStatus, TopBarAgentStatusLabel.failed)
    }
}
