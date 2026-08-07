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

    func testThreadStoreRoundTripsModelOnlyContextWithoutCreatingMessages() throws {
        let store = try JSONThreadStore(directory: makeTempDirectory())
        let anchor = ChatMessage(role: .assistant, content: "Visible")
        let context = ThreadModelContextItem(
            afterMessageID: anchor.id,
            responseItem: .object([
                "type": .string("message"),
                "role": .string("assistant"),
                "content": .array([
                    .object(["type": .string("output_text"), "text": .string("Hidden")])
                ])
            ])
        )
        let thread = ChatThread(messages: [anchor], modelContextItems: [context])

        try store.save(thread)

        let reloaded = try store.load(thread.id)
        XCTAssertEqual(reloaded.messages.map(\.id), [anchor.id])
        XCTAssertEqual(reloaded.messages.map(\.content), [anchor.content])
        XCTAssertEqual(reloaded.modelContextItems, [context])
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
        XCTAssertEqual(listing.issues.map(\.reason), [.unreadable])
        XCTAssertFalse(listing.directoryReadFailed)
    }

    func testListingRejectsSymlinkedThreadWithoutReadingItsTarget() throws {
        let directory = try makeTempDirectory()
        let outsideDirectory = try makeTempDirectory()
        let outsideStore = JSONThreadStore(directory: outsideDirectory)
        let outsideThread = ChatThread(title: "Outside")
        try outsideStore.save(outsideThread)
        let linkID = UUID()
        let link = directory.appendingPathComponent("\(linkID.uuidString).json")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outsideDirectory.appendingPathComponent(
                "\(outsideThread.id.uuidString).json"
            )
        )
        let store = JSONThreadStore(directory: directory)

        let listing = store.listing()

        XCTAssertTrue(listing.threads.isEmpty)
        XCTAssertEqual(listing.issues.map(\.reason), [.symbolicLink])
        XCTAssertThrowsError(try store.load(linkID)) { error in
            XCTAssertEqual(error as? JSONThreadStoreError, .symbolicLink)
        }
    }

    func testListingRejectsSparseOversizedThreadBeforeReadingIt() throws {
        let directory = try makeTempDirectory()
        let id = UUID()
        let fileURL = directory.appendingPathComponent("\(id.uuidString).json")
        XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: UInt64(JSONThreadStore.maximumThreadFileBytes + 1))
        try handle.close()
        let store = JSONThreadStore(directory: directory)

        let listing = store.listing()

        XCTAssertTrue(listing.threads.isEmpty)
        XCTAssertEqual(listing.issues.map(\.reason), [.exceedsSizeLimit])
        XCTAssertThrowsError(try store.load(id)) { error in
            XCTAssertEqual(
                error as? JSONThreadStoreError,
                .exceedsSizeLimit(maximumBytes: JSONThreadStore.maximumThreadFileBytes)
            )
        }
    }

    func testListingRejectsNonFileThreadPath() throws {
        let directory = try makeTempDirectory()
        let id = UUID()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("\(id.uuidString).json"),
            withIntermediateDirectories: false
        )
        let store = JSONThreadStore(directory: directory)

        let listing = store.listing()

        XCTAssertTrue(listing.threads.isEmpty)
        XCTAssertEqual(listing.issues.map(\.reason), [.notRegularFile])
        XCTAssertThrowsError(try store.load(id)) { error in
            XCTAssertEqual(error as? JSONThreadStoreError, .notRegularFile)
        }
    }

    func testListingReportsStorageRootThatIsNotADirectory() throws {
        let rootFile = try makeTempDirectory().appendingPathComponent("threads")
        try Data("not a directory".utf8).write(to: rootFile)

        let listing = JSONThreadStore(directory: rootFile).listing()

        XCTAssertTrue(listing.threads.isEmpty)
        XCTAssertTrue(listing.issues.isEmpty)
        XCTAssertTrue(listing.directoryReadFailed)
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
        XCTAssertEqual(thread.modelContextItems, [])
        XCTAssertNil(thread.goal)
    }
}
