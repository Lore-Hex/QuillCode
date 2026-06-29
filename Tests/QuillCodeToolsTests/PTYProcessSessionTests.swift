import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class PTYProcessSessionTests: XCTestCase {
    private func drain(
        _ command: String,
        windowSize: PTYWindowSize? = nil,
        timeout: TimeInterval = 15
    ) async -> (output: String, result: ToolResult?) {
        let request = ShellExecutionRequest(
            command: command,
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: timeout
        )
        let session = PTYProcessSession(request: request, windowSize: windowSize)
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

    func testPropagatesWindowSizeToTheChild() async throws {
        let (output, result) = await drain("stty size", windowSize: PTYWindowSize(rows: 24, columns: 80))

        XCTAssertTrue(output.contains("24 80"), "Expected the child to see the configured terminal size, got: \(output)")
        XCTAssertEqual(result?.ok, true)
    }

    func testSendInputDrivesAnInteractiveRead() async throws {
        let request = ShellExecutionRequest(
            command: "read x; echo \"got:$x\"",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 15
        )
        let session = PTYProcessSession(request: request)
        session.start()

        // The master fd becomes writable once the child has launched; retry until ready.
        var delivered = false
        for _ in 0..<300 {
            if session.sendInput("hello\n") {
                delivered = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(delivered, "Expected to deliver typed input to the pty master.")

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

        XCTAssertTrue(output.contains("got:hello"), "Expected the interactive read to receive input, got: \(output)")
        XCTAssertEqual(result?.ok, true)
    }

    func testSendInputIsRejectedAfterTheSessionFinishes() async throws {
        let request = ShellExecutionRequest(
            command: "printf done",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 15
        )
        let session = PTYProcessSession(request: request)
        session.start()
        for await event in session.events {
            if case .finished = event { break }
        }

        XCTAssertFalse(session.sendInput("late\n"), "A finished session must not accept further input.")
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
