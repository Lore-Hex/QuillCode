import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceSubagentRunToolIntegrationTests: XCTestCase {
    func testDefaultDelegationBudgetSupportsBoundedLongResearch() {
        XCTAssertEqual(
            WorkspaceSubagentRunToolExecutor.defaultDelegationBudget,
            .seconds(900)
        )
    }

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
        XCTAssertEqual(
            run.workers.map(\.summary),
            ["COMPLETE: Mapped the relevant files.", "COMPLETE: Focused checks passed."]
        )
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
        let marker = "PUBLIC-EVIDENCE-BEYOND-COMPACT-SUMMARY"
        let publicSummary = String(repeating: "Official source fact. ", count: 20) + marker
        let scheduler = WorkspaceSubagentScheduler(detailedWorker: { _ in
            WorkspaceSubagentWorkerResult(
                summary: publicSummary,
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

        XCTAssertTrue(resolved.result.stdout.contains(marker))
        XCTAssertEqual(resolved.result.stdout.components(separatedBy: marker).count - 1, 1)
        XCTAssertFalse(resolved.result.stdout.contains("private child detail"))
        XCTAssertFalse(resolved.result.stdout.contains("private-tool"))
    }

    func testToolOutputBoundsCombinedWorkerEvidenceWithoutDroppingWorkers() async throws {
        let root = try makeQuillCodeTestDirectory()
        let factory = testFactory(root: root, llm: ChildToolInventoryLLMClient())
        let scheduler = WorkspaceSubagentScheduler(detailedWorker: { job in
            WorkspaceSubagentWorkerResult(
                summary: "EVIDENCE-\(job.name)\n" + String(repeating: "verified fact and URL ", count: 800)
            )
        })
        let executor = WorkspaceSubagentRunToolExecutor(
            sessionFactory: factory,
            threadStore: nil,
            approvalPayloadStore: nil,
            schedulerOverride: scheduler,
            recordSink: nil
        )
        let workers = (1...6).map { index in
            ["name": "Worker \(index)", "role": "Research evidence track \(index)."]
        }
        let call = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "Research six independent evidence tracks.",
                "workers": workers,
            ])
        )

        let execution = await executor.executionOverride(call, root, ChatThread(), nil)
        let stdout = try XCTUnwrap(execution?.result.stdout)

        for index in 1...6 {
            XCTAssertTrue(stdout.contains("EVIDENCE-Worker \(index)"))
        }
        XCTAssertLessThan(stdout.count, 22_000)
    }

    func testDurableRecordSinkDoesNotAwaitRedundantAgentProgressCallback() async throws {
        let root = try makeQuillCodeTestDirectory()
        let factory = testFactory(root: root, llm: ChildToolInventoryLLMClient())
        let records = SubagentRunRecordCollector()
        let scheduler = WorkspaceSubagentScheduler(detailedWorker: { _ in
            WorkspaceSubagentWorkerResult(summary: "COMPLETE: Durable evidence retained.")
        })
        let executor = WorkspaceSubagentRunToolExecutor(
            sessionFactory: factory,
            threadStore: nil,
            approvalPayloadStore: nil,
            schedulerOverride: scheduler,
            recordSink: { record, _ in await records.append(record) }
        )
        let call = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "Return after durable worker persistence.",
                "workers": [["name": "Researcher", "role": "Retain evidence."]]
            ])
        )

        let startedAt = Date()
        let execution = await executor.executionOverride(call, root, ChatThread()) { _ in
            try? await Task.sleep(for: .milliseconds(400))
        }
        let resolved = try XCTUnwrap(execution)
        let latestStatuses = await records.latestStatuses()

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.2)
        XCTAssertEqual(resolved.thread.subagentRuns.first?.workers.map(\.status), [.completed])
        XCTAssertEqual(latestStatuses, [.completed])
    }

    func testModelAuthoredDelegationBudgetCancelsWorkersAndReturnsEvidenceToParent() async throws {
        let root = try makeQuillCodeTestDirectory()
        let factory = testFactory(root: root, llm: ChildToolInventoryLLMClient())
        let scheduler = WorkspaceSubagentScheduler(detailedWorker: { _ in
            try await Task.sleep(for: .seconds(30))
            return WorkspaceSubagentWorkerResult(summary: "Unexpected completion")
        })
        let executor = WorkspaceSubagentRunToolExecutor(
            sessionFactory: factory,
            threadStore: nil,
            approvalPayloadStore: nil,
            schedulerOverride: scheduler,
            recordSink: nil,
            delegationBudget: .milliseconds(25)
        )
        let call = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "Research within the delegated budget.",
                "workers": [["name": "Researcher", "role": "Inspect sources."]]
            ])
        )

        let startedAt = Date()
        let execution = await executor.executionOverride(call, root, ChatThread(), nil)
        let resolved = try XCTUnwrap(execution)

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
        XCTAssertTrue(resolved.result.stdout.contains("Delegation time budget reached"))
        XCTAssertTrue(resolved.result.stdout.contains("Synthesize the parent deliverable now"))
        let run = try XCTUnwrap(resolved.thread.subagentRuns.first)
        XCTAssertEqual(run.workers.map(\.status), [.cancelled])
    }

    func testDelegationBudgetReturnsWithoutWaitingForCancellationInsensitiveWorker() async throws {
        let root = try makeQuillCodeTestDirectory()
        let threadStore = SubagentThreadStore(directory: root.appendingPathComponent("children"))
        let factory = testFactory(root: root, llm: ChildToolInventoryLLMClient())
        let records = SubagentRunRecordCollector()
        let evidenceMarker = "PARTIAL-EVIDENCE-BEFORE-HARD-DEADLINE"
        let scheduler = WorkspaceSubagentScheduler(detailedWorker: { job in
            var child = ChatThread(id: job.childThreadID, title: "Subagent: \(job.name)")
            child.messages.append(ChatMessage(role: .assistant, content: evidenceMarker))
            try threadStore.save(child)
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                    continuation.resume()
                }
            }
            return WorkspaceSubagentWorkerResult(summary: "Late completion")
        })
        let executor = WorkspaceSubagentRunToolExecutor(
            sessionFactory: factory,
            threadStore: threadStore,
            approvalPayloadStore: nil,
            schedulerOverride: scheduler,
            recordSink: { record, _ in await records.append(record) },
            delegationBudget: .milliseconds(25)
        )
        let call = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "Return at the hard delegation deadline.",
                "workers": [["name": "Researcher", "role": "Ignore cancellation temporarily."]]
            ])
        )

        let startedAt = Date()
        let execution = await executor.executionOverride(call, root, ChatThread(), nil)
        let resolved = try XCTUnwrap(execution)

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.2)
        XCTAssertTrue(resolved.result.stdout.contains("Delegation time budget reached"))
        XCTAssertTrue(resolved.result.stdout.contains(evidenceMarker))
        let run = try XCTUnwrap(resolved.thread.subagentRuns.first)
        XCTAssertEqual(run.workers.map(\.status), [.cancelled])
        XCTAssertNotNil(run.finishedAt)

        try await Task.sleep(for: .milliseconds(450))
        let latestStatuses = await records.latestStatuses()
        XCTAssertEqual(latestStatuses, [.cancelled])
    }

    func testDelegationBudgetRecoversEvidenceFromCompletedWorkerCheckpoint() async throws {
        let root = try makeQuillCodeTestDirectory()
        let threadStore = SubagentThreadStore(directory: root.appendingPathComponent("children"))
        let factory = testFactory(root: root, llm: ChildToolInventoryLLMClient())
        let evidenceMarker = "VERIFIED-COMPLETED-WORKER-EVIDENCE"
        let scheduler = WorkspaceSubagentScheduler(detailedWorker: { job in
            let feedback = AgentToolFeedback(
                toolCall: ToolCall(
                    name: ToolDefinition.webFetch.name,
                    argumentsJSON: ToolArguments.json(["url": "https://example.test/evidence"])
                ),
                result: ToolResult(
                    ok: true,
                    stdout: "Fetched official source: \(evidenceMarker) at $1,799."
                )
            )
            let child = ChatThread(
                id: job.childThreadID,
                title: "Subagent: \(job.name)",
                messages: [
                    ChatMessage(role: .tool, content: try JSONHelpers.encodePretty(feedback)),
                    ChatMessage(role: .assistant, content: "COMPLETE: Verified the candidate."),
                ]
            )
            try threadStore.save(child)
            return WorkspaceSubagentWorkerResult(summary: "COMPLETE: Verified the candidate.")
        })
        let executor = WorkspaceSubagentRunToolExecutor(
            sessionFactory: factory,
            threadStore: threadStore,
            approvalPayloadStore: nil,
            schedulerOverride: scheduler,
            recordSink: { record, _ in
                if record.workers.map(\.status) == [.completed] {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            },
            delegationBudget: .milliseconds(25)
        )
        let call = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "Preserve completed evidence at the delegation deadline.",
                "workers": [["name": "Researcher", "role": "Verify the current price."]]
            ])
        )

        let execution = await executor.executionOverride(call, root, ChatThread(), nil)
        let resolved = try XCTUnwrap(execution)

        XCTAssertTrue(resolved.result.stdout.contains("Delegation time budget reached"))
        XCTAssertTrue(resolved.result.stdout.contains(evidenceMarker))
        XCTAssertTrue(resolved.result.stdout.contains("$1,799"))
        XCTAssertEqual(resolved.thread.subagentRuns.first?.workers.map(\.status), [.completed])
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
            return job.name == "Explorer"
                ? "COMPLETE: Mapped the relevant files."
                : "COMPLETE: Focused checks passed."
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

private actor SubagentRunRecordCollector {
    private var records: [SubagentRunRecord] = []

    func append(_ record: SubagentRunRecord) {
        records.append(record)
    }

    func latestStatuses() -> [SubagentStatus]? {
        records.last?.workers.map(\.status)
    }
}

private struct DelegatingParentLLMClient: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        if userMessage.contains("You are the \"Explorer\" subagent") {
            return .say("COMPLETE: Mapped the relevant files.")
        }
        if userMessage.contains("You are the \"Verifier\" subagent") {
            return .say("COMPLETE: Focused checks passed.")
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
