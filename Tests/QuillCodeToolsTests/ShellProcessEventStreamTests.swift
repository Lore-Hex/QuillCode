import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class ShellProcessEventStreamTests: XCTestCase {
    func testPendingEventsKeepNewestBoundAndTerminalCompletion() async {
        let (stream, continuation) = ShellProcessEventStream.makeStream()
        for index in 0..<(ShellProcessEventStream.maximumPendingEventCount * 4) {
            continuation.yield(.stdout("chunk-\(index)"))
        }
        continuation.yield(.finished(ToolResult(ok: true, stdout: "done", exitCode: 0)))
        continuation.finish()

        var events: [ShellProcessEvent] = []
        for await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, ShellProcessEventStream.maximumPendingEventCount)
        guard case .finished(let result) = events.last else {
            return XCTFail("The terminal completion event must remain the newest buffered event.")
        }
        XCTAssertEqual(result.stdout, "done")
        XCTAssertFalse(events.contains(.stdout("chunk-0")))
    }
}
