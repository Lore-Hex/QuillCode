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

    func testResearchCheckpointArmsAfterSuccessfulWebWorkAndClearsOnNamedDraft() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )

        for index in 0..<AgentResearchCheckpointGate.minimumPreDraftResearchWeight {
            let search = ToolCall(
                name: ToolDefinition.webSearch.name,
                argumentsJSON: ToolArguments.json(["query": "competitor \(index)"])
            )
            _ = state.recordCompletedStep(
                completed(call: search, stdout: "result \(index)"),
                workspaceRoot: root
            ) { _ in "search-\(index)" }
        }

        XCTAssertEqual(
            state.pendingResearchCheckpointPath(
                minimumResearchWeight: AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            ),
            "outputs/revenue.html"
        )

        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Checkpoint</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        XCTAssertNil(state.pendingResearchCheckpointPath(minimumResearchWeight: 1))
        XCTAssertEqual(state.successfulResearchWeightBeforeDraft, 0)
    }

    func testFailedWebWorkDoesNotArmResearchCheckpoint() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(userMessage: "Research and write outputs/report.md.")
        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.com"])
        )

        for _ in 0..<AgentResearchCheckpointGate.minimumPreDraftResearchWeight {
            _ = state.recordCompletedStep(
                completed(call: fetch, stdout: "failed", ok: false),
                workspaceRoot: root
            ) { _ in "constant" }
        }

        XCTAssertNil(
            state.pendingResearchCheckpointPath(
                minimumResearchWeight: AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            )
        )
    }

    func testDelegatedResearchContributesToPreDraftCheckpoint() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )

        for index in 0..<(AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            - AgentResearchCheckpointGate.delegatedResearchWeight) {
            let search = ToolCall(
                name: ToolDefinition.webSearch.name,
                argumentsJSON: ToolArguments.json(["query": "competitor \(index)"])
            )
            _ = state.recordCompletedStep(
                completed(call: search, stdout: "result \(index)"),
                workspaceRoot: root
            ) { _ in "search-\(index)" }
        }

        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "research competitors",
                "workers": [["name": "A", "role": "research A"]],
            ] as [String: Any])
        )
        _ = state.recordCompletedStep(
            completed(call: delegated, stdout: "verified evidence"),
            workspaceRoot: root
        ) { _ in "delegated" }

        XCTAssertEqual(
            state.pendingResearchCheckpointPath(
                minimumResearchWeight: AgentResearchCheckpointGate.minimumPreDraftResearchWeight
            ),
            "outputs/revenue.html"
        )
    }

    func testForcedResearchCheckpointRequiresWebWorkAndFinalRewrite() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )
        state.expectResearchCheckpoint(at: "outputs/revenue.html")

        let checkpoint = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Checkpoint with evidence gaps</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: checkpoint, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "checkpoint" }

        XCTAssertEqual(state.pendingResearchContinuationPath(), "outputs/revenue.html")
        XCTAssertFalse(state.didResumeResearch(afterCheckpointAt: "outputs/revenue.html"))

        let fetch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.com/revenue"])
        )
        _ = state.recordCompletedStep(
            completed(call: fetch, stdout: "revenue evidence"),
            workspaceRoot: root
        ) { _ in "fetch" }

        XCTAssertTrue(state.didResumeResearch(afterCheckpointAt: "outputs/revenue.html"))
        XCTAssertEqual(state.pendingResearchContinuationPath(), "outputs/revenue.html")

        let finalWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Complete final comparison</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: finalWrite, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "final" }

        XCTAssertNil(state.pendingResearchContinuationPath())
        XCTAssertEqual(state.successfulResearchStepsAfterCheckpoint, 0)
    }

    func testPostCheckpointResearchBudgetRequiresSynthesis() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(
            userMessage: "Research competitors and write outputs/revenue.html with citations."
        )
        state.expectResearchCheckpoint(at: "outputs/revenue.html")
        let checkpoint = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/revenue.html",
                "content": "<p>Checkpoint</p>",
            ])
        )
        _ = state.recordCompletedStep(
            completed(call: checkpoint, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "checkpoint" }

        let delegated = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "research competitors",
                "workers": [["name": "A", "role": "research A"]],
            ] as [String: Any])
        )
        _ = state.recordCompletedStep(
            completed(call: delegated, stdout: "verified evidence"),
            workspaceRoot: root
        ) { _ in "delegated" }
        XCTAssertEqual(
            state.successfulResearchStepsAfterCheckpoint,
            AgentResearchCheckpointGate.delegatedResearchWeight
        )

        for index in 0..<(AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
            - AgentResearchCheckpointGate.delegatedResearchWeight) {
            let fetch = ToolCall(
                name: ToolDefinition.webFetch.name,
                argumentsJSON: ToolArguments.json(["url": "https://example.com/\(index)"])
            )
            _ = state.recordCompletedStep(
                completed(call: fetch, stdout: "evidence \(index)"),
                workspaceRoot: root
            ) { _ in "fetch-\(index)" }
        }

        XCTAssertEqual(
            state.pendingResearchFinalizationPath(
                minimumResearchSteps: AgentResearchCheckpointGate.minimumPostCheckpointResearchSteps
            ),
            "outputs/revenue.html"
        )
    }

    func testOrdinaryDraftDoesNotArmResearchContinuation() {
        var state = AgentRunLoopState()
        state.seedArtifactVerification(userMessage: "Write outputs/report.md.")
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "Complete report",
            ])
        )

        _ = state.recordCompletedStep(
            completed(call: write, stdout: "wrote"),
            workspaceRoot: root
        ) { _ in "write" }

        XCTAssertNil(state.pendingResearchContinuationPath())
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
