import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class PTYProcessSessionTests: XCTestCase {
    private func drain(
        _ command: String,
        windowSize: PTYWindowSize? = nil,
        timeout: TimeInterval = 15,
        environment: [String: String]? = nil
    ) async -> (output: String, result: ToolResult?) {
        let request = ShellExecutionRequest(
            command: command,
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: timeout,
            environment: environment
        )
        let session = PTYProcessSession(request: request, windowSize: windowSize)
        session.start()
        return await collect(session)
    }

    private func makeSession(
        command: String,
        timeout: TimeInterval = 15,
        windowSize: PTYWindowSize? = nil
    ) -> PTYProcessSession {
        let request = ShellExecutionRequest(
            command: command,
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: timeout
        )
        return PTYProcessSession(request: request, windowSize: windowSize)
    }

    private func collect(_ session: PTYProcessSession) async -> (output: String, result: ToolResult?) {
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

    private func waitUntilPTYAccepts(_ action: () -> Bool) async throws -> Bool {
        for _ in 0..<300 {
            if action() {
                return true
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private func waitForFinish(_ session: PTYProcessSession) async {
        for await event in session.events {
            if case .finished = event {
                break
            }
        }
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

        XCTAssertTrue(
            output.contains("24 80"),
            "Expected the child to see the configured terminal size, got: \(output)"
        )
        XCTAssertEqual(result?.ok, true)
    }

    func testSendInputDrivesAnInteractiveRead() async throws {
        let session = makeSession(command: "read x; echo \"got:$x\"")
        session.start()

        // The master fd becomes writable once the child has launched; retry until ready.
        let delivered = try await waitUntilPTYAccepts { session.sendInput("hello\n") }
        XCTAssertTrue(delivered, "Expected to deliver typed input to the pty master.")

        let (output, result) = await collect(session)

        XCTAssertTrue(output.contains("got:hello"), "Expected the interactive read to receive input, got: \(output)")
        XCTAssertEqual(result?.ok, true)
    }

    func testResizeUpdatesARunningSessionsWindow() async throws {
        let session = makeSession(
            command: "read x; stty size",
            windowSize: PTYWindowSize(rows: 24, columns: 80)
        )
        session.start()

        // Resize the live session, then unblock the read so `stty size` reports the new size.
        let resized = try await waitUntilPTYAccepts {
            session.resize(to: PTYWindowSize(rows: 30, columns: 100))
        }
        XCTAssertTrue(resized, "Expected to resize the running pty session.")
        _ = session.sendInput("\n")

        let (output, result) = await collect(session)

        XCTAssertTrue(output.contains("30 100"), "Expected the resized terminal size, got: \(output)")
        XCTAssertEqual(result?.ok, true)
    }

    func testSendInputIsRejectedAfterTheSessionFinishes() async throws {
        let session = makeSession(command: "printf done")
        session.start()
        await waitForFinish(session)

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

    func testSuspendAndResumeAreRejectedBeforeStartAndAfterFinish() async throws {
        let session = makeSession(command: "printf done")

        // Before start there is no process to signal.
        XCTAssertFalse(session.suspend(), "Cannot suspend a session that has not started.")
        XCTAssertFalse(session.resume(), "Cannot resume a session that has not started.")
        XCTAssertFalse(session.isSuspended)

        session.start()
        await waitForFinish(session)

        // After the command finishes, job-control signals are no-ops.
        XCTAssertFalse(session.suspend(), "A finished session cannot be suspended.")
        XCTAssertFalse(session.resume(), "A finished session cannot be resumed.")
        XCTAssertFalse(session.isSuspended)
    }

    func testSuspendThenResumeStillDrivesTheRunningProcess() async throws {
        let session = makeSession(command: "read x; echo \"got:$x\"")
        session.start()

        // A successful suspend both proves the child has launched and (SIGSTOP being uncatchable)
        // deterministically guarantees it is stopped — no timing race on output.
        let suspended = try await waitUntilPTYAccepts { session.suspend() }
        XCTAssertTrue(suspended, "Expected to suspend the running child.")
        XCTAssertTrue(session.isSuspended)
        XCTAssertFalse(session.suspend(), "Suspending an already-suspended session is a no-op.")

        XCTAssertTrue(session.resume(), "Expected to resume the suspended child.")
        XCTAssertFalse(session.isSuspended)
        XCTAssertFalse(session.resume(), "Resuming a non-suspended session is a no-op.")

        // The resumed process must still accept input and run to completion — proving resume restored
        // it rather than leaving it stopped.
        let delivered = try await waitUntilPTYAccepts { session.sendInput("hello\n") }
        XCTAssertTrue(delivered, "Expected to deliver input to the resumed session.")

        let (output, result) = await collect(session)

        XCTAssertTrue(output.contains("got:hello"), "Expected the resumed read to receive input, got: \(output)")
        XCTAssertEqual(result?.ok, true)
    }

    func testCancellingASuspendedProcessStillTerminatesIt() async throws {
        // The load-bearing path: cancel() must SIGCONT-before-terminate, or a SIGSTOP-ped child would
        // ignore the SIGTERM and the run would hang to the timeout. The 90s timeout is far above the
        // expected near-instant cancellation, so a finished stream proves termination, not a time-out.
        let session = makeSession(command: "sleep 90", timeout: 90)
        session.start()

        let suspended = try await waitUntilPTYAccepts { session.suspend() }
        XCTAssertTrue(suspended, "Expected to suspend the running sleep.")

        session.cancel()

        let (_, result) = await collect(session)

        // Without the SIGCONT before terminate, the stopped sleep would never receive the SIGTERM and
        // this stream would not finish until the 90s timeout — the test would visibly hang.
        XCTAssertEqual(result?.ok, false, "A cancelled suspended process must still terminate.")
    }

    func testPTYDisablesTheInteractivePagerByDefault() async throws {
        // Without this, a real PTY makes git log/diff launch a pager that blocks for keypresses and the
        // command hangs to the timeout. The child should see the pager variables set to a passthrough.
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let (output, result) = await drain(
            "echo \"PAGER=[$PAGER] GIT_PAGER=[$GIT_PAGER] MANPAGER=[$MANPAGER]\"",
            environment: ["PATH": path]
        )
        XCTAssertTrue(output.contains("PAGER=[cat]"), "Expected PAGER=cat, got: \(output)")
        XCTAssertTrue(output.contains("GIT_PAGER=[cat]"), "Expected GIT_PAGER=cat, got: \(output)")
        XCTAssertTrue(output.contains("MANPAGER=[cat]"), "Expected MANPAGER=cat, got: \(output)")
        XCTAssertEqual(result?.ok, true)
    }

    func testPTYForcesPagerEvenWhenInherited() async throws {
        // An inherited or captured PAGER/MANPAGER=less (from the launching shell or a prior in-pane
        // `export`) must be OVERRIDDEN — the pane cannot host an interactive pager, and respecting the
        // value would re-introduce the hang. This is the load-bearing production case.
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let (output, _) = await drain(
            "echo \"PAGER=[$PAGER] MANPAGER=[$MANPAGER]\"",
            environment: ["PATH": path, "PAGER": "less", "MANPAGER": "less"]
        )
        XCTAssertTrue(output.contains("PAGER=[cat]"), "Inherited PAGER must be forced to cat, got: \(output)")
        XCTAssertTrue(output.contains("MANPAGER=[cat]"), "Inherited MANPAGER must be forced to cat, got: \(output)")
    }
}
