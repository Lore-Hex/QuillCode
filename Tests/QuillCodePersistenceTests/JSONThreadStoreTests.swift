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

    func testThreadStoreCompactsReasoningNoticesBeforeSaving() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        var thread = ChatThread(title: "Bounded reasoning")
        thread.events = (0..<5_000).map {
            ThreadEvent(kind: .notice, summary: "Thinking: token \($0)")
        }

        try store.save(thread)

        let reloaded = try store.load(thread.id)
        XCTAssertEqual(reloaded.events.count, 1)
        XCTAssertEqual(reloaded.events.first?.summary, "Thinking: token 4999")
    }

    func testListingCompactsAndRewritesLegacyReasoningEventLog() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        var thread = ChatThread(title: "Legacy reasoning log")
        thread.events = [ThreadEvent(kind: .message, summary: "Start")] +
            (0..<5_000).map {
                ThreadEvent(kind: .notice, summary: "Thinking: token \($0)")
            } +
            [ThreadEvent(kind: .toolQueued, summary: "host.shell.run queued")]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let fileURL = directory.appendingPathComponent("\(thread.id.uuidString).json")
        try encoder.encode(thread).write(to: fileURL)

        let listing = store.listing()

        XCTAssertEqual(listing.threads.first?.events.count, 3)
        XCTAssertTrue(listing.issues.isEmpty)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(ChatThread.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.events.count, 3)
        XCTAssertEqual(persisted.events[1].summary, "Thinking: token 4999")
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

    func testBootstrapListingDefersOldArchivedPayloadAndUsesValidatedWarmSummary() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        var archived = ChatThread(
            title: "Archived release investigation",
            messages: [
                ChatMessage(role: .user, content: "find the launch regression"),
                ChatMessage(role: .assistant, content: "the cache was rebuilding synchronously")
            ],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        archived.events = [ThreadEvent(kind: .notice, summary: "Preserved event")]
        let active = ChatThread(
            title: "Current work",
            messages: [ChatMessage(role: .user, content: "ship it")],
            updatedAt: cutoff.addingTimeInterval(100)
        )
        try store.save(archived)
        try store.save(active)

        let cold = store.bootstrapListing(deferArchivedBefore: cutoff)

        XCTAssertEqual(cold.deferredThreadCount, 1)
        XCTAssertEqual(cold.summaryCacheHitCount, 0)
        let coldArchive = try XCTUnwrap(cold.threads.first { $0.id == archived.id })
        XCTAssertFalse(coldArchive.payloadResidency.isLoaded)
        XCTAssertTrue(coldArchive.messages.isEmpty)
        XCTAssertTrue(coldArchive.events.isEmpty)
        XCTAssertEqual(
            coldArchive.payloadResidency.deferredSearchText,
            "find the launch regression\nthe cache was rebuilding synchronously"
        )
        XCTAssertTrue(try XCTUnwrap(cold.threads.first { $0.id == active.id }).payloadResidency.isLoaded)

        let warm = store.bootstrapListing(deferArchivedBefore: cutoff)

        XCTAssertEqual(warm.deferredThreadCount, 1)
        XCTAssertEqual(warm.summaryCacheHitCount, 1)
        let fullyListed = try XCTUnwrap(try store.list().first { $0.id == archived.id })
        XCTAssertEqual(fullyListed.messages.map(\.id), archived.messages.map(\.id))
        XCTAssertEqual(fullyListed.messages.map(\.role), archived.messages.map(\.role))
        XCTAssertEqual(fullyListed.messages.map(\.content), archived.messages.map(\.content))
        XCTAssertEqual(try store.load(archived.id).events.map(\.summary), archived.events.map(\.summary))
    }

    func testBootstrapListingInvalidatesChangedArchivedSummary() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        var archived = ChatThread(
            title: "Before",
            messages: [ChatMessage(role: .user, content: "original search")],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try store.save(archived)
        _ = store.bootstrapListing(deferArchivedBefore: cutoff)
        XCTAssertEqual(
            store.bootstrapListing(deferArchivedBefore: cutoff).summaryCacheHitCount,
            1
        )

        archived.title = "After"
        archived.messages.append(ChatMessage(role: .assistant, content: "updated search"))
        try store.save(archived)
        let refreshed = store.bootstrapListing(deferArchivedBefore: cutoff)

        XCTAssertEqual(refreshed.summaryCacheHitCount, 0)
        let summary = try XCTUnwrap(refreshed.threads.first)
        XCTAssertEqual(summary.title, "After")
        XCTAssertEqual(summary.payloadResidency.deferredSearchText, "original search\nupdated search")
    }

    func testBootstrapListingIgnoresCorruptSummaryAndRebuildsItPrivately() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let archived = ChatThread(
            title: "Recoverable archive",
            messages: [ChatMessage(role: .user, content: "recover exact search")],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try store.save(archived)
        _ = store.bootstrapListing(deferArchivedBefore: cutoff)
        let summaryURL = ThreadPayloadSummaryStore.cacheFileURL(
            for: archived.id,
            in: directory
        )
        try Data("not a summary".utf8).write(to: summaryURL)

        let recovered = store.bootstrapListing(deferArchivedBefore: cutoff)

        XCTAssertEqual(recovered.deferredThreadCount, 1)
        XCTAssertEqual(recovered.summaryCacheHitCount, 0)
        XCTAssertEqual(
            recovered.threads.first?.payloadResidency.deferredSearchText,
            "recover exact search"
        )
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: summaryURL.path)[.posixPermissions] as? Int,
            0o600
        )
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(
                atPath: summaryURL.deletingLastPathComponent().path
            )[.posixPermissions] as? Int,
            0o700
        )
        XCTAssertEqual(
            store.bootstrapListing(deferArchivedBefore: cutoff).summaryCacheHitCount,
            1
        )
    }

    func testArchivedRewritePurgesDerivedTranscriptExcerpts() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        var archived = ChatThread(
            title: "Sensitive archive",
            messages: [ChatMessage(role: .user, content: "remove this excerpt")],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try store.save(archived)
        _ = store.bootstrapListing(deferArchivedBefore: cutoff)
        let summaryURL = ThreadPayloadSummaryStore.cacheFileURL(
            for: archived.id,
            in: directory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))

        archived.messages = []
        archived.updatedAt = oldDate.addingTimeInterval(1)
        try store.save(archived)

        XCTAssertFalse(FileManager.default.fileExists(atPath: summaryURL.path))
        XCTAssertTrue(try store.load(archived.id).messages.isEmpty)
    }

    func testWarmBootstrapKeepsLargeArchiveSetAsBoundedSummaries() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let cutoff = Date(timeIntervalSince1970: 1_700_000_000)
        let threadCount = 200
        for index in 0..<threadCount {
            try store.save(ChatThread(
                title: "Archive \(index)",
                messages: [
                    ChatMessage(role: .user, content: "request \(index) " + String(repeating: "x", count: 4_096)),
                    ChatMessage(role: .assistant, content: "answer \(index) " + String(repeating: "y", count: 4_096))
                ],
                isArchived: true,
                createdAt: oldDate,
                updatedAt: oldDate.addingTimeInterval(TimeInterval(index))
            ))
        }

        let cold = store.bootstrapListing(deferArchivedBefore: cutoff)
        let warm = store.bootstrapListing(deferArchivedBefore: cutoff)

        XCTAssertEqual(cold.deferredThreadCount, threadCount)
        XCTAssertEqual(cold.summaryCacheHitCount, 0)
        XCTAssertEqual(warm.deferredThreadCount, threadCount)
        XCTAssertEqual(warm.summaryCacheHitCount, threadCount)
        XCTAssertTrue(warm.threads.allSatisfy {
            !$0.payloadResidency.isLoaded && $0.messages.isEmpty && $0.events.isEmpty
        })
        XCTAssertEqual(try store.list().count, threadCount)
    }

    func testWarmBootstrapBoundsActivePayloadsAndKeepsNewestChatReady() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let activeCount = 40
        let residentLimit = 12
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var newestID: UUID?
        for index in 0..<activeCount {
            let thread = ChatThread(
                title: "Active \(index)",
                messages: [
                    ChatMessage(
                        role: .user,
                        content: "request \(index) " + String(repeating: "x", count: 4_096)
                    )
                ],
                createdAt: baseDate,
                updatedAt: baseDate.addingTimeInterval(TimeInterval(index))
            )
            try store.save(thread)
            newestID = thread.id
        }

        let cold = store.bootstrapListing(
            deferArchivedBefore: .distantPast,
            maximumResidentActivePayloads: residentLimit
        )
        let warm = store.bootstrapListing(
            deferArchivedBefore: .distantPast,
            maximumResidentActivePayloads: residentLimit
        )

        for listing in [cold, warm] {
            let loaded = listing.threads.filter(\.payloadResidency.isLoaded)
            let deferred = listing.threads.filter { !$0.payloadResidency.isLoaded }
            XCTAssertEqual(loaded.count, residentLimit)
            XCTAssertEqual(deferred.count, activeCount - residentLimit)
            XCTAssertEqual(loaded.first?.id, newestID)
            XCTAssertEqual(loaded.first?.messages.first?.content.hasPrefix("request 39"), true)
            XCTAssertTrue(deferred.allSatisfy { $0.messages.isEmpty && $0.events.isEmpty })
        }
        XCTAssertEqual(cold.summaryCacheHitCount, 0)
        XCTAssertEqual(warm.summaryCacheHitCount, activeCount - residentLimit)
    }

    func testDeferredPayloadRetainsCompactSubagentManifestAndHydratesTranscript() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let worker = SubagentWorkerRecord(
            id: "worker",
            name: "Verifier",
            role: "verify release",
            status: .completed,
            summary: "Verified",
            updatedAt: createdAt
        )
        let thread = ChatThread(
            title: "Delegated release",
            messages: [ChatMessage(role: .user, content: "retain the parent transcript")],
            subagentRuns: [SubagentRunRecord(
                objective: "Verify the release",
                workers: [worker],
                createdAt: createdAt,
                updatedAt: createdAt,
                finishedAt: createdAt
            )],
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try store.save(thread)
        try store.save(ChatThread(
            title: "Selected chat",
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(1)
        ))

        let listing = store.bootstrapListing(
            deferArchivedBefore: .distantPast,
            maximumResidentActivePayloads: 0
        )
        let summary = try XCTUnwrap(listing.threads.first { $0.id == thread.id })

        XCTAssertFalse(summary.payloadResidency.isLoaded)
        XCTAssertTrue(summary.messages.isEmpty)
        XCTAssertEqual(summary.subagentRuns.map(\.id), thread.subagentRuns.map(\.id))
        XCTAssertEqual(summary.subagentRuns.map(\.objective), ["Verify the release"])
        let hydrated = try store.materialize(summary)
        XCTAssertEqual(hydrated.messages.map(\.id), thread.messages.map(\.id))
        XCTAssertEqual(hydrated.messages.map(\.content), ["retain the parent transcript"])
        XCTAssertEqual(hydrated.subagentRuns.map(\.id), thread.subagentRuns.map(\.id))
    }

    func testSavingDeferredMetadataPreservesAuthoritativePayload() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        var archived = ChatThread(
            title: "Before",
            messages: [ChatMessage(role: .user, content: "retain me")],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate,
            instructions: [ProjectInstruction(
                path: "/workspace/AGENTS.md",
                title: "AGENTS.md",
                content: "Be exact",
                byteCount: 8
            )]
        )
        archived.events = [ThreadEvent(kind: .notice, summary: "Keep this too")]
        archived.followUpQueue = [FollowUpItem(text: "and this", createdAt: oldDate)]
        try store.save(archived)
        var summary = try XCTUnwrap(
            store.bootstrapListing(
                deferArchivedBefore: Date(timeIntervalSince1970: 1_700_000_000)
            ).threads.first
        )
        XCTAssertFalse(summary.payloadResidency.isLoaded)

        summary.title = "After"
        summary.isPinned = true
        summary.updatedAt = oldDate.addingTimeInterval(60)
        try store.save(summary)

        let persisted = try store.load(archived.id)
        XCTAssertEqual(persisted.title, "After")
        XCTAssertTrue(persisted.isPinned)
        XCTAssertEqual(persisted.messages.map(\.id), archived.messages.map(\.id))
        XCTAssertEqual(persisted.messages.map(\.content), archived.messages.map(\.content))
        XCTAssertEqual(persisted.events.map(\.id), archived.events.map(\.id))
        XCTAssertEqual(persisted.events.map(\.summary), archived.events.map(\.summary))
        XCTAssertEqual(persisted.instructions, archived.instructions)
        XCTAssertEqual(persisted.followUpQueue, archived.followUpQueue)
        XCTAssertTrue(persisted.payloadResidency.isLoaded)
    }

    func testSavingDeferredTranscriptMutationFailsWithoutChangingFile() throws {
        let directory = try makeTempDirectory()
        let store = JSONThreadStore(directory: directory)
        let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
        let archived = ChatThread(
            messages: [ChatMessage(role: .user, content: "authoritative")],
            isArchived: true,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try store.save(archived)
        var summary = try XCTUnwrap(
            store.bootstrapListing(
                deferArchivedBefore: Date(timeIntervalSince1970: 1_700_000_000)
            ).threads.first
        )
        summary.messages.append(ChatMessage(role: .assistant, content: "unsafe partial edit"))

        XCTAssertThrowsError(try store.save(summary)) { error in
            XCTAssertEqual(error as? JSONThreadStoreError, .deferredPayloadMutation)
        }
        let persisted = try store.load(archived.id)
        XCTAssertEqual(persisted.messages.map(\.id), archived.messages.map(\.id))
        XCTAssertEqual(persisted.messages.map(\.content), archived.messages.map(\.content))
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
