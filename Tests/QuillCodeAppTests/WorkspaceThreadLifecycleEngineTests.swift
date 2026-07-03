import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceThreadLifecycleEngineTests: XCTestCase {
    func testRenameTrimsTitleAndRejectsEmptyNames() throws {
        let thread = ChatThread(title: "Old")
        let now = Date(timeIntervalSince1970: 1_234)
        var threads = [thread]

        let renamed = try XCTUnwrap(WorkspaceThreadLifecycleEngine.renameThread(
            thread.id,
            to: "  New name  ",
            threads: &threads,
            now: now
        ))

        XCTAssertEqual(renamed.title, "New name")
        XCTAssertEqual(renamed.updatedAt, now)
        XCTAssertNil(WorkspaceThreadLifecycleEngine.renameThread(
            thread.id,
            to: " \n\t ",
            threads: &threads,
            now: now
        ))
    }

    func testSetPinThreadIsIdempotentAndUpdatesTimestampOnlyWhenChanged() throws {
        let thread = ChatThread(title: "Pin me", updatedAt: Date(timeIntervalSince1970: 10))
        let pinnedAt = Date(timeIntervalSince1970: 20)
        let unpinnedAt = Date(timeIntervalSince1970: 30)
        var threads = [thread]

        let pinned = try XCTUnwrap(WorkspaceThreadLifecycleEngine.setPinThread(
            thread.id,
            isPinned: true,
            threads: &threads,
            now: pinnedAt
        ))

        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(pinned.updatedAt, pinnedAt)
        XCTAssertNil(WorkspaceThreadLifecycleEngine.setPinThread(
            thread.id,
            isPinned: true,
            threads: &threads,
            now: unpinnedAt
        ))

        let unpinned = try XCTUnwrap(WorkspaceThreadLifecycleEngine.setPinThread(
            thread.id,
            isPinned: false,
            threads: &threads,
            now: unpinnedAt
        ))

        XCTAssertFalse(unpinned.isPinned)
        XCTAssertEqual(unpinned.updatedAt, unpinnedAt)
    }

    func testArchiveSelectedThreadSelectsNewestUnarchivedThreadInSameProject() throws {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let selected = ChatThread(title: "Selected", projectID: projectID, updatedAt: Date(timeIntervalSince1970: 10))
        let older = ChatThread(title: "Older", projectID: projectID, updatedAt: Date(timeIntervalSince1970: 20))
        let newer = ChatThread(title: "Newer", projectID: projectID, updatedAt: Date(timeIntervalSince1970: 30))
        let otherProject = ChatThread(title: "Other", updatedAt: Date(timeIntervalSince1970: 40))
        var threads = [selected, older, newer, otherProject]
        let now = Date(timeIntervalSince1970: 50)

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.archiveThread(
            selected.id,
            threads: &threads,
            selectedThreadID: selected.id,
            now: now
        ))

        XCTAssertEqual(result.selectedThreadID, newer.id)
        XCTAssertEqual(result.changedThread.id, selected.id)
        XCTAssertTrue(result.changedThread.isArchived)
        XCTAssertEqual(result.changedThread.updatedAt, now)
    }

    func testArchiveNonSelectedThreadPreservesSelection() throws {
        let selected = ChatThread(title: "Selected")
        let target = ChatThread(title: "Target")
        var threads = [selected, target]

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.archiveThread(
            target.id,
            threads: &threads,
            selectedThreadID: selected.id
        ))

        XCTAssertEqual(result.selectedThreadID, selected.id)
        XCTAssertTrue(result.changedThread.isArchived)
    }

    func testUnarchiveReturnsProjectContext() throws {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        var archived = ChatThread(title: "Archived", projectID: projectID)
        archived.isArchived = true
        var threads = [archived]

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.unarchiveThread(
            archived.id,
            threads: &threads
        ))

        XCTAssertEqual(result.projectID, projectID)
        XCTAssertFalse(result.changedThread.isArchived)
    }

    func testDeleteSelectedThreadSelectsNewestUnarchivedThreadInSameProject() throws {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let selected = ChatThread(title: "Selected", projectID: projectID, updatedAt: Date(timeIntervalSince1970: 10))
        let older = ChatThread(title: "Older", projectID: projectID, updatedAt: Date(timeIntervalSince1970: 20))
        let newer = ChatThread(title: "Newer", projectID: projectID, updatedAt: Date(timeIntervalSince1970: 30))
        var archived = ChatThread(title: "Archived", projectID: projectID, updatedAt: Date(timeIntervalSince1970: 40))
        archived.isArchived = true
        let otherProject = ChatThread(title: "Other", updatedAt: Date(timeIntervalSince1970: 50))
        var threads = [selected, older, newer, archived, otherProject]

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.deleteThread(
            selected.id,
            threads: &threads,
            selectedThreadID: selected.id
        ))

        XCTAssertEqual(result.removedThread.id, selected.id)
        XCTAssertEqual(result.selectedThreadID, newer.id)
        XCTAssertFalse(threads.contains { $0.id == selected.id })
    }

    func testDeleteNonSelectedThreadPreservesSelection() throws {
        let selected = ChatThread(title: "Selected")
        let target = ChatThread(title: "Target")
        var threads = [selected, target]

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.deleteThread(
            target.id,
            threads: &threads,
            selectedThreadID: selected.id
        ))

        XCTAssertEqual(result.removedThread.id, target.id)
        XCTAssertEqual(result.selectedThreadID, selected.id)
        XCTAssertEqual(threads.map(\.id), [selected.id])
    }

    func testClearThreadResetsConversationStateAndPreservesShell() throws {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let now = Date(timeIntervalSince1970: 42)
        let createdAt = Date(timeIntervalSince1970: 1)
        let instruction = ProjectInstruction(
            path: "AGENTS.md",
            title: "AGENTS.md",
            content: "Use Swift.",
            byteCount: 10
        )
        let memory = MemoryNote(
            id: "global-style",
            scope: .global,
            title: "Style",
            content: "Prefer focused diffs.",
            relativePath: "style.md",
            byteCount: 21
        )
        var thread = ChatThread(
            title: "Fix CI",
            projectID: projectID,
            mode: .review,
            model: "trustedrouter/fusion",
            messages: [
                .init(role: .user, content: "run whoami"),
                .init(role: .assistant, content: "quill")
            ],
            events: [
                .init(kind: .toolCompleted, summary: "Ran shell")
            ],
            createdAt: createdAt,
            instructions: [instruction],
            memories: [memory],
            followUpQueue: [FollowUpItem(text: "then run tests")]
        )
        thread.isPinned = true
        let normalizedModel = thread.model
        var threads = [thread]

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.clearThread(
            thread.id,
            threads: &threads,
            now: now
        ))

        XCTAssertEqual(result.changedThread.id, thread.id)
        XCTAssertEqual(result.changedThread.title, "Fix CI")
        XCTAssertEqual(result.changedThread.projectID, projectID)
        XCTAssertEqual(result.changedThread.mode, .review)
        XCTAssertEqual(result.changedThread.model, normalizedModel)
        XCTAssertEqual(result.changedThread.createdAt, createdAt)
        XCTAssertEqual(result.changedThread.updatedAt, now)
        XCTAssertEqual(result.changedThread.instructions, [instruction])
        XCTAssertEqual(result.changedThread.memories, [memory])
        XCTAssertTrue(result.changedThread.isPinned)
        XCTAssertTrue(result.changedThread.messages.isEmpty)
        XCTAssertTrue(result.changedThread.events.isEmpty)
        XCTAssertTrue(result.changedThread.followUpQueue.isEmpty)
    }

    func testClearThreadRejectsAlreadyEmptyThread() {
        let thread = ChatThread(title: "Empty")
        var threads = [thread]

        XCTAssertNil(WorkspaceThreadLifecycleEngine.clearThread(thread.id, threads: &threads))
    }

    func testAgentRunThreadUpdateUpsertsAndPreservesCurrentSelection() {
        let project = ProjectRef(name: "QuillCode", path: "/repo")
        let target = ChatThread(title: "Original", projectID: project.id)
        let selected = ChatThread(title: "Selected")
        var updatedTarget = target
        updatedTarget.title = "Updated"
        var threads = [target, selected]

        let result = WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate(
            updatedTarget,
            threads: &threads,
            projects: [project],
            selectedThreadID: selected.id,
            selectedProjectID: nil
        )

        XCTAssertEqual(result.selectedThreadID, selected.id)
        XCTAssertNil(result.selectedProjectID)
        XCTAssertFalse(result.didSelectUpdatedThread)
        XCTAssertEqual(threads.map(\.id), [target.id, selected.id])
        XCTAssertEqual(threads.first?.title, "Updated")
    }

    func testAgentRunThreadUpdateSelectsUpdatedThreadWhenSelectionIsStale() {
        let project = ProjectRef(name: "QuillCode", path: "/repo")
        let updated = ChatThread(title: "Updated", projectID: project.id)
        var threads: [ChatThread] = []

        let result = WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate(
            updated,
            threads: &threads,
            projects: [project],
            selectedThreadID: UUID(),
            selectedProjectID: nil
        )

        XCTAssertEqual(result.selectedThreadID, updated.id)
        XCTAssertEqual(result.selectedProjectID, project.id)
        XCTAssertTrue(result.didSelectUpdatedThread)
        XCTAssertEqual(threads.map(\.id), [updated.id])
    }

    func testAgentRunThreadUpdateDropsUnknownProjectWhenFallbackSelectingUpdatedThread() {
        let updated = ChatThread(title: "Updated", projectID: UUID())
        var threads: [ChatThread] = []

        let result = WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate(
            updated,
            threads: &threads,
            projects: [],
            selectedThreadID: nil,
            selectedProjectID: nil
        )

        XCTAssertEqual(result.selectedThreadID, updated.id)
        XCTAssertNil(result.selectedProjectID)
        XCTAssertTrue(result.didSelectUpdatedThread)
    }

    func testArchiveThreadsArchivesAndUnpinsAllTargets() throws {
        var pinned = ChatThread(title: "Pinned")
        pinned.isPinned = true
        let other = ChatThread(title: "Other")
        var threads = [pinned, other]
        let now = Date(timeIntervalSince1970: 99)

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.archiveThreads(
            [pinned.id, other.id],
            threads: &threads,
            now: now
        ))

        XCTAssertEqual(Set(result.changedThreads.map(\.id)), Set([pinned.id, other.id]))
        XCTAssertTrue(threads.allSatisfy { $0.isArchived })
        XCTAssertTrue(threads.allSatisfy { !$0.isPinned })
        XCTAssertTrue(threads.allSatisfy { $0.updatedAt == now })
    }

    func testUnarchiveThreadsUnarchivesAllTargets() throws {
        var first = ChatThread(title: "First")
        first.isArchived = true
        var second = ChatThread(title: "Second")
        second.isArchived = true
        var threads = [first, second]

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.unarchiveThreads(
            [first.id, second.id],
            threads: &threads
        ))

        XCTAssertEqual(Set(result.changedThreads.map(\.id)), Set([first.id, second.id]))
        XCTAssertTrue(threads.allSatisfy { !$0.isArchived })
    }

    func testDeleteThreadsRemovesAndReturnsTargets() throws {
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        let untouched = ChatThread(title: "Untouched")
        var threads = [first, second, untouched]

        let result = try XCTUnwrap(WorkspaceThreadLifecycleEngine.deleteThreads(
            [first.id, second.id],
            threads: &threads
        ))

        XCTAssertEqual(result.removedThreads.map(\.id), [first.id, second.id])
        XCTAssertEqual(threads.map(\.id), [untouched.id])
    }
}
