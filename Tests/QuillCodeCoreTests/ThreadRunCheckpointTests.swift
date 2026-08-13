import Foundation
import XCTest
@testable import QuillCodeCore

final class ThreadRunCheckpointTests: XCTestCase {
    func testCheckpointRoundTripsWithThread() throws {
        let checkpoint = ThreadRunCheckpoint(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            messageCountAtStart: 3,
            eventCountAtStart: 7
        )

        let data = try JSONEncoder().encode(ChatThread(activeRunCheckpoint: checkpoint))
        let decoded = try JSONDecoder().decode(ChatThread.self, from: data)

        XCTAssertEqual(decoded.activeRunCheckpoint, checkpoint)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains(#""schemaVersion":1"#), json)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("prompt"), json)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("arguments"), json)
    }

    func testLegacyThreadWithoutCheckpointDecodesAsIdle() throws {
        let thread = ChatThread()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(thread)) as? [String: Any]
        )
        object.removeValue(forKey: "activeRunCheckpoint")

        let decoded = try JSONDecoder().decode(
            ChatThread.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.activeRunCheckpoint)
    }

    func testCheckpointNormalizesNegativeBoundaries() throws {
        let checkpoint = ThreadRunCheckpoint(
            messageCountAtStart: -1,
            eventCountAtStart: -2
        )

        XCTAssertEqual(checkpoint.messageCountAtStart, 0)
        XCTAssertEqual(checkpoint.eventCountAtStart, 0)
    }
}
