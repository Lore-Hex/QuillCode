import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceFollowUpQueueIntegrationTests: XCTestCase {
    // MARK: enqueue / delete (unit-ish, on the live model)

    func testEnqueueFollowUpAppendsToSelectedThreadAndClearsDraft() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        model.setDraft("queued while running")

        XCTAssertTrue(model.enqueueFollowUp("queued while running"))

        XCTAssertEqual(model.followUpQueue.map(\.text), ["queued while running"])
        XCTAssertEqual(model.selectedThread?.followUpQueue.map(\.text), ["queued while running"])
        XCTAssertEqual(model.composer.draft, "", "enqueuing clears the composer draft")
    }

    func testEnqueueFollowUpIgnoresEmptyAndWhitespace() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()

        XCTAssertFalse(model.enqueueFollowUp("   \n "))
        XCTAssertTrue(model.followUpQueue.isEmpty)
    }

    func testEnqueueFollowUpPreservesFIFOOrder() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()

        XCTAssertTrue(model.enqueueFollowUp("one"))
        XCTAssertTrue(model.enqueueFollowUp("two"))
        XCTAssertTrue(model.enqueueFollowUp("three"))

        XCTAssertEqual(model.followUpQueue.map(\.text), ["one", "two", "three"])
    }

    func testDeleteFollowUpRemovesByID() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        _ = model.enqueueFollowUp("keep")
        _ = model.enqueueFollowUp("drop")
        let dropID = try XCTUnwrap(model.followUpQueue.first { $0.text == "drop" }?.id)

        model.deleteFollowUp(dropID)

        XCTAssertEqual(model.followUpQueue.map(\.text), ["keep"])
    }

    func testEnqueueFollowUpPersistsWithThread() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let model = QuillCodeWorkspaceModel(threadStore: store)
        let threadID = model.newChat()

        _ = model.enqueueFollowUp("persisted follow-up")

        // Reload straight from disk: the queue survives independently of the in-memory model.
        let reloaded = try store.load(threadID)
        XCTAssertEqual(reloaded.followUpQueue.map(\.text), ["persisted follow-up"])
    }

    // MARK: submit-during-run enqueues (functional) + drains (integration)

    func testSubmitDuringRunEnqueuesThenDrainsAsNextTurn() async throws {
        let root = try makeTempDirectory()
        let gate = LLMGate()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: GatedSayLLMClient(gate: gate)))

        model.setDraft("first turn")
        let task = Task { await model.submitComposer(workspaceRoot: root) }

        // Turn 1 is in flight (composer shows sending) — the composer is NOT locked: a submit now
        // enqueues instead of being rejected.
        try await waitUntil(timeoutSeconds: 2) { model.composer.isSending }
        XCTAssertTrue(model.enqueueFollowUp("second turn"))
        XCTAssertEqual(model.followUpQueue.map(\.text), ["second turn"])

        // Release turn 1; the drain loop pops "second turn" and runs it as the next turn.
        gate.open()
        await task.value

        XCTAssertFalse(model.composer.isSending)
        XCTAssertTrue(model.followUpQueue.isEmpty, "the queue drains fully")
        let userTurns = model.selectedThread?.messages.filter { $0.role == .user }.map(\.content)
        XCTAssertEqual(userTurns, ["first turn", "second turn"], "queued item became the next turn, once")
    }

    func testSeededQueueDrainsEveryItemExactlyOnceInOrder() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        // Seed the queue as if these were submitted during an earlier run.
        _ = model.enqueueFollowUp("bravo")
        _ = model.enqueueFollowUp("charlie")

        model.setDraft("alpha")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertTrue(model.followUpQueue.isEmpty)
        let userTurns = model.selectedThread?.messages.filter { $0.role == .user }.map(\.content)
        XCTAssertEqual(userTurns, ["alpha", "bravo", "charlie"])
    }

    func testFollowUpDeletedBeforeDrainIsNeverSent() async throws {
        let root = try makeTempDirectory()
        let gate = LLMGate()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: GatedSayLLMClient(gate: gate)))

        model.setDraft("first turn")
        let task = Task { await model.submitComposer(workspaceRoot: root) }
        try await waitUntil(timeoutSeconds: 2) { model.composer.isSending }

        _ = model.enqueueFollowUp("keep me")
        _ = model.enqueueFollowUp("delete me")
        let deleteID = try XCTUnwrap(model.followUpQueue.first { $0.text == "delete me" }?.id)
        model.deleteFollowUp(deleteID)

        gate.open()
        await task.value

        let userTurns = model.selectedThread?.messages.filter { $0.role == .user }.map(\.content)
        XCTAssertEqual(userTurns, ["first turn", "keep me"], "the deleted item is never sent")
        XCTAssertTrue(model.followUpQueue.isEmpty)
    }

    func testCancelledRunHaltsDrainAndPreservesQueue() async throws {
        let root = try makeTempDirectory()
        let gate = LLMGate()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: GatedSayLLMClient(gate: gate)))

        model.setDraft("first turn")
        let task = Task { await model.submitComposer(workspaceRoot: root) }
        try await waitUntil(timeoutSeconds: 2) { model.composer.isSending }

        _ = model.enqueueFollowUp("should survive stop")

        // Stop the run: the drain must NOT flush the queue — remaining items stay for the user.
        task.cancel()
        gate.open()
        await task.value

        XCTAssertEqual(model.root.topBar.agentStatus, "Stopped")
        XCTAssertEqual(model.followUpQueue.map(\.text), ["should survive stop"])
        let userTurns = model.selectedThread?.messages.filter { $0.role == .user }.map(\.content)
        XCTAssertEqual(userTurns, ["first turn"], "the queued item was not sent after a Stop")
    }

    // MARK: approval gate — the drain must NOT run past an undecided Plan-mode approval

    func testFollowUpDoesNotDrainPastUndecidedPlanApproval() async throws {
        let root = try makeTempDirectory()
        let gate = LLMGate()
        // Plan mode: the first turn proposes a MUTATING tool, which Plan mode gates for approval.
        // The agent returns .completed (blocked on approval), so the drain must NOT proceed — it
        // must key off the undecided approval, not merely "the turn returned".
        let mutating = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch mutating-step.txt"])
        )
        let planThread = ChatThread(mode: .plan)
        let threadID = planThread.id
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [planThread], selectedThreadID: threadID),
            runner: AgentRunner(llm: GatedScriptedLLMClient(gate: gate, actions: [.tool(mutating)]))
        )

        model.setDraft("propose a mutating step")
        let task = Task { await model.submitComposer(workspaceRoot: root) }
        try await waitUntil(timeoutSeconds: 2) { model.composer.isSending }

        // Queue a follow-up while the plan turn is in flight.
        XCTAssertTrue(model.enqueueFollowUp("queued while gated"))

        gate.open()
        await task.value

        // The plan turn blocked on approval. The follow-up must still be queued (NOT drained past
        // the open gate), and the held tool must not have run.
        XCTAssertEqual(model.followUpQueue.map(\.text), ["queued while gated"], "queue must wait behind the gate")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("mutating-step.txt").path),
            "the gated tool must not have run"
        )
        // The approval gate is live and approvable: exactly one undecided request on the run thread,
        // and no queued follow-up leaked into the transcript as a user turn.
        let runThread = try XCTUnwrap(model.root.threads.first { $0.id == threadID })
        XCTAssertEqual(WorkspaceApprovalActionPlanner.undecidedRequests(in: runThread).count, 1)
        let userTurns = runThread.messages.filter { $0.role == .user }.map(\.content)
        XCTAssertEqual(userTurns, ["propose a mutating step"], "the queued item did not become a turn")
    }

    func testApprovingGatedPlanTurnThenDrainsQueueExactlyOnce() async throws {
        let root = try makeTempDirectory()
        let gate = LLMGate()
        let mutating = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch mutating-step.txt"])
        )
        // Turn 1: .tool(mutating) → gated. Resume (after approval): .say (plan done, no new gate).
        // Drained follow-up turn: .say (completes). So the queue drains exactly once, after approval.
        let planThread = ChatThread(mode: .plan)
        let threadID = planThread.id
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [planThread], selectedThreadID: threadID),
            runner: AgentRunner(llm: GatedScriptedLLMClient(
                gate: gate,
                actions: [.tool(mutating), .say("plan step done"), .say("follow-up handled")]
            ))
        )

        model.setDraft("propose a mutating step")
        let task = Task { await model.submitComposer(workspaceRoot: root) }
        try await waitUntil(timeoutSeconds: 2) { model.composer.isSending }
        XCTAssertTrue(model.enqueueFollowUp("queued while gated"))
        gate.open()
        await task.value

        // Precondition: still gated, queue intact.
        XCTAssertEqual(model.followUpQueue.map(\.text), ["queued while gated"])
        let requestID = try XCTUnwrap(
            WorkspaceApprovalActionPlanner.undecidedRequests(in: model.selectedThread).first?.id
        )

        // Approve the held tool → resume drives the plan to completion → the queue now drains.
        _ = await model.decidePendingApproval(requestID: requestID, approve: true, workspaceRoot: root)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("mutating-step.txt").path),
            "the approved tool ran"
        )
        XCTAssertTrue(model.followUpQueue.isEmpty, "the queue drains after the approved turn completes")
        let userTurns = model.selectedThread?.messages.filter { $0.role == .user }.map(\.content)
        XCTAssertEqual(
            userTurns?.filter { $0 == "queued while gated" }.count, 1,
            "the queued follow-up drained exactly once, after approval"
        )
    }

    // MARK: helpers

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

/// A one-shot gate: the first turn's LLM call blocks until `open()` is called, letting a test
/// enqueue a follow-up while the run is genuinely in flight. Later turns pass through immediately.
private final class LLMGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false

    func open() {
        lock.lock()
        isOpen = true
        lock.unlock()
    }

    func opened() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isOpen
    }
}

/// Blocks the FIRST turn until the gate opens (so a test can enqueue mid-run), then answers with a
/// plain "say". Subsequent turns answer immediately. Honors cancellation so a Stop still unwinds.
private struct GatedSayLLMClient: LLMClient {
    let gate: LLMGate

    func nextAction(thread _: ChatThread, userMessage: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        while !gate.opened() {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        return .say("done: \(userMessage)")
    }
}

/// Serves a scripted sequence of agent actions (falling back to a terminal `.say` once exhausted).
private actor ScriptedActions {
    private var remaining: [AgentAction]
    init(_ actions: [AgentAction]) { remaining = actions }
    func next() -> AgentAction {
        guard !remaining.isEmpty else { return .say("scripted end") }
        return remaining.removeFirst()
    }
}

/// Blocks until the gate opens (so a test can enqueue a follow-up while the first turn is genuinely
/// in flight), then plays a scripted action sequence across turns. Used to drive a Plan-mode turn
/// that proposes a mutating tool (gated for approval) so the drain-past-approval defect is covered.
private struct GatedScriptedLLMClient: LLMClient {
    let gate: LLMGate
    let scripted: ScriptedActions

    init(gate: LLMGate, actions: [AgentAction]) {
        self.gate = gate
        self.scripted = ScriptedActions(actions)
    }

    func nextAction(thread _: ChatThread, userMessage _: String, tools _: [ToolDefinition]) async throws -> AgentAction {
        while !gate.opened() {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        return await scripted.next()
    }
}
