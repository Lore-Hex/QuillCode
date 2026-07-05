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
