import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class WorkspaceComposerDraftIntegrationTests: XCTestCase {
    func testDraftIsPreservedPerThreadAcrossSwitches() throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        let threadA = model.newChat()
        model.setDraft("draft for A")

        // New chat stashes A's draft and starts empty.
        let threadB = model.newChat()
        XCTAssertEqual(model.composer.draft, "")
        model.setDraft("draft for B")

        // Switching back to A restores its draft; switching to B restores B's.
        model.selectThread(threadA)
        XCTAssertEqual(model.composer.draft, "draft for A")
        model.selectThread(threadB)
        XCTAssertEqual(model.composer.draft, "draft for B")

        // The surface snapshot mirrors the restored draft.
        XCTAssertEqual(model.surface().composer.draft, "draft for B")
    }

    func testSubmittedDraftIsNotResurrected() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        let threadA = model.newChat()
        model.setDraft("draft for A")
        let threadB = model.newChat()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        // A's unsent draft survives; B's sent draft is gone, not resurrected.
        model.selectThread(threadA)
        XCTAssertEqual(model.composer.draft, "draft for A")
        model.selectThread(threadB)
        XCTAssertEqual(model.composer.draft, "")
    }

    func testDeletingActiveThreadDoesNotBleedDraftAndPrunesIt() throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        _ = model.newChat()
        model.setDraft("draft for A")
        let threadB = model.newChat()
        model.setDraft("draft for B")

        // Deleting the active thread B auto-selects A; B's draft must not bleed into A.
        _ = model.deleteThread(threadB)
        XCTAssertEqual(model.composer.draft, "draft for A")
        XCTAssertNil(model.threadDrafts[threadB])
    }

    func testArchivingActiveThreadRestoresAutoSelectedThreadDraft() throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        let threadA = model.newChat()
        model.setDraft("draft for A")
        let threadB = model.newChat()
        model.setDraft("draft for B")

        // Archiving the active thread B auto-selects A and shows A's own draft.
        model.archiveThread(threadB)
        XCTAssertEqual(model.composer.draft, "draft for A")
        // Restoring archived B brings back its stashed draft without bleeding A.
        _ = model.unarchiveThread(threadB)
        XCTAssertEqual(model.composer.draft, "draft for B")
        _ = threadA
    }

    func testSlashSubmitPrunesActiveThreadDraft() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        let threadA = model.newChat()
        model.setDraft("draft for A")
        let threadB = model.newChat()
        model.setDraft("/diff")
        await model.submitComposer(workspaceRoot: root)

        model.selectThread(threadA)
        XCTAssertEqual(model.composer.draft, "draft for A")
        model.selectThread(threadB)
        XCTAssertEqual(model.composer.draft, "")
    }

    func testSelectedThreadDraftSurvivesWorkspaceReload() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let thread = ChatThread(title: "Persisted draft")
        try store.save(thread)
        let first = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: store
        )

        first.setDraft("continue the partial plan")

        let reloadedThreads = try store.list()
        let second = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: reloadedThreads, selectedThreadID: thread.id),
            threadStore: store
        )
        XCTAssertEqual(second.composer.draft, "continue the partial plan")
    }

    func testLightweightCheckpointRestoresWithoutRewritingTranscript() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root.appendingPathComponent("threads"))
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        let thread = ChatThread(title: "Checkpointed draft")
        try threadStore.save(thread)
        let first = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: threadStore,
            composerDraftStore: checkpointStore
        )

        first.setDraft("continue after a crash")

        XCTAssertNil(try threadStore.load(thread.id).composerDraft)
        XCTAssertEqual(try checkpointStore.load(for: thread.id)?.draft, "continue after a crash")
        let second = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: try threadStore.list(),
                selectedThreadID: thread.id
            ),
            threadStore: threadStore,
            composerDraftStore: checkpointStore
        )
        XCTAssertEqual(second.composer.draft, "continue after a crash")
        XCTAssertEqual(second.root.threads.first?.composerDraft, "continue after a crash")
    }

    func testCheckpointTombstonePreventsStaleThreadDraftFromResurrecting() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root.appendingPathComponent("threads"))
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        let thread = ChatThread(title: "Stale snapshot", composerDraft: "already sent")
        try threadStore.save(thread)
        try checkpointStore.save(nil, for: thread.id)

        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: threadStore,
            composerDraftStore: checkpointStore
        )

        XCTAssertEqual(model.composer.draft, "")
        XCTAssertNil(model.root.threads.first?.composerDraft)
    }

    func testPendingFirstMessageRestoresAndMovesToCreatedThread() throws {
        let root = try makeTempDirectory()
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        try checkpointStore.save("first unsent message", for: nil)
        let model = QuillCodeWorkspaceModel(composerDraftStore: checkpointStore)

        XCTAssertEqual(model.composer.draft, "first unsent message")
        let threadID = try XCTUnwrap(model.prepareComposerSubmissionThread())

        XCTAssertEqual(model.composer.draft, "first unsent message")
        XCTAssertEqual(try checkpointStore.load(for: threadID)?.draft, "first unsent message")
        XCTAssertNil(try checkpointStore.load(for: nil))
    }

    func testConfidentialDraftNeverCreatesCheckpoint() throws {
        let root = try makeTempDirectory()
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        let model = QuillCodeWorkspaceModel(composerDraftStore: checkpointStore)
        let threadID = model.newConfidentialChat()

        model.setDraft("private unsent text")

        XCTAssertEqual(model.composer.draft, "private unsent text")
        XCTAssertNil(try checkpointStore.load(for: threadID))
        XCTAssertNil(try checkpointStore.load(for: nil))
    }

    func testOversizedCheckpointFallsBackWithoutLeavingStaleDraft() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root.appendingPathComponent("threads"))
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        let thread = ChatThread(title: "Large draft")
        try threadStore.save(thread)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: threadStore,
            composerDraftStore: checkpointStore
        )
        model.setDraft("old checkpoint")
        let oversized = String(
            repeating: "x",
            count: ComposerDraftCheckpointStore.maximumDraftBytes + 1
        )

        model.setDraft(oversized)

        XCTAssertNil(try checkpointStore.load(for: thread.id))
        XCTAssertEqual(try threadStore.load(thread.id).composerDraft, oversized)
        let reloaded = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: try threadStore.list(),
                selectedThreadID: thread.id
            ),
            threadStore: threadStore,
            composerDraftStore: checkpointStore
        )
        XCTAssertEqual(reloaded.composer.draft, oversized)
    }

    func testDeletingThreadRemovesItsCheckpoint() throws {
        let root = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: root.appendingPathComponent("threads"))
        let checkpointStore = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts")
        )
        let thread = ChatThread(title: "Delete checkpoint")
        try threadStore.save(thread)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: threadStore,
            composerDraftStore: checkpointStore
        )
        model.setDraft("remove with chat")

        XCTAssertTrue(model.deleteThread(thread.id))

        XCTAssertNil(try checkpointStore.load(for: thread.id))
        XCTAssertFalse(threadStore.contains(thread.id))
    }

    func testSentDraftIsClearedFromPersistentThread() async throws {
        let root = try makeQuillCodeTestDirectory()
        let store = try JSONThreadStore(directory: makeTempDirectory())
        let thread = ChatThread(title: "Send clears draft")
        try store.save(thread)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: store
        )

        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertNil(try store.load(thread.id).composerDraft)
    }

    func testClearThreadClearsDraftOnlyThread() throws {
        let store = try JSONThreadStore(directory: makeTempDirectory())
        let thread = ChatThread(title: "Draft only")
        try store.save(thread)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            threadStore: store
        )

        model.setDraft("remove me")

        XCTAssertTrue(model.clearThread(thread.id))
        XCTAssertEqual(model.composer.draft, "")
        XCTAssertNil(try store.load(thread.id).composerDraft)
    }
}
