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
