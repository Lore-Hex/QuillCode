import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

final class WorkspaceThreadPersistenceTests: XCTestCase {
    func testConfidentialThreadIsNeverWrittenToTheStore() throws {
        // The confidential privacy promise at the persistence boundary: save, saveOrThrow, batch save,
        // and mutate must all leave the store untouched for a confidential thread — nothing with the
        // thread's id (or its content) may reach disk.
        let directory = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: directory)
        let confidential = ChatThread(
            title: "Confidential",
            messages: [.init(role: .user, content: "private question")],
            runtimeContext: .confidential
        )
        var threads = [confidential]
        let persistence = WorkspaceThreadPersistence(store: store)

        persistence.save(confidential)
        try persistence.saveOrThrow(confidential)
        persistence.save([confidential])
        persistence.mutate(confidential.id, threads: &threads) { thread in
            thread.title = "Mutated confidential"
        }

        XCTAssertEqual(threads[0].title, "Mutated confidential", "in-memory mutation still applies")
        XCTAssertThrowsError(try store.load(confidential.id), "the store must have no record of the thread")
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(
            contents.contains { $0.contains(confidential.id.uuidString) },
            "no file named for the confidential thread may exist: \(contents)"
        )
    }

    func testMutateUpdatesTimestampAndPersistsChangedThread() throws {
        let directory = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: directory)
        let originalDate = Date(timeIntervalSince1970: 10)
        let updatedDate = Date(timeIntervalSince1970: 20)
        let thread = ChatThread(title: "Before", updatedAt: originalDate)
        var threads = [thread]
        let persistence = WorkspaceThreadPersistence(store: store, now: { updatedDate })

        let index = persistence.mutate(thread.id, threads: &threads) { changedThread in
            changedThread.title = "After"
        }

        XCTAssertEqual(index, 0)
        XCTAssertEqual(threads[0].title, "After")
        XCTAssertEqual(threads[0].updatedAt, updatedDate)

        let loaded = try store.load(thread.id)
        XCTAssertEqual(loaded.title, "After")
        XCTAssertEqual(loaded.updatedAt, updatedDate)
    }

    func testSaveManyAndDeleteDelegateToStore() throws {
        let directory = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: directory)
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")
        let persistence = WorkspaceThreadPersistence(store: store)

        try persistence.saveOrThrow(first)
        XCTAssertEqual(try store.load(first.id).title, "First")

        persistence.save([first, second])
        XCTAssertEqual(try store.load(first.id).title, "First")
        XCTAssertEqual(try store.load(second.id).title, "Second")

        persistence.delete(first.id)
        XCTAssertThrowsError(try store.load(first.id))
        XCTAssertEqual(try store.load(second.id).title, "Second")
    }

    func testMissingStoreIsANoop() {
        let thread = ChatThread(title: "No store")
        var threads = [thread]
        let persistence = WorkspaceThreadPersistence(store: nil, now: { Date(timeIntervalSince1970: 30) })

        XCTAssertEqual(persistence.mutate(thread.id, threads: &threads) { $0.title = "Updated" }, 0)
        XCTAssertEqual(threads[0].title, "Updated")
        persistence.save(thread)
        persistence.save([thread])
        persistence.delete(thread.id)
    }

    func testMutateMissingThreadDoesNothing() {
        let thread = ChatThread(title: "Only thread")
        var threads = [thread]
        let persistence = WorkspaceThreadPersistence(store: nil, now: { Date(timeIntervalSince1970: 30) })

        XCTAssertNil(persistence.mutate(UUID(), threads: &threads) { $0.title = "Changed" })
        XCTAssertEqual(threads, [thread])
    }

    func testEphemeralThreadIsNeverPersisted() throws {
        let directory = try makeQuillCodeTestDirectory()
        let store = JSONThreadStore(directory: directory)
        let parentID = UUID()
        let side = ChatThread(
            title: "Side conversation",
            runtimeContext: .sideConversation(parentThreadID: parentID)
        )
        let persistence = WorkspaceThreadPersistence(store: store)

        persistence.save(side)
        try persistence.saveOrThrow(side)
        persistence.save([side])

        XCTAssertThrowsError(try store.load(side.id))
    }

    func testFailedSaveIsVisibleUntilAFullSnapshotSucceeds() throws {
        let root = try makeQuillCodeTestDirectory()
        let privateDirectoryName = "private-customer-project"
        let blockingFile = root.appendingPathComponent(privateDirectoryName)
        try Data("not-a-directory".utf8).write(to: blockingFile)
        let store = JSONThreadStore(
            directory: blockingFile.appendingPathComponent("threads")
        )
        let tracker = WorkspaceThreadPersistenceIssueTracker()
        let persistence = WorkspaceThreadPersistence(store: store, issueTracker: tracker)
        let thread = ChatThread(title: "Unsaved customer plan")

        persistence.save(thread)

        let issue = try XCTUnwrap(tracker.runtimeIssue)
        XCTAssertEqual(tracker.failedThreadCount, 1)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.title, "A chat change is not saved")
        XCTAssertEqual(
            issue.diagnostics.first { $0.label == "Affected chats" }?.value,
            "1"
        )
        XCTAssertFalse(issue.message.contains(privateDirectoryName))
        XCTAssertFalse(issue.diagnostics.contains { $0.value.contains(privateDirectoryName) })

        try FileManager.default.removeItem(at: blockingFile)
        persistence.save(thread)

        XCTAssertEqual(tracker.failedThreadCount, 0)
        XCTAssertNil(tracker.runtimeIssue)
        XCTAssertEqual(try store.load(thread.id).title, thread.title)
    }

    func testThrowingSaveRecordsFailureBeforeRethrowing() throws {
        let root = try makeQuillCodeTestDirectory()
        let blockingFile = root.appendingPathComponent("blocked")
        try Data().write(to: blockingFile)
        let tracker = WorkspaceThreadPersistenceIssueTracker()
        let persistence = WorkspaceThreadPersistence(
            store: JSONThreadStore(directory: blockingFile.appendingPathComponent("threads")),
            issueTracker: tracker
        )

        XCTAssertThrowsError(try persistence.saveOrThrow(ChatThread(title: "Important")))
        XCTAssertEqual(tracker.failedThreadCount, 1)
    }

    func testFailedDeleteIsVisibleUntilDeleteCanComplete() throws {
        let root = try makeQuillCodeTestDirectory()
        let storeDirectory = root.appendingPathComponent("threads", isDirectory: true)
        let store = JSONThreadStore(directory: storeDirectory)
        let thread = ChatThread(title: "Delete me")
        try store.save(thread)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: storeDirectory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: storeDirectory.path
            )
        }
        let tracker = WorkspaceThreadPersistenceIssueTracker()
        let persistence = WorkspaceThreadPersistence(
            store: store,
            issueTracker: tracker
        )

        persistence.delete(thread.id)

        XCTAssertEqual(tracker.failedThreadCount, 1)
        XCTAssertEqual(tracker.runtimeIssue?.title, "A chat change is not saved")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: storeDirectory.path
        )
        persistence.delete(thread.id)

        XCTAssertEqual(tracker.failedThreadCount, 0)
        XCTAssertNil(tracker.runtimeIssue)
        XCTAssertThrowsError(try store.load(thread.id))
    }

    func testEachAffectedChatRequiresItsOwnSuccessfulSnapshot() throws {
        let root = try makeQuillCodeTestDirectory()
        let blockingFile = root.appendingPathComponent("blocked")
        try Data().write(to: blockingFile)
        let store = JSONThreadStore(directory: blockingFile.appendingPathComponent("threads"))
        let tracker = WorkspaceThreadPersistenceIssueTracker()
        let persistence = WorkspaceThreadPersistence(store: store, issueTracker: tracker)
        let first = ChatThread(title: "First")
        let second = ChatThread(title: "Second")

        persistence.save([first, second])

        XCTAssertEqual(tracker.failedThreadCount, 2)
        XCTAssertEqual(tracker.runtimeIssue?.title, "Some chat changes are not saved")

        try FileManager.default.removeItem(at: blockingFile)
        persistence.save(first)

        XCTAssertEqual(tracker.failedThreadCount, 1)
        XCTAssertEqual(tracker.runtimeIssue?.title, "A chat change is not saved")

        persistence.save(second)

        XCTAssertEqual(tracker.failedThreadCount, 0)
        XCTAssertNil(tracker.runtimeIssue)
    }
}
