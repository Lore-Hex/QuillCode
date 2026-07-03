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
    }
}
