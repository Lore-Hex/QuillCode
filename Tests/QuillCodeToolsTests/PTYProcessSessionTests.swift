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

    func testAcceptsInputThroughTheMasterPTY() async throws {
        let request = ShellExecutionRequest(
            command: "printf 'input? '; IFS= read name; printf 'hello:%s\\n' \"$name\"",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 5
        )
        let session = PTYProcessSession(request: request)
        let capture = EventCapture()

        session.start()
        let drainTask = Task {
            for await event in session.events {
                await capture.record(event)
            }
        }

        var didSendInput = false
        let deadline = Date().addingTimeInterval(2)
        while !didSendInput, Date() < deadline {
            didSendInput = session.sendInput("quill\n")
            if !didSendInput {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        XCTAssertTrue(didSendInput, "Expected PTY input to become writable while the command was active.")
        await drainTask.value

        let output = await capture.normalizedOutput()
        XCTAssertTrue(output.contains("input? "), "Expected prompt output, got: \(output)")
        XCTAssertTrue(output.contains("quill\n"), "Expected canonical terminal echo, got: \(output)")
        XCTAssertTrue(output.contains("hello:quill\n"), "Expected command to consume stdin, got: \(output)")
        let result = await capture.capturedResult()
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

    func testResizeUpdatesARunningSessionsWindow() async throws {
        let request = ShellExecutionRequest(
            command: "read x; stty size",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 15
        )
        let session = PTYProcessSession(request: request, windowSize: PTYWindowSize(rows: 24, columns: 80))
        session.start()

        // Resize the live session, then unblock the read so `stty size` reports the new size.
        var resized = false
        for _ in 0..<300 {
            if session.resize(to: PTYWindowSize(rows: 30, columns: 100)) {
                resized = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(resized, "Expected to resize the running pty session.")
        _ = session.sendInput("\n")

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

        XCTAssertTrue(output.contains("30 100"), "Expected the resized terminal size, got: \(output)")
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

private actor EventCapture {
    private var output = ""
    private(set) var result: ToolResult?

    func record(_ event: ShellProcessEvent) {
        switch event {
        case .stdout(let text), .stderr(let text):
            output += text
        case .finished(let toolResult):
            result = toolResult
        }
    }

    func normalizedOutput() -> String {
        output.replacingOccurrences(of: "\r\n", with: "\n")
    }

    func capturedResult() -> ToolResult? {
        result
    }
}
