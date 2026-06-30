import XCTest
import QuillCodeCore
import QuillCodeTools
import QuillCodeAgent
@testable import QuillCodeApp

/// Scripts an exact sequence of agent actions for a resumed run (ignores intent text).
private actor ScriptedActionState {
    private var actions: [AgentAction]
    init(_ actions: [AgentAction]) { self.actions = actions }
    func next() -> AgentAction {
        guard !actions.isEmpty else { return .say("done") }
        return actions.removeFirst()
    }
}

private struct ScriptedLLMClient: LLMClient {
    let state: ScriptedActionState
    init(_ actions: [AgentAction]) { state = ScriptedActionState(actions) }
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        await state.next()
    }
}

@MainActor
final class WorkspaceToolCardIntegrationTests: XCTestCase {
    func testToolCardsRepresentActionableApprovalReview() throws {
        let call = ToolCall(
            id: "approval-tool",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-request",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let event = ThreadEvent(
            kind: .approvalRequested,
            summary: "clarify: needs target",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )
        let thread = ChatThread(events: [event])

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].title, ToolDefinition.shellRun.name)
        XCTAssertEqual(cards[0].status, .review)
        XCTAssertFalse(cards[0].isExpanded)
        XCTAssertEqual(cards[0].density, .peek)
        XCTAssertEqual(cards[0].reviewState, .ready)
        XCTAssertEqual(cards[0].inputJSON, ToolArguments.json(["cmd": "whoami"]))
        XCTAssertEqual(cards[0].actions.map(\.title), ["Run", "Edit", "Skip"])
    }

    func testToolCardApprovalActionRecordsDecisionAndRunsTool() throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            id: "approval-tool-run",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "approval-run",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let thread = ChatThread(events: [
            ThreadEvent(
                kind: .approvalRequested,
                summary: "review required",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let didRun = model.runToolCardAction(ToolCardActionSurface(
            title: "Run",
            kind: .approve,
            requestID: "approval-run",
            style: .primary
        ), workspaceRoot: root)

        XCTAssertTrue(didRun)
        let events = try XCTUnwrap(model.selectedThread?.events)
        XCTAssertTrue(events.contains { $0.kind == .approvalDecided })
        XCTAssertTrue(events.contains { $0.kind == .toolQueued })
        XCTAssertTrue(events.contains { $0.kind == .toolCompleted })
        let cards = model.currentToolCards
        XCTAssertTrue(cards.contains { $0.status == .done && $0.subtitle == "Approved · whoami" })
        XCTAssertTrue(cards.contains { $0.title == ToolDefinition.shellRun.name && $0.outputJSON?.contains("exitCode") == true })
    }

    func testApprovingWhilePlanningRunsTheToolAndStaysInPlanMode() throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            id: "plan-approval-tool-run",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let request = ApprovalRequest(
            id: "plan-approval-run",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "Planning — approve the proposed change to apply it and start executing.",
            recommendedVerdict: .clarify
        )
        let thread = ChatThread(mode: .plan, events: [
            ThreadEvent(
                kind: .approvalRequested,
                summary: "planning",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let didRun = model.runToolCardAction(ToolCardActionSurface(
            title: "Approve",
            kind: .approve,
            requestID: "plan-approval-run",
            style: .primary
        ), workspaceRoot: root)

        XCTAssertTrue(didRun)
        // The held tool runs, but the thread STAYS in Plan mode — approving one step does not
        // flip to autonomous execution, so the next mutation is gated for approval again.
        XCTAssertEqual(model.selectedThread?.mode, .plan)
        let events = try XCTUnwrap(model.selectedThread?.events)
        XCTAssertTrue(events.contains { $0.kind == .toolCompleted })
    }

    private func approvalRequestCount(_ model: QuillCodeWorkspaceModel) -> Int {
        model.selectedThread?.events.filter { $0.kind == .approvalRequested }.count ?? 0
    }

    private func planThread(
        heldCommand: String,
        userMessage: String?,
        requestID: String = "plan-approval"
    ) throws -> ChatThread {
        let held = ToolCall(
            id: "held-\(requestID)",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": heldCommand])
        )
        let request = ApprovalRequest(
            id: requestID,
            toolCall: held,
            toolDefinition: ToolDefinition.shellRun,
            reason: "Planning — approve the proposed change to apply it and start executing.",
            recommendedVerdict: .clarify
        )
        return ChatThread(
            mode: .plan,
            messages: userMessage.map { [ChatMessage(role: .user, content: $0)] } ?? [],
            events: [
                ThreadEvent(
                    kind: .approvalRequested,
                    summary: "planning",
                    payloadJSON: try JSONHelpers.encodePretty(request)
                )
            ]
        )
    }

    private func approve(_ requestID: String) -> ToolCardActionSurface {
        ToolCardActionSurface(title: "Approve", kind: .approve, requestID: requestID, style: .primary)
    }

    func testApprovingAPlanBlockResumesTheAgentToProposeTheNextGatedStep() async throws {
        let root = try makeTempDirectory()
        let thread = try planThread(heldCommand: "touch step-one.txt", userMessage: "run the plan")
        // The resumed run (still in Plan mode) proposes the next mutating step.
        let followUp = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch step-two.txt"])
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            runner: AgentRunner(llm: ScriptedLLMClient([.tool(followUp), .say("Plan complete.")]))
        )

        _ = await model.approveToolCardAndResume(approve("plan-approval"), workspaceRoot: root)

        // The held tool ran, and the thread STAYS in Plan mode.
        XCTAssertEqual(model.selectedThread?.mode, .plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("step-one.txt").path))
        // The agent RESUMED and proposed the next step — but it is GATED, not auto-run: the file
        // is absent and a second approval request is surfaced for the user to approve.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("step-two.txt").path))
        XCTAssertEqual(approvalRequestCount(model), 2)
    }

    func testResumedPlanStepIsGatedNotAutoRunEvenForARelativeDestructiveCommand() async throws {
        // The killer: a resumed step is gated by Plan mode regardless of its shape — a RELATIVE
        // `rm -rf keep` (which the .auto hard-deny list does NOT catch) is still blocked, proven
        // against the filesystem. This exercises the Plan gate, not a `"rm -rf /"` substring.
        let root = try makeTempDirectory()
        let victim = root.appendingPathComponent("keep")
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        try "data".write(to: victim.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let thread = try planThread(heldCommand: "touch step-one.txt", userMessage: "run the plan")
        let destructive = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "rm -rf keep"])
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            runner: AgentRunner(llm: ScriptedLLMClient([.tool(destructive), .say("never reached")]))
        )

        _ = await model.approveToolCardAndResume(approve("plan-approval"), workspaceRoot: root)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("step-one.txt").path))
        // The resume REACHED the destructive step (a second approval request was surfaced for it)…
        XCTAssertEqual(approvalRequestCount(model), 2)
        XCTAssertTrue(
            model.selectedThread?.events.contains {
                $0.kind == .approvalRequested && ($0.payloadJSON?.contains("rm -rf keep") ?? false)
            } == true
        )
        // …but it was BLOCKED, not run — the directory survives on disk.
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.appendingPathComponent("file.txt").path))
    }

    func testApprovingAPlanBlockWithoutAUserMessageDoesNotResume() async throws {
        // No user request on record → no intent to continue → the agent must NOT resume (the guard
        // that keeps an empty/stale prompt from driving the plan).
        let root = try makeTempDirectory()
        let thread = try planThread(heldCommand: "touch step-one.txt", userMessage: nil)
        let followUp = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch step-two.txt"])
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            runner: AgentRunner(llm: ScriptedLLMClient([.tool(followUp), .say("should not run")]))
        )

        _ = await model.approveToolCardAndResume(approve("plan-approval"), workspaceRoot: root)

        XCTAssertEqual(model.selectedThread?.mode, .plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("step-one.txt").path))
        // No resume fired — the scripted follow-up never ran and no new approval was surfaced.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("step-two.txt").path))
        XCTAssertEqual(approvalRequestCount(model), 1)
    }

    func testResumeIsSkippedWhenTheSelectedThreadIsNotTheApprovedOne() async throws {
        // The async resume is pinned to the approved thread: if the user switched threads, the
        // resume must NOT continue the now-selected plan (no wrong-thread continuation).
        let root = try makeTempDirectory()
        let thread = try planThread(heldCommand: "touch step-one.txt", userMessage: "run the plan")
        let followUp = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch step-two.txt"])
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            runner: AgentRunner(llm: ScriptedLLMClient([.tool(followUp), .say("should not run")]))
        )

        // Resume pinned to a DIFFERENT thread id than the selected one → must no-op.
        await model.resumeAgentAfterApproval(workspaceRoot: root, expectedThreadID: UUID())

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("step-two.txt").path))
        XCTAssertEqual(approvalRequestCount(model), 1)
    }

    func testToolCardEditActionPreloadsComposerWithoutDecidingOrRunningTool() throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            id: "approval-tool-edit",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "ls -la"])
        )
        let request = ApprovalRequest(
            id: "approval-edit",
            toolCall: call,
            toolDefinition: ToolDefinition.shellRun,
            reason: "review required"
        )
        let thread = ChatThread(events: [
            ThreadEvent(
                kind: .approvalRequested,
                summary: "review required",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let didEdit = model.runToolCardAction(ToolCardActionSurface(
            title: "Edit",
            kind: .edit,
            requestID: "approval-edit",
            style: .secondary
        ), workspaceRoot: root)

        XCTAssertTrue(didEdit)
        XCTAssertEqual(model.composer.draft, "Run ls -la")
        let events = try XCTUnwrap(model.selectedThread?.events)
        XCTAssertFalse(events.contains { $0.kind == .approvalDecided })
        XCTAssertFalse(events.contains { $0.kind == .toolQueued })
        XCTAssertFalse(events.contains { $0.kind == .toolCompleted })
    }

    func testToolCardsRepresentStoppedActiveToolAsFailed() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "sleep 10"])
        )
        let callJSON = try JSONHelpers.encodePretty(call)
        let thread = ChatThread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(
                kind: .toolFailed,
                summary: "Stopped by user",
                payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#
            ),
            ThreadEvent(kind: .notice, summary: "Stopped by user")
        ])

        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()
        let timeline = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems()

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].status, .failed)
        XCTAssertEqual(cards[0].subtitle, "Failed · sleep 10")
        XCTAssertEqual(cards[0].density, .expanded)
        XCTAssertEqual(cards[0].outputJSON, #"{"ok":false,"error":"Stopped by user"}"#)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.status, .failed)
        XCTAssertEqual(timeline.compactMap(\.toolCard).first?.density, .expanded)
    }
}
