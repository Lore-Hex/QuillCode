import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

/// Proves `/model` is a LIVE writer, not a dead display (issue #879): switching the model actually
/// mutates the selected thread's `model` AND survives a reload from disk, so the next turn runs on
/// the chosen model. Drives the SAME `setModel` writer the composer `/model` popup accept calls.
@MainActor
final class WorkspaceModelCommandPersistenceIntegrationTests: XCTestCase {
    func testModelSlashCommandPersistsThreadModelToDiskAndReadsBack() async throws {
        let root = try makeQuillCodeTestDirectory()
        let threadStore = JSONThreadStore(directory: root)
        let thread = ChatThread(model: TrustedRouterDefaults.defaultModel)
        try threadStore.save(thread)

        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: threadStore
        )

        // The full command path: draft → submission planner → slash dispatch → setModel.
        model.setDraft("/model provider/custom-model")
        await model.submitComposer(workspaceRoot: root)

        // In memory the selected thread now carries the new model...
        XCTAssertEqual(model.selectedThread?.model, "provider/custom-model")
        // ...and it is persisted, so a fresh load from disk sees the same model (survives reload).
        let reloaded = try threadStore.load(thread.id)
        XCTAssertEqual(reloaded.model, "provider/custom-model")
    }

    func testPopupAcceptWriterSetsAndPersistsCanonicalModel() throws {
        let root = try makeQuillCodeTestDirectory()
        let threadStore = JSONThreadStore(directory: root)
        let thread = ChatThread(model: TrustedRouterDefaults.defaultModel)
        try threadStore.save(thread)

        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: threadStore
        )

        // `setModel` is exactly what the `/model` popup accept invokes via `onSetModel`. It returns
        // the canonical id, writes the thread, and persists — the whole live-writer chain.
        let resolved = model.setModel("tr/synth")
        XCTAssertEqual(resolved, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(model.selectedThread?.model, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(try threadStore.load(thread.id).model, TrustedRouterDefaults.synthModel)
    }

    func testPerThreadModelIsIndependentAcrossThreads() throws {
        let root = try makeQuillCodeTestDirectory()
        let threadStore = JSONThreadStore(directory: root)
        let first = ChatThread(model: TrustedRouterDefaults.defaultModel)
        let second = ChatThread(model: TrustedRouterDefaults.defaultModel)
        try threadStore.save(first)
        try threadStore.save(second)

        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [first, second], selectedThreadID: first.id),
            threadStore: threadStore
        )

        model.setModel("tr/synth")
        // Only the selected thread changed; the other keeps its own model (per-thread storage).
        XCTAssertEqual(try threadStore.load(first.id).model, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(try threadStore.load(second.id).model, TrustedRouterDefaults.defaultModel)
    }

    // MARK: - Run-path: the SELECTED model is what the next turn actually runs on

    /// The load-bearing end-to-end proof (fail-on-revert of the run-path fix): after `/model`, drive
    /// a REAL agent turn through `submitComposer` and assert the LLM client the run used was
    /// retargeted at the SELECTED model — not the stale build-time default. Before the fix the run
    /// posted `config.defaultModel` regardless of the switch; this test would fail.
    func testNextTurnRunsOnTheSelectedModelAfterModelCommand() async throws {
        let root = try makeQuillCodeTestDirectory()
        let recorder = ModelRunRecorder()
        let thread = ChatThread(model: TrustedRouterDefaults.defaultModel)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            runner: AgentRunner(llm: RecordingModelLLMClient(model: TrustedRouterDefaults.defaultModel, recorder: recorder)),
            threadStore: JSONThreadStore(directory: root)
        )

        // Switch model, then run a normal turn.
        model.setModel("tr/synth")
        model.setDraft("do the thing")
        await model.submitComposer(workspaceRoot: root)

        // The run's client was retargeted at the selected model (Synth), not the build-time default.
        XCTAssertEqual(recorder.lastRunModel, TrustedRouterDefaults.synthModel)
        XCTAssertNotEqual(recorder.lastRunModel, TrustedRouterDefaults.defaultModel)
    }

    /// Each thread runs on ITS OWN model within the same session, without any Settings save: switch
    /// the model on one thread, switch to a second thread and run — the run uses the second thread's
    /// (unchanged) model, proving the override is per-turn from `thread.model`, not global state.
    func testEachThreadRunsOnItsOwnModelWithinTheSession() async throws {
        let root = try makeQuillCodeTestDirectory()
        let recorder = ModelRunRecorder()
        let threadStore = JSONThreadStore(directory: root)
        let first = ChatThread(model: TrustedRouterDefaults.defaultModel)
        let second = ChatThread(model: TrustedRouterDefaults.defaultModel)
        try threadStore.save(first)
        try threadStore.save(second)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [first, second], selectedThreadID: first.id),
            runner: AgentRunner(llm: RecordingModelLLMClient(model: TrustedRouterDefaults.defaultModel, recorder: recorder)),
            threadStore: threadStore
        )

        // First thread switches to Synth and runs → run uses Synth.
        model.setModel("tr/synth")
        model.setDraft("first turn")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(recorder.lastRunModel, TrustedRouterDefaults.synthModel)

        // Switch to the second (still-default) thread and run → run uses the DEFAULT, not Synth.
        model.selectThread(second.id)
        model.setDraft("second turn")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(recorder.lastRunModel, TrustedRouterDefaults.defaultModel)
    }

    // MARK: - MAJOR 2 regression: `/skill code-review` SUBMITS (runs the skill), not re-completes

    /// Fail-on-revert of the `/skill` Enter-submit fix: submitting the command's OWN documented
    /// example (`/skill code-review`) must RUN an agent turn (loading the skill), not get swallowed.
    /// Before the fix the slash popup stayed open (the detail's usage-example fuzzy-matched) and
    /// Enter re-accepted the bare `/skill `, dropping the argument — so no turn ran.
    func testSkillCommandExampleSubmitsAndRunsAnAgentTurn() async throws {
        let root = try makeQuillCodeTestDirectory()
        let recorder = ModelRunRecorder()
        let thread = ChatThread(model: TrustedRouterDefaults.defaultModel)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            runner: AgentRunner(llm: RecordingModelLLMClient(model: TrustedRouterDefaults.defaultModel, recorder: recorder)),
            threadStore: JSONThreadStore(directory: root)
        )

        model.setDraft("/skill code-review")
        await model.submitComposer(workspaceRoot: root)

        // A real turn ran (the skill-load agent prompt), the draft was consumed, and the user turn
        // recorded the fully-typed command — not a bare `/skill ` with the argument dropped.
        XCTAssertNotNil(recorder.lastRunModel, "The /skill example must actually run a turn.")
        XCTAssertEqual(model.composer.draft, "")
        let userMessages = model.selectedThread?.messages.filter { $0.role == .user }.map(\.content) ?? []
        XCTAssertTrue(
            userMessages.contains { $0.contains("code-review") },
            "The run must carry the skill-load prompt for the typed skill, not a bare /skill."
        )
        XCTAssertFalse(
            userMessages.contains("/skill "),
            "The bare `/skill ` completion must never be what gets submitted."
        )
    }

    /// Unit-level guard on the exact seam the fix touches: `configuredRunner(from:modelID:)` must
    /// retarget the runner's LLM client at `modelID`.
    func testConfiguredRunnerRetargetsTheLLMClientAtTheGivenModel() {
        let recorder = ModelRunRecorder()
        let builder = WorkspaceAgentRunContextBuilder(
            selectedProject: nil,
            browser: BrowserState(),
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let base = AgentRunner(llm: RecordingModelLLMClient(model: "acme/flagship", recorder: recorder))

        let configured = builder.configuredRunner(from: base, modelID: "acme/tiny")
        XCTAssertEqual((configured.llm as? RecordingModelLLMClient)?.model, "acme/tiny")

        // A nil modelID leaves the client's model untouched (existing callers unaffected).
        let untouched = builder.configuredRunner(from: base, modelID: nil)
        XCTAssertEqual((untouched.llm as? RecordingModelLLMClient)?.model, "acme/flagship")
    }
}

/// Thread-safe recorder of the model each run used, shared across the client's `overridingModel`
/// copies (a value-type client can't mutate itself, so it writes through a reference recorder).
private final class ModelRunRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastRunModel: String?
    var lastRunModel: String? {
        lock.lock(); defer { lock.unlock() }
        return _lastRunModel
    }
    func record(_ model: String) {
        lock.lock(); defer { lock.unlock() }
        _lastRunModel = model
    }
}

/// A `ModelOverridingLLMClient` that records the model it is asked to run under and returns a
/// trivial `.say`, so a run's effective model id is observable end-to-end. `overridingModel`
/// returns a copy on the new model (exactly like `TrustedRouterLLMClient`), so the run-path
/// override applied in `configuredRunner` is exercised by the real production seam.
private struct RecordingModelLLMClient: ModelOverridingLLMClient {
    var model: String
    var recorder: ModelRunRecorder

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        recorder.record(model)
        return .say("done on \(model)")
    }

    func overridingModel(_ modelID: String) -> RecordingModelLLMClient {
        var copy = self
        copy.model = modelID
        return copy
    }
}
