import Foundation
import XCTest
@testable import QuillCodePersistence

final class ComposerDraftCheckpointStoreTests: PersistenceTestCase {
    func testRoundTripsDraftAndDurableTombstoneWithPrivatePermissions() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("composer-drafts", isDirectory: true)
        let store = ComposerDraftCheckpointStore(directory: directory)
        let threadID = UUID()

        try store.save("half-written plan", for: threadID)

        XCTAssertEqual(
            try store.load(for: threadID),
            ComposerDraftCheckpoint(threadID: threadID, draft: "half-written plan")
        )
        XCTAssertEqual(try posixPermissions(at: directory), 0o700)
        XCTAssertEqual(try posixPermissions(at: checkpointURL(directory: directory, threadID: threadID)), 0o600)

        try store.save(" \n ", for: threadID)
        let tombstone = try XCTUnwrap(store.load(for: threadID))
        XCTAssertNil(tombstone.draft)
    }

    func testThreadAndPendingCheckpointsRemainIndependent() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts", isDirectory: true)
        )
        let firstID = UUID()
        let secondID = UUID()

        try store.save("pending first message", for: nil)
        try store.save("first", for: firstID)
        try store.save("second", for: secondID)

        XCTAssertEqual(try store.load(for: nil)?.draft, "pending first message")
        XCTAssertEqual(try store.load(for: firstID)?.draft, "first")
        XCTAssertEqual(try store.load(for: secondID)?.draft, "second")

        try store.delete(for: firstID)
        XCTAssertNil(try store.load(for: firstID))
        XCTAssertEqual(try store.load(for: secondID)?.draft, "second")
    }

    func testRejectsOversizedDraftWithoutReplacingPreviousCheckpoint() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ComposerDraftCheckpointStore(
            directory: root.appendingPathComponent("composer-drafts", isDirectory: true)
        )
        let threadID = UUID()
        try store.save("known good", for: threadID)

        XCTAssertThrowsError(try store.save(
            String(repeating: "x", count: ComposerDraftCheckpointStore.maximumDraftBytes + 1),
            for: threadID
        )) { error in
            XCTAssertEqual(
                error as? ComposerDraftCheckpointStoreError,
                .draftExceedsSizeLimit(maximumBytes: ComposerDraftCheckpointStore.maximumDraftBytes)
            )
        }
        XCTAssertEqual(try store.load(for: threadID)?.draft, "known good")
    }

    func testRejectsMismatchedAndSymlinkedRecords() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("composer-drafts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ComposerDraftCheckpointStore(directory: directory)
        let requestedID = UUID()
        let destination = checkpointURL(directory: directory, threadID: requestedID)
        let encoder = JSONEncoder()
        try encoder.encode(ComposerDraftCheckpoint(
            threadID: UUID(),
            draft: "wrong owner"
        )).write(to: destination)

        XCTAssertThrowsError(try store.load(for: requestedID)) { error in
            XCTAssertEqual(error as? ComposerDraftCheckpointStoreError, .invalidRecord)
        }

        try FileManager.default.removeItem(at: destination)
        let target = root.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
        XCTAssertThrowsError(try store.load(for: requestedID)) { error in
            XCTAssertEqual(error as? BoundedFileDataError, .symbolicLink)
        }
    }

    private func checkpointURL(directory: URL, threadID: UUID) -> URL {
        directory
            .appendingPathComponent("thread-\(threadID.uuidString.lowercased())")
            .appendingPathExtension("json")
    }
}
