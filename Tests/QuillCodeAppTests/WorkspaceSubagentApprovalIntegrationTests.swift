import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceSubagentApprovalIntegrationTests: XCTestCase {
    @MainActor
    func testLegacyPausedWorkerSurvivesRelaunchAndCompletesExactApprovedTool() async throws {
        let workspace = try makeTempDirectory()
        let sessions = workspace.appendingPathComponent("subagent-sessions")
        let output = workspace.appendingPathComponent("approved.txt")
        let actions = LegacySubagentApprovalActionQueue(actions: [
            .tool(ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "approved.txt",
                    "content": "written exactly once"
                ])
            )),
            .say("Approved worker finished.")
        ])
        let runner = AgentRunner(
            llm: LegacySubagentApprovalScriptedLLMClient(actions: actions),
            safety: StaticSafetyReviewer()
        )
        let model = QuillCodeWorkspaceModel(
            activity: ActivityState(isVisible: true),
            runner: runner,
            subagentSessionStoreDirectory: sessions
        )
        _ = model.newChat()
        model.setMode(.review)

        await model.runSubagentSlashCommand(
            WorkspaceSubagentRunRequest(
                objective: "Write a reviewed file",
                workers: [WorkspaceSubagentWorkerRequest(name: "Builder", role: "Write the requested file")]
            ),
            originalPrompt: "/subagents Write a reviewed file | Builder: Write the requested file",
            workspaceRoot: workspace
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let pausedItem = try XCTUnwrap(model.surface().activity.subagents.first)
        XCTAssertEqual(pausedItem.statusLabel, "Needs approval")
        let commandID = try XCTUnwrap(pausedItem.actions.first { $0.title == "Approve" }?.commandID)
        let command = try XCTUnwrap(WorkspaceSubagentApprovalCommand(commandID: commandID))
        XCTAssertNoThrow(try WorkspaceSubagentSessionStore(directory: sessions).load(command.runID))

        // Recreate the workspace model to prove migration-era actions still resume from their
        // private journal rather than process-local scheduler state.
        let relaunched = QuillCodeWorkspaceModel(
            root: model.root,
            activity: ActivityState(isVisible: true),
            runner: runner,
            subagentSessionStoreDirectory: sessions
        )
        await relaunched.resolveSubagentApproval(command, workspaceRoot: workspace)

        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "written exactly once")
        XCTAssertThrowsError(try WorkspaceSubagentSessionStore(directory: sessions).load(command.runID))
        let completedItem = try XCTUnwrap(relaunched.surface().activity.subagents.first)
        XCTAssertEqual(completedItem.statusLabel, "Done")
        XCTAssertTrue(completedItem.actions.isEmpty)
        XCTAssertEqual(
            relaunched.selectedThread?.messages.filter { $0.role == .user }.count,
            1,
            "Approval continuation must not duplicate the original delegated prompt."
        )
        XCTAssertTrue(completedItem.transcript.contains {
            $0.kind == .tool && $0.statusLabel == "Done"
        })
        XCTAssertTrue(completedItem.transcript.contains {
            $0.kind == .assistant && $0.detail.contains("Approved worker finished")
        })
    }

    @MainActor
    func testApprovalExecutesProtectedCallAndResumesExactHiddenChild() async throws {
        let fixture = try makeFixture()
        let action = fixture.action(kind: .approve)

        let didRun = await fixture.model.approveSubagentToolCardAndResume(
            action,
            workspaceRoot: fixture.workspaceRoot
        )

        XCTAssertTrue(didRun)
        XCTAssertEqual(
            try String(contentsOf: fixture.workspaceRoot.appendingPathComponent("approved.txt")),
            "unredacted payload\n"
        )
        let child = try fixture.childStore.load(fixture.childThreadID)
        XCTAssertTrue(child.events.contains { $0.kind == .approvalDecided })
        XCTAssertTrue(child.events.contains { $0.kind == .toolCompleted })
        XCTAssertEqual(child.messages.last(where: { $0.role == .assistant })?.content, "Finished after approval.")
        let worker = try XCTUnwrap(fixture.model.root.threads
            .first(where: { $0.id == fixture.parentThreadID })?
            .subagentRuns.first?
            .workers.first)
        XCTAssertEqual(worker.status, .completed)
        XCTAssertNil(worker.pendingApproval)
        XCTAssertThrowsError(try fixture.payloadStore.load(fixture.payloadKey))

        // A delayed second tap cannot replay the already-consumed raw call.
        let replayed = await fixture.model.approveSubagentToolCardAndResume(
            action,
            workspaceRoot: fixture.workspaceRoot
        )
        XCTAssertFalse(replayed)
    }

    @MainActor
    func testDenyRecordsChildDecisionWithoutExecutingAndCancelsDependents() async throws {
        let fixture = try makeFixture(includesDependent: true)
        let action = fixture.action(kind: .deny)

        let didRun = await fixture.model.approveSubagentToolCardAndResume(
            action,
            workspaceRoot: fixture.workspaceRoot
        )

        XCTAssertTrue(didRun)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.workspaceRoot.appendingPathComponent("approved.txt").path
        ))
        let child = try fixture.childStore.load(fixture.childThreadID)
        XCTAssertTrue(child.events.contains { $0.kind == .approvalDecided })
        XCTAssertEqual(child.messages.last?.content, "Skipped \(ToolDefinition.fileWrite.name).")
        let workers = try XCTUnwrap(fixture.model.root.threads
            .first(where: { $0.id == fixture.parentThreadID })?
            .subagentRuns.first?
            .workers)
        XCTAssertEqual(workers.map(\.status), [.cancelled, .cancelled])
        XCTAssertThrowsError(try fixture.payloadStore.load(fixture.payloadKey))
    }

    @MainActor
    func testDenyCanBePersistedBeforeItsGraphContinuationRuns() async throws {
        let fixture = try makeFixture(includesDependent: true)
        let action = fixture.action(kind: .deny)
        let target = try XCTUnwrap(action.subagentTarget)

        XCTAssertTrue(fixture.model.recordSubagentDenial(action))

        var workers = try XCTUnwrap(fixture.model.root.threads
            .first(where: { $0.id == fixture.parentThreadID })?
            .subagentRuns.first?
            .workers)
        XCTAssertEqual(workers.map(\.status), [.cancelled, .blocked])
        XCTAssertNil(workers[0].pendingApproval)
        XCTAssertTrue(try fixture.childStore.load(fixture.childThreadID).events.contains {
            $0.kind == .approvalDecided
        })
        XCTAssertThrowsError(try fixture.payloadStore.load(fixture.payloadKey))

        let resumed = await fixture.model.resumeSubagentRunAfterDecision(
            target,
            workspaceRoot: fixture.workspaceRoot
        )
        XCTAssertTrue(resumed)
        workers = try XCTUnwrap(fixture.model.root.threads
            .first(where: { $0.id == fixture.parentThreadID })?
            .subagentRuns.first?
            .workers)
        XCTAssertEqual(workers.map(\.status), [.cancelled, .cancelled])
    }

    @MainActor
    func testApprovalTargetIgnoresCurrentlySelectedThread() async throws {
        let fixture = try makeFixture()
        XCTAssertNotEqual(fixture.model.root.selectedThreadID, fixture.parentThreadID)

        let didRun = await fixture.model.approveSubagentToolCardAndResume(
            fixture.action(kind: .approve),
            workspaceRoot: fixture.workspaceRoot
        )
        XCTAssertTrue(didRun)

        XCTAssertEqual(fixture.model.root.selectedThreadID, fixture.unrelatedThreadID)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.workspaceRoot.appendingPathComponent("approved.txt").path
        ))
    }

    @MainActor
    private func makeFixture(includesDependent: Bool = false) throws -> SubagentApprovalFixture {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let persistenceRoot = try makeQuillCodeTestDirectory()
        let childStore = SubagentThreadStore(directory: persistenceRoot.appendingPathComponent("children"))
        let payloadStore = SubagentApprovalPayloadStore(directory: persistenceRoot.appendingPathComponent("payloads"))
        let parentThreadID = UUID()
        let unrelatedThreadID = UUID()
        let childThreadID = UUID()
        let runID = UUID()
        let workerID = "writer-worker"
        let payloadKey = UUID()
        let requestID = "approval-write"
        let rawCall = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "approved.txt",
                "content": "unredacted payload\n"
            ])
        )
        let presentationCall = ToolCall(
            id: rawCall.id,
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "approved.txt",
                "content": "[redacted]"
            ])
        )
        let request = ApprovalRequest(
            id: requestID,
            toolCall: presentationCall,
            toolDefinition: ToolDefinition.fileWrite,
            reason: "Writing this file needs approval."
        )
        let child = ChatThread(
            id: childThreadID,
            title: "Subagent: Writer",
            mode: .review,
            messages: [ChatMessage(role: .user, content: "Create the approved file.")],
            events: [ThreadEvent(
                kind: .approvalRequested,
                summary: request.reason,
                payloadJSON: try JSONHelpers.encodePretty(request)
            )]
        )
        try childStore.save(child)
        try payloadStore.save(rawCall, key: payloadKey)

        let worker = SubagentWorkerRecord(
            id: workerID,
            childThreadID: childThreadID,
            name: "Writer",
            role: "create a file",
            status: .awaitingApproval,
            summary: request.reason,
            pendingApproval: SubagentPendingApproval(
                requestID: requestID,
                generation: 1,
                payloadKey: payloadKey
            )
        )
        var workers = [worker]
        if includesDependent {
            workers.append(SubagentWorkerRecord(
                id: "verifier-worker",
                childThreadID: UUID(),
                dependencyIDs: [workerID],
                name: "Verifier",
                role: "verify the file",
                status: .blocked,
                summary: "Waiting on Writer"
            ))
        }
        let run = SubagentRunRecord(id: runID, objective: "Create and verify a file", workers: workers)
        let parent = ChatThread(id: parentThreadID, title: "Parent", subagentRuns: [run])
        let unrelated = ChatThread(id: unrelatedThreadID, title: "Visible task")
        let parentStore = JSONThreadStore(directory: persistenceRoot.appendingPathComponent("parents"))
        try parentStore.save(parent)
        try parentStore.save(unrelated)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [parent, unrelated],
                selectedThreadID: unrelatedThreadID
            ),
            runner: AgentRunner(
                llm: SubagentApprovalContinuationClient(),
                safety: SubagentApprovalSafetyReviewer()
            ),
            threadStore: parentStore,
            subagentThreadStore: childStore,
            subagentApprovalPayloadStore: payloadStore
        )
        return SubagentApprovalFixture(
            model: model,
            workspaceRoot: workspaceRoot,
            childStore: childStore,
            payloadStore: payloadStore,
            parentThreadID: parentThreadID,
            unrelatedThreadID: unrelatedThreadID,
            childThreadID: childThreadID,
            runID: runID,
            workerID: workerID,
            payloadKey: payloadKey,
            requestID: requestID
        )
    }
}

private actor LegacySubagentApprovalActionQueue {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func next() -> AgentAction {
        guard !actions.isEmpty else { return .say("Done.") }
        return actions.removeFirst()
    }
}

private struct LegacySubagentApprovalScriptedLLMClient: LLMClient {
    let actions: LegacySubagentApprovalActionQueue

    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        await actions.next()
    }
}

@MainActor
private struct SubagentApprovalFixture {
    let model: QuillCodeWorkspaceModel
    let workspaceRoot: URL
    let childStore: SubagentThreadStore
    let payloadStore: SubagentApprovalPayloadStore
    let parentThreadID: UUID
    let unrelatedThreadID: UUID
    let childThreadID: UUID
    let runID: UUID
    let workerID: String
    let payloadKey: UUID
    let requestID: String

    func action(kind: ToolCardActionKind) -> ToolCardActionSurface {
        ToolCardActionSurface(
            title: kind == .approve ? "Run" : "Skip",
            kind: kind,
            requestID: requestID,
            style: kind == .approve ? .primary : .secondary,
            subagentTarget: WorkspaceSubagentApprovalTarget(
                parentThreadID: parentThreadID,
                runID: runID,
                workerID: workerID,
                generation: 1
            )
        )
    }
}

private struct SubagentApprovalContinuationClient: LLMClient {
    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        .say("Finished after approval.")
    }
}

private struct SubagentApprovalSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        SafetyReview(verdict: .approve, rationale: "Approved in test.", userIntentMatched: true)
    }
}
