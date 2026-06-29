import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class PTYProcessSessionTests: XCTestCase {
    private func drain(_ command: String, timeout: TimeInterval = 15) async -> (output: String, result: ToolResult?) {
        let request = ShellExecutionRequest(
            command: command,
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: timeout
        )
        let session = PTYProcessSession(request: request)
        session.start()
        var output = ""
        var result: ToolResult?
        for await event in session.events {
            switch event {
            case .stdout(let text), .stderr(let text):
                output += text
            case .finished(let toolResult):
                result = toolResult
            }
        }
        return (output, result)
    }

    func testCommandObservesATTYOnStandardOutput() async throws {
        let (output, result) = await drain("test -t 1 && echo TTY || echo NOTTY")

        XCTAssertTrue(output.contains("TTY"), "Expected the command to see a TTY on stdout, got: \(output)")
        XCTAssertFalse(output.contains("NOTTY"), "A PTY-backed run should not report a non-tty stdout.")
        XCTAssertEqual(result?.ok, true)
        XCTAssertEqual(result?.exitCode, 0)
    }

    func testCapturesCommandOutput() async throws {
        let (output, result) = await drain("printf 'hello-pty'")

        XCTAssertTrue(output.contains("hello-pty"), "Expected captured output, got: \(output)")
        XCTAssertEqual(result?.ok, true)
        XCTAssertEqual(result?.exitCode, 0)
    }

    func testReportsNonZeroExitCode() async throws {
        let (_, result) = await drain("exit 3")

        XCTAssertEqual(result?.ok, false)
        XCTAssertEqual(result?.exitCode, 3)
        XCTAssertNotNil(result?.error)
    }

    func testEmptyCommandFinishesWithGuidance() async throws {
        let (_, result) = await drain("   ")

        XCTAssertEqual(result?.ok, false)
        XCTAssertEqual(result?.error, ShellToolMessages.missingCommand)
    }
}
