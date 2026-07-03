import XCTest
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
@testable import quill_code_desktop

/// A safety regression guard: refusing a held tool (Deny / Skip) must NEVER be silently dropped,
/// even while a `.send` task is in flight. Routing every gate decision through the `.send` slot once
/// subjected Deny to a `!isRunning(.send)` guard that swallowed the click; the decision-recording is
/// now unconditional (a refusal always resolves the gate) and only the follow-up drain is slot-gated.
@MainActor
final class QuillCodeDesktopDenyGateDrainTests: XCTestCase {
    func testDenyIsRecordedEvenWhileASendTaskIsInFlight() async throws {
        let workspaceRoot = try makeTempDirectory()
        let (model, requestID) = try gatedModel(queued: ["queued behind gate"])
        let coordinator = QuillCodeDesktopWorkspaceActionCoordinator()
        let tasks = QuillCodeDesktopTaskCoordinator()

        // Simulate a `.send` task genuinely in flight (a long-running operation holding the slot).
        let release = ManualRelease()
        tasks.startIfIdle(.send) {
            await release.wait()
        }
        XCTAssertTrue(tasks.isRunning(.send))

        // The user clicks Skip while the slot is busy. The refusal MUST be recorded — not dropped.
        coordinator.runToolCardAction(
            denyAction(requestID: requestID),
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: {}
        )

        // The gate is resolved immediately (decision recorded) despite the busy `.send` slot: a
        // matching `approvalDecided` event exists for the gate's request id — the refusal was NOT
        // dropped.
        XCTAssertTrue(
            isGateDecided(requestID: requestID, in: model.selectedThread),
            "a Skip must resolve the gate even while a send is in flight"
        )

        // Let the in-flight send finish; the queue then drains (the in-flight send's completion, or a
        // later interaction, drains the now-decided thread — nothing is stranded).
        await release.open()
        try await waitUntil(timeoutSeconds: 2) { !tasks.isRunning(.send) }
    }

    func testDenyDrainsQueuedFollowUpWhenSlotIsFree() async throws {
        let workspaceRoot = try makeTempDirectory()
        let (model, requestID) = try gatedModel(queued: ["drain me"])
        let coordinator = QuillCodeDesktopWorkspaceActionCoordinator()
        let tasks = QuillCodeDesktopTaskCoordinator()

        // The normal case: a gate is shown when the run is blocked, so the `.send` slot is free.
        coordinator.runToolCardAction(
            denyAction(requestID: requestID),
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: {}
        )

        // The deny records immediately and the drain runs through the slot.
        XCTAssertTrue(isGateDecided(requestID: requestID, in: model.selectedThread))
        try await waitUntil(timeoutSeconds: 2) { model.followUpQueue.isEmpty && !tasks.isRunning(.send) }
        let userTurns = model.selectedThread?.messages.filter { $0.role == .user }.map(\.content)
        XCTAssertEqual(userTurns?.filter { $0 == "drain me" }.count, 1, "the queued follow-up drained once")
    }

    // MARK: helpers

    private func denyAction(requestID: String) -> ToolCardActionSurface {
        ToolCardActionSurface(title: "Skip", kind: .deny, requestID: requestID, style: .secondary)
    }

    /// True when the thread records a decision for `requestID` — i.e. the gate is resolved.
    private func isGateDecided(requestID: String, in thread: ChatThread?) -> Bool {
        guard let thread else { return false }
        return thread.events.contains { event in
            guard event.kind == .approvalDecided,
                  let data = event.payloadJSON?.data(using: .utf8),
                  let decision = try? JSONDecoder().decode(ApprovalDecision.self, from: data)
            else {
                return false
            }
            return decision.requestID == requestID
        }
    }

    /// A model whose selected `.auto` thread holds a pre-seeded undecided approval for a mutating
    /// shell tool, with follow-ups queued behind the gate.
    private func gatedModel(queued: [String]) throws -> (model: QuillCodeWorkspaceModel, requestID: String) {
        let requestID = "deny-gate"
        let held = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "touch gated-tool.txt"])
        )
        let request = ApprovalRequest(
            id: requestID,
            toolCall: held,
            toolDefinition: ToolDefinition.shellRun,
            reason: "gate",
            recommendedVerdict: .clarify
        )
        var thread = ChatThread(
            mode: .auto,
            messages: [ChatMessage(role: .user, content: "do the gated work")],
            events: [ThreadEvent(
                kind: .approvalRequested,
                summary: "gate",
                payloadJSON: try JSONHelpers.encodePretty(request)
            )]
        )
        thread.followUpQueue = queued.map { FollowUpItem(text: $0) }
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id)
        )
        return (model, requestID)
    }

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

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeDesktopDenyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

/// A manually-released async barrier so a test can hold the `.send` slot open until it chooses.
private actor ManualRelease {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
