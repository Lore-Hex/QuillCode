import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
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
}
