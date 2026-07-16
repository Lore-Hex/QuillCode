import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class ShellToolExecutorTests: XCTestCase {
    func testShellRunsWhoami() {
        let result = ShellToolExecutor().run(.init(
            command: "whoami",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory())
        ))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertFalse(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testShellRejectsEmptyCommand() {
        let result = ShellToolExecutor().run(.init(
            command: " ",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory())
        ))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("No shell command") == true)
    }

    func testShellUsesExplicitEnvironment() {
        var environment = ProcessInfo.processInfo.environment
        environment["QUILL_CODE_TEST_ENV"] = "from-shell-request"
        let result = ShellToolExecutor().run(.init(
            command: "printf '%s' \"$QUILL_CODE_TEST_ENV\"",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            environment: environment
        ))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "from-shell-request")
    }

    func testShellUsesSelectedExecutable() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("shell-arguments.txt")
        let shell = try makeRecordingShell(in: root, argumentsFile: argumentsFile)

        let result = ShellToolExecutor().run(.init(
            command: "printf selected-shell",
            cwd: root,
            shellExecutableURL: shell
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "selected-shell")
        XCTAssertEqual(
            try String(contentsOf: argumentsFile, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init),
            ["-lc", "printf selected-shell"]
        )
    }

    func testShellSuppliesBoundedStandardInputAndClosesEOF() {
        let result = ShellToolExecutor().run(.init(
            command: "cat",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            standardInput: "hook payload\n"
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "hook payload\n")
    }

    func testShellDrainsLargeOutputWithoutPipeDeadlock() {
        let result = ShellToolExecutor().run(.init(
            command: "yes quill | head -n 20000",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 5
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("quill"))
    }

    func testCancellableShellStopsLongRunningCommand() async throws {
        let task = Task {
            await ShellToolExecutor().runCancellable(.init(
                command: "sleep 10; echo should-not-print",
                cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
                timeoutSeconds: 20
            ))
        }

        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let result = await task.value

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("cancelled") == true, result.error ?? "")
        XCTAssertFalse(result.stdout.contains("should-not-print"))
    }

    func testStreamingShellYieldsOutputBeforeCompletion() async throws {
        let stream = ShellToolExecutor().runStreaming(.init(
            command: "echo stream-start; sleep 0.2; echo stream-end",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 5
        ))
        var sawStartBeforeFinish = false
        var finishedResult: ToolResult?

        for await event in stream {
            switch event {
            case .stdout(let text):
                if finishedResult == nil, text.contains("stream-start") {
                    sawStartBeforeFinish = true
                }
            case .stderr:
                continue
            case .finished(let result):
                finishedResult = result
            }
        }

        let result = try XCTUnwrap(finishedResult)
        XCTAssertTrue(sawStartBeforeFinish)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("stream-start"))
        XCTAssertTrue(result.stdout.contains("stream-end"))
    }

    func testStreamingShellUsesSelectedExecutable() async throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("stream-shell-arguments.txt")
        let shell = try makeRecordingShell(in: root, argumentsFile: argumentsFile)
        let stream = ShellToolExecutor().runStreaming(.init(
            command: "printf selected-stream-shell",
            cwd: root,
            shellExecutableURL: shell
        ))
        var finishedResult: ToolResult?

        for await event in stream {
            if case .finished(let result) = event { finishedResult = result }
        }

        let result = try XCTUnwrap(finishedResult)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "selected-stream-shell")
        XCTAssertEqual(
            try String(contentsOf: argumentsFile, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init),
            ["-lc", "printf selected-stream-shell"]
        )
    }

    func testStreamingSessionSendsInputToRunningProcess() async throws {
        let session = ShellToolExecutor().startStreamingSession(.init(
            command: "printf 'input? '; IFS= read name; printf 'hello:%s\\n' \"$name\"",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 5
        ))
        var stdout = ""
        var didSendInput = false
        var finishedResult: ToolResult?

        for await event in session.events {
            switch event {
            case .stdout(let text):
                stdout += text
                if stdout.contains("input? "), !didSendInput {
                    XCTAssertTrue(session.sendInput("quill\n"))
                    didSendInput = true
                }
            case .stderr:
                continue
            case .finished(let result):
                finishedResult = result
            }
        }

        let result = try XCTUnwrap(finishedResult)
        XCTAssertTrue(didSendInput)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "input? hello:quill\n")
    }

    func testStreamingShellRejectsEmptyCommand() async throws {
        let stream = ShellToolExecutor().runStreaming(.init(
            command: "   ",
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            timeoutSeconds: 5
        ))

        var events: [ShellProcessEvent] = []
        for await event in stream {
            events.append(event)
        }

        guard case .finished(let result) = events.last else {
            return XCTFail("Expected finished event")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("No shell command") == true, result.error ?? "")
    }

    func testStreamingShellTimeoutKeepsPartialOutputAndStopsProcess() async throws {
        let root = try makeTempDirectory()
        let fifoPath = root.appendingPathComponent("blocked-input").path
            .replacingOccurrences(of: "'", with: "'\\''")
        let stream = ShellToolExecutor().runStreaming(.init(
            command: "mkfifo '\(fifoPath)'; printf stream-start; IFS= read _ < '\(fifoPath)'; printf stream-end",
            cwd: root,
            timeoutSeconds: 0.2
        ))

        var stdout = ""
        var finishedResult: ToolResult?
        for await event in stream {
            switch event {
            case .stdout(let text):
                stdout += text
            case .stderr:
                continue
            case .finished(let result):
                finishedResult = result
            }
        }

        let result = try XCTUnwrap(finishedResult)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("timed out") == true, result.error ?? "")
        XCTAssertTrue(stdout.contains("stream-start"))
        XCTAssertTrue(result.stdout.contains("stream-start"))
        XCTAssertFalse(result.stdout.contains("stream-end"))
    }

    func testSSHRemoteShellBuildsNonInteractiveRequest() throws {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeFakeSSH(in: root, argumentsFile: argumentsFile)
        let request = try XCTUnwrap(SSHRemoteShellExecutor(
            sshExecutable: fakeSSH.path,
            connectTimeoutSeconds: 7
        ).request(
            command: "printf 'hi there'",
            connection: .ssh(
                path: "/srv/quill repo",
                host: "feather.local",
                user: "quill",
                port: 2222
            ),
            timeoutSeconds: 5
        ))

        let result = ShellToolExecutor().run(request)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.stdout, "remote-ok\n")
        let arguments = try String(contentsOf: argumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(arguments, [
            "-T",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=7",
            "-p",
            "2222",
            "--",
            "quill@feather.local",
            "cd '/srv/quill repo' && printf 'hi there'"
        ])
    }

    func testSSHRemoteShellSupportsHomeRelativeRemoteRoots() throws {
        let request = try XCTUnwrap(SSHRemoteShellExecutor(
            sshExecutable: "ssh-test",
            connectTimeoutSeconds: 3
        ).request(
            command: "pwd",
            connection: .ssh(path: "~/Quill Projects", host: "feather.local")
        ))

        XCTAssertTrue(request.command.contains("'ssh-test'"))
        XCTAssertTrue(request.command.contains("'ConnectTimeout=3'"))
        XCTAssertTrue(request.command.contains("'feather.local'"))
        XCTAssertTrue(request.command.contains("cd ~/"))
        XCTAssertTrue(request.command.contains("'Quill Projects'"))
    }

    func testSSHRemoteShellRejectsUnsafeDestinationFields() {
        XCTAssertNil(SSHRemoteShellExecutor().request(
            command: "pwd",
            connection: .ssh(path: "/srv/quill", host: "bad host", user: "quill")
        ))
        XCTAssertNil(SSHRemoteShellExecutor().request(
            command: "pwd",
            connection: .ssh(path: "/srv/quill", host: "feather.local", user: "bad user")
        ))
        XCTAssertNil(SSHRemoteShellExecutor().request(
            command: "pwd",
            connection: .ssh(path: "/srv/quill", host: "feather.local", port: 70_000)
        ))
    }

    func testSSHRemoteShellRejectsOptionInjectingDestination() {
        // A host/user beginning with `-` would be parsed by ssh as an option flag (e.g.
        // `-oProxyCommand=…` runs a local command), so it must be rejected outright.
        XCTAssertNil(SSHRemoteShellExecutor().request(
            command: "pwd",
            connection: .ssh(path: "/srv/quill", host: "-oProxyCommand=touch${IFS}/tmp/pwned")
        ))
        XCTAssertNil(SSHRemoteShellExecutor().request(
            command: "pwd",
            connection: .ssh(path: "/srv/quill", host: "feather.local", user: "-oProxyCommand=x")
        ))
    }

    func testSSHRemoteShellTerminatesOptionsBeforeDestination() throws {
        // Defense-in-depth: `--` precedes the destination so it can never be read as an option.
        let request = try XCTUnwrap(SSHRemoteShellExecutor(sshExecutable: "ssh-test").request(
            command: "pwd",
            connection: .ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        ))
        XCTAssertTrue(request.command.contains("'--' 'quill@feather.local'"), request.command)
    }
}
