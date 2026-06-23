import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceToolExecutionOverrideCombinerTests: XCTestCase {
    func testReturnsNilWhenNoOverridesAreAvailable() {
        XCTAssertNil(WorkspaceToolExecutionOverrideCombiner.combine(
            plan: nil,
            browser: nil,
            computerUse: nil,
            memory: nil,
            mcp: nil,
            remoteProject: nil
        ))
    }

    func testUsesFirstOverrideWithResultInWorkspaceOrder() async throws {
        let recorder = OverrideRecorder()
        let override = try XCTUnwrap(WorkspaceToolExecutionOverrideCombiner.combine(
            plan: recordingOverride("plan", result: ToolResult(ok: true, stdout: "plan"), recorder: recorder),
            browser: recordingOverride("browser", result: ToolResult(ok: true, stdout: "browser"), recorder: recorder),
            computerUse: recordingOverride("computerUse", result: ToolResult(ok: true, stdout: "computer"), recorder: recorder),
            memory: recordingOverride("memory", result: ToolResult(ok: true, stdout: "memory"), recorder: recorder),
            mcp: recordingOverride("mcp", result: ToolResult(ok: true, stdout: "mcp"), recorder: recorder),
            remoteProject: recordingOverride("remoteProject", result: ToolResult(ok: true, stdout: "remote"), recorder: recorder)
        ))

        let result = await override(sampleCall(), sampleWorkspaceRoot())
        let calls = await recorder.snapshot()

        XCTAssertEqual(result?.stdout, "plan")
        XCTAssertEqual(calls, ["plan"])
    }

    func testFallsThroughNilOverridesUntilLaterHandlerReturnsResult() async throws {
        let recorder = OverrideRecorder()
        let override = try XCTUnwrap(WorkspaceToolExecutionOverrideCombiner.combine(
            plan: recordingOverride("plan", result: nil, recorder: recorder),
            browser: recordingOverride("browser", result: nil, recorder: recorder),
            computerUse: recordingOverride("computerUse", result: ToolResult(ok: true, stdout: "computer"), recorder: recorder),
            memory: recordingOverride("memory", result: ToolResult(ok: true, stdout: "memory"), recorder: recorder),
            mcp: recordingOverride("mcp", result: ToolResult(ok: true, stdout: "mcp"), recorder: recorder),
            remoteProject: recordingOverride("remoteProject", result: nil, recorder: recorder)
        ))

        let result = await override(sampleCall(), sampleWorkspaceRoot())
        let calls = await recorder.snapshot()

        XCTAssertEqual(result?.stdout, "computer")
        XCTAssertEqual(calls, ["plan", "remoteProject", "browser", "computerUse"])
    }

    func testFallsThroughAllOverridesWhenNoHandlerReturnsResult() async throws {
        let recorder = OverrideRecorder()
        let override = try XCTUnwrap(WorkspaceToolExecutionOverrideCombiner.combine(
            plan: recordingOverride("plan", result: nil, recorder: recorder),
            browser: recordingOverride("browser", result: nil, recorder: recorder),
            computerUse: recordingOverride("computerUse", result: nil, recorder: recorder),
            memory: recordingOverride("memory", result: nil, recorder: recorder),
            mcp: recordingOverride("mcp", result: nil, recorder: recorder),
            remoteProject: recordingOverride("remoteProject", result: nil, recorder: recorder)
        ))

        let result = await override(sampleCall(), sampleWorkspaceRoot())
        let calls = await recorder.snapshot()

        XCTAssertNil(result)
        XCTAssertEqual(calls, ["plan", "remoteProject", "browser", "computerUse", "memory", "mcp"])
    }

    private func sampleCall() -> ToolCall {
        ToolCall(name: "host.test", argumentsJSON: "{}")
    }

    private func sampleWorkspaceRoot() -> URL {
        URL(fileURLWithPath: "/tmp/quillcode-workspace")
    }

    private func recordingOverride(
        _ label: String,
        result: ToolResult?,
        recorder: OverrideRecorder
    ) -> AgentToolExecutionOverride {
        { _, _ in
            await recorder.append(label)
            return result
        }
    }
}

private actor OverrideRecorder {
    private var labels: [String] = []

    func append(_ label: String) {
        labels.append(label)
    }

    func snapshot() -> [String] {
        labels
    }
}
