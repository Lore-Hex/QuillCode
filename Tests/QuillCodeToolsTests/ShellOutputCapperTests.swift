import XCTest
import QuillCodeCore
@testable import QuillCodeTools

// MARK: - Unit: the pure capper

final class ShellOutputCapperTests: XCTestCase {
    func testUnderLimitPassesThroughUnchanged() {
        let text = "a\nb\nc"
        let result = ShellOutputCapper.cap(text, maxLines: 100, maxBytes: 10_000)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.text, text)
    }

    func testOverLineLimitKeepsTheTail() {
        let text = (1...3000).map { "line\($0)" }.joined(separator: "\n")
        let result = ShellOutputCapper.cap(text, maxLines: 100, maxBytes: 1_000_000)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.text.contains("output truncated"))
        XCTAssertTrue(result.text.contains("line3000"), "the tail must be kept")     // last line
        XCTAssertFalse(result.text.contains("line1\n"), "early lines must be dropped")
        // note line + 100 kept lines
        XCTAssertLessThanOrEqual(result.text.components(separatedBy: "\n").count, 102)
    }

    func testOverByteLimitTruncates() {
        let text = String(repeating: "x", count: 200_000)
        let result = ShellOutputCapper.cap(text, maxLines: 1_000_000, maxBytes: 1000)
        XCTAssertTrue(result.truncated)
        XCTAssertLessThan(result.text.utf8.count, 2000)
    }

    func testEmptyIsPassthrough() {
        XCTAssertFalse(ShellOutputCapper.cap("").truncated)
    }
}

// MARK: - Functional: through the shell executor with real output

final class ShellToolExecutorCapFunctionalTests: XCTestCase {
    func testExecutorCapsAChattyCommand() {
        let request = ShellExecutionRequest(
            command: "seq 5000",
            cwd: FileManager.default.temporaryDirectory,
            timeoutSeconds: 30
        )
        let result = ShellToolExecutor().run(request)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("output truncated"), "5000 lines should be capped")
        XCTAssertTrue(result.stdout.contains("\n5000"), "the tail (final lines) must survive")
        XCTAssertLessThan(result.stdout.components(separatedBy: "\n").count, 2100, "capped near the 2000-line ceiling")
    }
}

// MARK: - Integration: through the ToolRouter dispatch the agent uses

final class ShellToolOutputCapIntegrationTests: XCTestCase {
    func testRouterDispatchedShellRunIsCapped() {
        let router = ToolRouter(workspaceRoot: FileManager.default.temporaryDirectory)
        let call = ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"seq 5000"}"#)
        let result = router.execute(call)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("output truncated"))
        XCTAssertTrue(result.stdout.contains("\n5000"))
    }
}
