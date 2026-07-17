@testable import QuillCodeCLI
import XCTest

final class AppServerExecServerPendingResponseRegistryTests: XCTestCase {
    func testRegisterRejectsDuplicateRequestIDWithoutReplacingPendingResponse() throws {
        var registry = AppServerExecServerPendingResponseRegistry()
        let first = AsyncThrowingStream<CLIJSONValue, Error>.makeStream()
        let duplicate = AsyncThrowingStream<CLIJSONValue, Error>.makeStream()

        try registry.register(
            requestID: 7,
            generation: 1,
            continuation: first.continuation
        )

        XCTAssertThrowsError(try registry.register(
            requestID: 7,
            generation: 2,
            continuation: duplicate.continuation
        )) { error in
            XCTAssertEqual(
                error as? AppServerExecServerError,
                .invalidResponse("duplicate pending response for request id 7")
            )
        }

        let pending = try XCTUnwrap(try registry.take(7))
        XCTAssertEqual(pending.generation, 1)
    }

    func testRegisterRejectsRequestIDUntilAbandonedResponseArrives() throws {
        var registry = AppServerExecServerPendingResponseRegistry()
        let first = AsyncThrowingStream<CLIJSONValue, Error>.makeStream()
        let reused = AsyncThrowingStream<CLIJSONValue, Error>.makeStream()

        try registry.register(
            requestID: 9,
            generation: 1,
            continuation: first.continuation
        )
        XCTAssertTrue(registry.abandon(9))

        XCTAssertThrowsError(try registry.register(
            requestID: 9,
            generation: 2,
            continuation: reused.continuation
        )) { error in
            XCTAssertEqual(
                error as? AppServerExecServerError,
                .invalidResponse("request id 9 is still waiting for an abandoned response")
            )
        }

        XCTAssertNil(try registry.take(9))
        try registry.register(
            requestID: 9,
            generation: 2,
            continuation: reused.continuation
        )
        let pending = try XCTUnwrap(try registry.take(9))
        XCTAssertEqual(pending.generation, 2)
    }
}
