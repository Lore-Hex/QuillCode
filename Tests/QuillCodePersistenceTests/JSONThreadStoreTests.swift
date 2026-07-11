import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class JSONThreadStoreTests: PersistenceTestCase {
    func testThreadStoreRoundTrips() throws {
        let store = try JSONThreadStore(directory: makeTempDirectory())
        var thread = ChatThread(title: "Test")
        thread.messages.append(.init(role: .user, content: "hello"))

        try store.save(thread)

        XCTAssertEqual(try store.load(thread.id).messages.first?.content, "hello")
        XCTAssertEqual(try store.list().count, 1)
    }

    func testFollowUpQueuePersistsWithThreadAcrossReload() throws {
        let store = JSONThreadStore(directory: try makeTempDirectory())
        var thread = ChatThread(title: "Queued")
        thread.followUpQueue = [
            FollowUpItem(id: UUID(), text: "first follow-up", createdAt: Date(timeIntervalSince1970: 1)),
            FollowUpItem(id: UUID(), text: "second follow-up", createdAt: Date(timeIntervalSince1970: 2))
        ]

        try store.save(thread)

        // Reload from disk restores the queue in order (survives reload).
        let reloaded = try store.load(thread.id)
        XCTAssertEqual(reloaded.followUpQueue.map(\.text), ["first follow-up", "second follow-up"])
        XCTAssertEqual(reloaded.followUpQueue, thread.followUpQueue)
    }

    func testComposerDraftPersistsWithThreadAcrossReload() throws {
        let store = JSONThreadStore(directory: try makeTempDirectory())
        var thread = ChatThread(title: "Draft")
        thread.composerDraft = "half-written prompt"

        try store.save(thread)

        XCTAssertEqual(try store.load(thread.id).composerDraft, "half-written prompt")
    }

    func testComposerAndSentImageAttachmentsPersistAcrossReload() throws {
        let store = JSONThreadStore(directory: try makeTempDirectory())
        let attachment = try XCTUnwrap(ChatAttachment(
            displayName: "screen.png",
            format: .png,
            localURL: URL(fileURLWithPath: "/tmp/screen.png"),
            byteCount: 8
        ))
        var thread = ChatThread(title: "Images", composerAttachments: [attachment])
        thread.messages = [ChatMessage(role: .user, content: "look", attachments: [attachment])]

        try store.save(thread)

        let reloaded = try store.load(thread.id)
        XCTAssertEqual(reloaded.composerAttachments.map(\.id), [attachment.id])
        XCTAssertEqual(reloaded.composerAttachments.map(\.displayName), ["screen.png"])
        XCTAssertEqual(reloaded.messages.first?.attachments.map(\.id), [attachment.id])
    }

    func testGoalPersistsWithThreadAcrossReload() throws {
        let store = JSONThreadStore(directory: try makeTempDirectory())
        var thread = ChatThread(title: "Goal")
        thread.goal = try XCTUnwrap(ThreadGoal(
            objective: "Ship the release",
            status: .blocked,
            blocker: "Waiting for CI"
        ))

        try store.save(thread)

        let persistedGoal = try XCTUnwrap(store.load(thread.id).goal)
        XCTAssertEqual(persistedGoal.objective, thread.goal?.objective)
        XCTAssertEqual(persistedGoal.status, thread.goal?.status)
        XCTAssertEqual(persistedGoal.blocker, thread.goal?.blocker)
    }

    func testBlankComposerDraftDecodesAsNil() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Blank Draft",
          "instructions": [],
          "memories": [],
          "mode": "auto",
          "model": "trustedrouter/fast",
          "messages": [],
          "events": [],
          "isPinned": false,
          "isArchived": false,
          "createdAt": "2020-01-01T00:00:00Z",
          "updatedAt": "2020-01-01T00:00:00Z",
          "composerDraft": "   \\n  "
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let thread = try decoder.decode(ChatThread.self, from: Data(json.utf8))
        XCTAssertNil(thread.composerDraft)
    }

    func testListSkipsCorruptFilesAndKeepsHealthyThreads() throws {
        // The catastrophic bug this guards: one truncated/hand-edited file must NOT empty the whole
        // sidebar. A throwing map used to abort the entire load on a single bad file.
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        try store.save(ChatThread(title: "Alpha"))
        try store.save(ChatThread(title: "Beta"))
        // A truncated crash-mid-write file and a foreign-but-.json file.
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("\(UUID().uuidString).json"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("\(UUID().uuidString).json"))

        let threads = try store.list()
        XCTAssertEqual(Set(threads.map(\.title)), ["Alpha", "Beta"])
    }

    func testListingReportsUnreadableFilesWithoutLosingHealthyThreads() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        try store.save(ChatThread(title: "Healthy"))
        let corrupt = directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("garbage".utf8).write(to: corrupt)

        let listing = store.listing()
        XCTAssertEqual(listing.threads.map(\.title), ["Healthy"])
        // Compare by filename: contentsOfDirectory resolves the macOS /var -> /private/var symlink,
        // so raw URL equality is unreliable here.
        XCTAssertEqual(listing.unreadable.map(\.lastPathComponent), [corrupt.lastPathComponent])
    }

    func testListToleratesSchemaIncompatibleFile() throws {
        // A .json that is valid JSON but missing required ChatThread keys is skipped, not fatal.
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        try store.save(ChatThread(title: "Good"))
        let incompatible = """
        { "id": "\(UUID().uuidString)", "title": "No required fields" }
        """
        try Data(incompatible.utf8).write(to: directory.appendingPathComponent("\(UUID().uuidString).json"))

        XCTAssertEqual(try store.list().map(\.title), ["Good"])
        XCTAssertEqual(store.listing().unreadable.count, 1)
    }

    func testLoadStillThrowsOnCorruptNamedThread() throws {
        // Only the LIST is best-effort; a direct open of a named corrupt thread must still report it.
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let id = UUID()
        try Data("{ truncated".utf8).write(to: directory.appendingPathComponent("\(id.uuidString).json"))

        XCTAssertThrowsError(try store.load(id))
    }

    func testThreadWrittenBeforeQueueFieldDecodesToEmptyQueue() throws {
        // A thread JSON persisted before followUpQueue existed must still decode (queue = []).
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "instructions": [],
          "memories": [],
          "mode": "auto",
          "model": "trustedrouter/fusion",
          "messages": [],
          "events": [],
          "isPinned": false,
          "isArchived": false,
          "createdAt": "2020-01-01T00:00:00Z",
          "updatedAt": "2020-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let thread = try decoder.decode(ChatThread.self, from: Data(json.utf8))
        XCTAssertEqual(thread.followUpQueue, [])
        XCTAssertNil(thread.goal)
    }
}
