import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class PTYProcessMemoryBoundTests: XCTestCase {
    func testFinishedResultBoundsChattyPTYOutputAndKeepsTail() async throws {
        let request = ShellExecutionRequest(
            command: "yes terminal-tail | head -n 40000",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 15
        )
        let session = PTYProcessSession(request: request)
        session.start()

        var result: ToolResult?
        for await event in session.events {
            if case .finished(let finished) = event {
                result = finished
            }
        }

        let finished = try XCTUnwrap(result)
        XCTAssertTrue(finished.ok, finished.error ?? "")
        XCTAssertTrue(finished.stdout.contains("output truncated"), finished.stdout.prefix(120).description)
        XCTAssertTrue(finished.stdout.hasSuffix("terminal-tail\r\nterminal-tail\r\n"))
        XCTAssertLessThan(finished.stdout.utf8.count, 60_000)
    }
}
