import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceSubagentRunToolIntegrationTests: XCTestCase {
    func testModelAuthoredDelegationRunsWorkersAndReturnsToParentInOneTurn() async throws {
        let root = try makeQuillCodeTestDirectory()
        let threadStore = SubagentThreadStore(directory: root.appendingPathComponent("children"))
        let payloadStore = SubagentApprovalPayloadStore(directory: root.appendingPathComponent("approvals"))
        let factory = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(
                llm: DelegatingParentLLMClient(),
                safety: RunSubagentsApprovingSafetyReviewer(),
                maxToolSteps: 4
            ),
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            subagentThreadStore: threadStore,
            subagentApprovalPayloadStore: payloadStore,
            workspaceRoot: root
        )
        let parent = ChatThread(title: "Parallel review", mode: .auto)

        let result = try await factory.makeSession(
            prompt: "Use two subagents to inspect and verify this change.",
            thread: parent
        ).run()

        let run = try XCTUnwrap(result.thread.subagentRuns.first)
        XCTAssertEqual(run.workers.map(\.name), ["Explorer", "Verifier"])
        XCTAssertEqual(run.workers.map(\.status), [.completed, .completed])
        XCTAssertEqual(run.workers.map(\.summary), ["Mapped the relevant files.", "Focused checks passed."])
        XCTAssertEqual(
            result.thread.messages.last(where: { $0.role == .assistant })?.content,
            "The parallel review is complete."
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .toolCompleted && $0.summary == "host.subagents.run completed"
        })
        let children = try run.workers.map { try threadStore.load($0.childThreadID) }
        XCTAssertEqual(children.count, 2)
        XCTAssertTrue(children.allSatisfy { $0.messages.contains(where: { $0.role == .assistant }) })
    }

    func testToolOutputExposesSummariesWithoutPrivateChildTranscript() async throws {
        let root = try makeQuillCodeTestDirectory()
        let factory = testFactory(root: root, llm: ChildToolInventoryLLMClient())
        let scheduler = WorkspaceSubagentScheduler(detailedWorker: { _ in
            WorkspaceSubagentWorkerResult(
                summary: "Public worker summary.",
                transcript: [
                    SubagentTranscriptEntry(
                        id: "private-tool",
                        kind: .tool,
                        title: "Private tool",
                        detail: "private child detail",
                        statusLabel: "Done"
                    )
                ]
            )
        })
        let executor = WorkspaceSubagentRunToolExecutor(
            sessionFactory: factory,
            threadStore: nil,
            approvalPayloadStore: nil,
            schedulerOverride: scheduler,
            recordSink: nil
        )
        let call = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "Inspect privately.",
                "workers": [["name": "Explorer", "role": "Inspect files."]]
            ])
        )

        let execution = await executor.executionOverride(call, root, ChatThread(), nil)
        let resolved = try XCTUnwrap(execution)

        XCTAssertTrue(resolved.result.stdout.contains("Public worker summary."))
        XCTAssertFalse(resolved.result.stdout.contains("private child detail"))
        XCTAssertFalse(resolved.result.stdout.contains("private-tool"))
    }

    func testChildSessionCannotStartAnIndependentSubagentTree() async throws {
        let root = try makeQuillCodeTestDirectory()
        let factory = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(
                llm: ChildToolInventoryLLMClient(),
                safety: RunSubagentsApprovingSafetyReviewer()
            ),
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: root
        )
        let worker = AgentWorkspaceSubagentWorker(
            sessionFactory: factory,
            parentThread: ChatThread()
        )

        let summary = try await worker.run(WorkspaceSubagentJob(name: "Explorer", role: "Inspect tools"))

        XCTAssertEqual(summary, "Nested delegation tool unavailable as expected.")
    }

    func testModelAuthoredRunPersistsManifestWhileWorkersAreStillRunning() async throws {
        let root = try makeQuillCodeTestDirectory()
        let parentStore = JSONThreadStore(directory: root.appendingPathComponent("threads"))
        let model = QuillCodeWorkspaceModel(
            runner: AgentRunner(
                llm: DelegatingParentLLMClient(),
                safety: RunSubagentsApprovingSafetyReviewer()
            ),
            threadStore: parentStore
        )
        model.subagentSchedulerOverride = WorkspaceSubagentScheduler { job in
            try await Task.sleep(for: .milliseconds(250))
            return job.name == "Explorer" ? "Mapped the relevant files." : "Focused checks passed."
        }
        let parentThreadID = model.newChat()
        model.setDraft("Use two subagents to inspect and verify this change.")

        let task = Task { await model.submitComposer(workspaceRoot: root) }
        try await waitUntil(timeoutSeconds: 1) {
            guard let persisted = try? parentStore.load(parentThreadID),
                  let run = persisted.subagentRuns.first
            else { return false }
            return run.workers.contains { $0.status == .queued || $0.status == .running }
        }
        await task.value

        let persisted = try parentStore.load(parentThreadID)
        XCTAssertEqual(persisted.subagentRuns.first?.workers.map(\.status), [.completed, .completed])
        XCTAssertEqual(
            persisted.messages.last(where: { $0.role == .assistant })?.content,
            "The parallel review is complete."
        )
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private struct DelegatingParentLLMClient: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        if userMessage.contains("You are the \"Explorer\" subagent") {
            return .say("Mapped the relevant files.")
        }
        if userMessage.contains("You are the \"Verifier\" subagent") {
            return .say("Focused checks passed.")
        }
        if thread.messages.contains(where: { $0.role == .tool }) {
            return .say("The parallel review is complete.")
        }
        XCTAssertTrue(tools.contains { $0.name == ToolDefinition.subagentsRun.name })
        XCTAssertFalse(tools.contains { $0.name == ToolDefinition.subagentsUpdate.name })
        return .tool(ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "Inspect and verify this change.",
                "workers": [
                    ["name": "Explorer", "role": "Map the relevant files."],
                    ["name": "Verifier", "role": "Run focused checks."]
                ]
            ])
        ))
    }
}

private func testFactory(root: URL, llm: any LLMClient) -> WorkspaceAgentSendSessionFactory {
    WorkspaceAgentSendSessionFactory(
        baseRunner: AgentRunner(llm: llm, safety: RunSubagentsApprovingSafetyReviewer()),
        selectedProject: nil,
        config: AppConfig(),
        browser: BrowserState(),
        browserToolOverride: nil,
        computerUseBackend: nil,
        globalMemoryDirectory: nil,
        mcpToolDefinitions: [],
        mcpToolExecutionOverride: nil,
        sshRemoteShellExecutor: SSHRemoteShellExecutor(),
        workspaceRoot: root
    )
}

private struct ChildToolInventoryLLMClient: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        tools.contains { $0.name == ToolDefinition.subagentsRun.name }
            ? .say("Nested delegation tool was unexpectedly available.")
            : .say("Nested delegation tool unavailable as expected.")
    }
}

private struct RunSubagentsApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        _ = context
        return SafetyReview(
            verdict: .approve,
            rationale: "Test-approved delegated workflow.",
            userIntentMatched: true
        )
    }
}
