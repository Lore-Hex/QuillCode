import XCTest
import Foundation
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentRunLoopStateTests: XCTestCase {
    private var root: URL { FileManager.default.temporaryDirectory }

    func testRepeatedCompletionMatchesOnlyTheLastExactCall() {
        var state = AgentRunLoopState()
        let call = shellCall("whoami")
        let completion = completed(call: call, stdout: "quill")

        state.baselineWorkspaceStateIfNeeded(workspaceRoot: root) { _ in "before" }
        _ = state.recordCompletedStep(completion, workspaceRoot: root) { _ in "after" }

        XCTAssertEqual(state.repeatedCompletion(for: call)?.result.stdout, "quill")
        XCTAssertNil(state.repeatedCompletion(for: shellCall("pwd")))
        XCTAssertEqual(state.toolResults.map(\.stdout), ["quill"])
        XCTAssertEqual(state.latestCompletion?.call, call)
    }

    func testNoProgressFlailEscalatesOnlyAfterAssessmentRecord() {
        var state = AgentRunLoopState()
        let call = fileReadCall("same.txt")
        state.baselineWorkspaceStateIfNeeded(workspaceRoot: root) { _ in "constant" }

        XCTAssertEqual(recordNoProgress(call, in: &state), .none)
        XCTAssertEqual(recordNoProgress(call, in: &state), .none)

        guard case .suspected(let suspectedReason) = recordNoProgress(call, in: &state) else {
            return XCTFail("expected suspected flail after three no-progress turns")
        }
        XCTAssertEqual(suspectedReason.kind, .repeatedActionNoProgress)

        XCTAssertTrue(state.recordFlailAssessmentIfNeeded())
        XCTAssertFalse(state.recordFlailAssessmentIfNeeded())

        guard case .confirmed(let confirmedReason) = recordNoProgress(call, in: &state) else {
            return XCTFail("expected confirmed flail after the assessment has been recorded")
        }
        XCTAssertEqual(confirmedReason.kind, .repeatedActionNoProgress)
    }

    func testDefaultWorkspaceSignatureShortCircuitsNonGitDirectories() throws {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(AgentRunner.defaultWorkspaceStateSignature(directory), "no-git")
    }

    func testWriteNeedsLaterSuccessfulReadAndRewriteRearmsVerification() {
        var state = AgentRunLoopState()
        let write = ToolCall(
            name: "host.file.write",
            argumentsJSON: ToolArguments.json(["path": "./outputs/report.md", "content": "draft"])
        )
        let read = fileReadCall("outputs/report.md")
        state.baselineWorkspaceStateIfNeeded(workspaceRoot: root) { _ in "before" }

        _ = state.recordCompletedStep(completed(call: write, stdout: "wrote"), workspaceRoot: root) { _ in "write" }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/report.md"])

        _ = state.recordCompletedStep(
            completed(call: read, stdout: "missing", ok: false),
            workspaceRoot: root
        ) { _ in "write" }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/report.md"])

        _ = state.recordCompletedStep(completed(call: read, stdout: "draft"), workspaceRoot: root) { _ in "write" }
        XCTAssertTrue(state.unverifiedWrittenWorkspacePaths.isEmpty)

        _ = state.recordCompletedStep(completed(call: write, stdout: "rewrote"), workspaceRoot: root) { _ in "rewrite" }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/report.md"])
    }

    func testRenderedChartNeedsLaterSuccessfulRead() {
        var state = AgentRunLoopState()
        let render = ToolCall(
            name: ToolDefinition.chartRender.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.png",
                "categories": ["Q1"],
                "series": ["East": "10"],
            ] as [String: Any])
        )
        let read = fileReadCall("outputs/revenue.png")
        state.baselineWorkspaceStateIfNeeded(workspaceRoot: root) { _ in "before" }

        _ = state.recordCompletedStep(completed(call: render, stdout: "rendered"), workspaceRoot: root) { _ in
            "render"
        }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/revenue.png"])

        _ = state.recordCompletedStep(completed(call: read, stdout: "PNG image"), workspaceRoot: root) { _ in
            "render"
        }
        XCTAssertTrue(state.unverifiedWrittenWorkspacePaths.isEmpty)
    }

    func testBatchReadVerifiesEveryWrittenPath() {
        var state = AgentRunLoopState()
        let firstWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/first.md", "content": "first"])
        )
        let secondWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "outputs/second.md", "content": "second"])
        )
        let batchRead = ToolCall(
            name: ToolDefinition.fileReadMany.name,
            argumentsJSON: ToolArguments.json(["paths": ["outputs/first.md", "outputs/second.md"]])
        )

        _ = state.recordCompletedStep(completed(call: firstWrite, stdout: "wrote"), workspaceRoot: root) { _ in
            "first"
        }
        _ = state.recordCompletedStep(completed(call: secondWrite, stdout: "wrote"), workspaceRoot: root) { _ in
            "second"
        }
        XCTAssertEqual(state.unverifiedWrittenWorkspacePaths, ["outputs/first.md", "outputs/second.md"])

        _ = state.recordCompletedStep(completed(call: batchRead, stdout: "first\nsecond"), workspaceRoot: root) { _ in
            "second"
        }

        XCTAssertTrue(state.unverifiedWrittenWorkspacePaths.isEmpty)
        XCTAssertEqual(state.successfullyReadWorkspacePaths, ["outputs/first.md", "outputs/second.md"])
    }

    private func recordNoProgress(
        _ call: ToolCall,
        in state: inout AgentRunLoopState
    ) -> FlailVerdict {
        state.recordCompletedStep(
            completed(call: call, stdout: "same"),
            workspaceRoot: root
        ) { _ in "constant" }
    }

    private func shellCall(_ command: String) -> ToolCall {
        ToolCall(
            name: "host.shell.run",
            argumentsJSON: ToolArguments.json(["cmd": command])
        )
    }

    private func fileReadCall(_ path: String) -> ToolCall {
        ToolCall(
            name: "host.file.read",
            argumentsJSON: ToolArguments.json(["path": path])
        )
    }

    private func completed(call: ToolCall, stdout: String, ok: Bool = true) -> AgentToolStepCompletion {
        let result = ToolResult(ok: ok, stdout: stdout)
        return AgentToolStepCompletion(
            call: call,
            result: result,
            followUpReviewResult: nil,
            toolResults: [result]
        )
    }
}
