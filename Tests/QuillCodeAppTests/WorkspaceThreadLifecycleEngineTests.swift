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

    func testDuplicateCopiesConversationAndAddsNotice() throws {
        let projectID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let source = ChatThread(
            title: "Implement feature",
            projectID: projectID,
            mode: .review,
            model: "provider/model",
            messages: [
                .init(role: .user, content: "run whoami"),
                .init(role: .assistant, content: "quill")
            ],
            events: [
                .init(kind: .notice, summary: "Original event")
            ],
            isPinned: true,
            isArchived: true,
            instructions: [
                ProjectInstruction(path: "AGENTS.md", title: "AGENTS", content: "Rules", byteCount: 5)
            ],
            memories: [
                MemoryNote(
                    id: "m1",
                    scope: .project,
                    title: "Preference",
                    content: "Use Swift",
                    relativePath: "note.md",
                    byteCount: 9
                )
            ]
        )

        let duplicate = WorkspaceThreadLifecycleEngine.duplicateThread(source, projectID: projectID)

        XCTAssertNotEqual(duplicate.id, source.id)
        XCTAssertEqual(duplicate.title, "Copy: Implement feature")
        XCTAssertEqual(duplicate.projectID, projectID)
        XCTAssertEqual(duplicate.mode, AgentMode.review)
        XCTAssertEqual(duplicate.model, "provider/model")
        XCTAssertEqual(duplicate.messages, source.messages)
        XCTAssertFalse(duplicate.isPinned)
        XCTAssertFalse(duplicate.isArchived)
        XCTAssertEqual(duplicate.instructions, source.instructions)
        XCTAssertEqual(duplicate.memories, source.memories)
        XCTAssertEqual(duplicate.events.last?.summary, "Duplicated from Implement feature")
        XCTAssertEqual(duplicate.events.last?.payloadJSON, source.id.uuidString)
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
