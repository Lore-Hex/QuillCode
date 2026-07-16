import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class MCPProgressTrackerTests: XCTestCase {
    func testTrackerAcceptsOnlyMatchingStrictlyIncreasingProgress() throws {
        var tracker = MCPProgressTracker(token: .string("progress-1"))

        XCTAssertNil(tracker.consume(notification(token: "other", progress: 1)))
        XCTAssertEqual(
            tracker.consume(notification(token: "progress-1", progress: 10, total: 100, message: " Indexing\nfiles ")),
            .init(completed: 10, total: 100, message: "Indexing files")
        )
        XCTAssertNil(tracker.consume(notification(token: "progress-1", progress: 10)))
        XCTAssertNil(tracker.consume(notification(token: "progress-1", progress: 9)))
        XCTAssertEqual(
            tracker.consume(notification(token: "progress-1", progress: 20, total: -1)),
            .init(completed: 20)
        )
    }

    func testTrackerBoundsAcceptedUpdatesAndMessages() {
        var tracker = MCPProgressTracker(token: .integer(17))
        let oversizedMessage = String(repeating: "x", count: 400)

        for progress in 0..<256 {
            XCTAssertNotNil(tracker.consume(notification(
                token: 17,
                progress: progress,
                message: oversizedMessage
            )))
        }
        XCTAssertNil(tracker.consume(notification(token: 17, progress: 256)))
        XCTAssertEqual(tracker.acceptedCount, 256)
        XCTAssertEqual(tracker.lastCompleted, 255)
    }

    func testTrackerRejectsJSONBooleansAsTokensAndProgressValues() {
        XCTAssertNil(MCPProgressToken(true))

        var tracker = MCPProgressTracker(token: .string("token"))
        XCTAssertNil(tracker.consume(notification(token: true, progress: 1)))
        XCTAssertNil(tracker.consume(notification(token: "token", progress: true)))
        XCTAssertEqual(tracker.acceptedCount, 0)
    }

    func testTrackerAcceptsFoundationNumbersThatEqualBooleanBitPatterns() throws {
        let data = try JSONSerialization.data(withJSONObject: notification(
            token: 1,
            progress: 1.0,
            total: 2.0
        ))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var tracker = MCPProgressTracker(token: .integer(1))

        XCTAssertEqual(
            tracker.consume(object),
            .init(completed: 1, total: 2)
        )
    }

    func testRequestContextPreservesMetadataAndValidatesShape() throws {
        let context = try MCPProgressRequestContext(metadata: .object([
            "requestID": .string("request-1"),
            "progressToken": .number(42)
        ]))

        XCTAssertEqual(context.token, .integer(42))
        XCTAssertEqual(context.metadata["requestID"], .string("request-1"))
        XCTAssertEqual(context.metadata["progressToken"], .number(42))
        XCTAssertThrowsError(try MCPProgressRequestContext(metadata: .string("invalid")))
    }

    private func notification(
        token: Any,
        progress: Any,
        total: Any? = nil,
        message: String? = nil
    ) -> [String: Any] {
        var params: [String: Any] = ["progressToken": token, "progress": progress]
        if let total { params["total"] = total }
        if let message { params["message"] = message }
        return ["jsonrpc": "2.0", "method": "notifications/progress", "params": params]
    }
}
