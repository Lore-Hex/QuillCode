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
}
