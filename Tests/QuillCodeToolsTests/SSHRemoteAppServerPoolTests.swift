import Foundation
import QuillCodeCore
@testable import QuillCodeTools
import XCTest

final class SSHRemoteAppServerPoolTests: XCTestCase {
    func testExecutesCommandsThroughOnePersistentRemoteAppServer() async throws {
        let fixture = try makeFixture(mode: "success")
        defer { fixture.remove() }
        let pool = fixture.pool()

        let first = await pool.execute(
            command: "printf first",
            connection: fixture.connection,
            timeoutSeconds: 3
        )
        let second = await pool.execute(
            command: "printf second",
            connection: fixture.connection,
            timeoutSeconds: 3
        )
        await pool.disconnectAll()

        XCTAssertEqual(first, .completed(ToolResult(ok: true, stdout: "remote-1\n", exitCode: 0)))
        XCTAssertEqual(second, .completed(ToolResult(ok: true, stdout: "remote-2\n", exitCode: 0)))
        XCTAssertEqual(try fixture.startCount(), 1)

        let messages = try fixture.messages()
        XCTAssertEqual(messages.filter { $0.contains(#""method":"initialize""#) }.count, 1)
        XCTAssertEqual(messages.filter { $0.contains(#""method":"command/exec""#) }.count, 2)
        XCTAssertTrue(messages.contains { $0.contains(#""printf first""#) })
        XCTAssertTrue(messages.contains { $0.contains(#""printf second""#) })

        let arguments = try fixture.sshArguments()
        XCTAssertEqual(Array(arguments.prefix(8)), [
            "-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=2", "-p", "2222", "--"
        ])
        XCTAssertEqual(arguments[8], "quill@feather.local")
        XCTAssertTrue(arguments[9].contains("cd \(shellQuoted(fixture.remoteRoot.path))"), arguments[9])
        XCTAssertTrue(arguments[9].contains("app-server --stdio"), arguments[9])
    }

    func testReportsUnavailableBeforeExecutionWhenRemoteBinaryCannotStart() async throws {
        let fixture = try makeFixture(mode: "success")
        defer { fixture.remove() }
        let pool = fixture.pool(quillCodeExecutable: fixture.root.appendingPathComponent("missing-quill-code").path)

        let outcome = await pool.execute(
            command: "touch should-not-run",
            connection: fixture.connection,
            timeoutSeconds: 2
        )
        await pool.disconnectAll()

        guard case .unavailableBeforeExecution(let detail) = outcome else {
            return XCTFail("Expected pre-execution unavailability, got \(outcome)")
        }
        XCTAssertFalse(detail.isEmpty)
        XCTAssertFalse(try fixture.messages().contains { $0.contains("touch should-not-run") })
    }

    func testDoesNotClassifyDisconnectAfterDispatchAsSafeToRetry() async throws {
        let fixture = try makeFixture(mode: "disconnect-after-command")
        defer { fixture.remove() }
        let pool = fixture.pool()

        let outcome = await pool.execute(
            command: "touch may-have-run",
            connection: fixture.connection,
            timeoutSeconds: 2
        )
        await pool.disconnectAll()

        guard case .executionStateUnknown(let detail) = outcome else {
            return XCTFail("Expected unknown execution state, got \(outcome)")
        }
        XCTAssertFalse(detail.isEmpty)
        XCTAssertEqual(
            try fixture.messages().filter { $0.contains(#""method":"command/exec""#) }.count,
            1
        )
    }

    func testMapsNonzeroRemoteExitCodeWithoutDroppingOutput() async throws {
        let fixture = try makeFixture(mode: "failure")
        defer { fixture.remove() }
        let pool = fixture.pool()

        let outcome = await pool.execute(
            command: "false",
            connection: fixture.connection,
            timeoutSeconds: 2
        )
        await pool.disconnectAll()

        XCTAssertEqual(
            outcome,
            .completed(ToolResult(
                ok: false,
                stdout: "partial\n",
                stderr: "failed\n",
                exitCode: 7,
                error: "Command failed with exit code 7."
            ))
        )
    }

    func testDefinitiveRPCRejectionDoesNotBecomeUnknownOrBreakTheSession() async throws {
        let fixture = try makeFixture(mode: "response-error-once")
        defer { fixture.remove() }
        let pool = fixture.pool()

        let rejected = await pool.execute(
            command: "first",
            connection: fixture.connection,
            timeoutSeconds: 2
        )
        let recovered = await pool.execute(
            command: "second",
            connection: fixture.connection,
            timeoutSeconds: 2
        )
        await pool.disconnectAll()

        guard case .completed(let rejection) = rejected else {
            return XCTFail("Expected a definitive completed rejection, got \(rejected)")
        }
        XCTAssertFalse(rejection.ok)
        XCTAssertTrue(rejection.error?.contains("profile denied") == true, rejection.error ?? "")
        XCTAssertEqual(recovered, .completed(ToolResult(ok: true, stdout: "remote-2\n", exitCode: 0)))
        XCTAssertEqual(try fixture.startCount(), 1, "A server-declared error must not tear down a healthy session.")
    }

    func testCancellationDropsUncertainSessionBeforeNextCommand() async throws {
        let fixture = try makeFixture(mode: "hang-first-process")
        defer { fixture.remove() }
        let pool = fixture.pool()

        let hangingCommand = Task {
            await pool.execute(
                command: "touch may-have-run-before-cancellation",
                connection: fixture.connection,
                timeoutSeconds: 30
            )
        }
        try await waitUntil(timeoutSeconds: 2) {
            try fixture.messages().contains { $0.contains("touch may-have-run-before-cancellation") }
        }

        hangingCommand.cancel()
        let cancelled = await hangingCommand.value
        let recovered = await pool.execute(
            command: "printf recovered",
            connection: fixture.connection,
            timeoutSeconds: 2
        )
        await pool.disconnectAll()

        guard case .executionStateUnknown = cancelled else {
            return XCTFail("Cancellation after dispatch must remain ambiguous, got \(cancelled)")
        }
        XCTAssertEqual(recovered, .completed(ToolResult(ok: true, stdout: "remote-1\n", exitCode: 0)))
        XCTAssertEqual(try fixture.startCount(), 2, "The next command must use a fresh app-server process.")
    }

    private func makeFixture(mode: String) throws -> SSHRemoteAppServerFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-ssh-app-server-tests-\(UUID().uuidString)", isDirectory: true)
        let remoteRoot = root.appendingPathComponent("remote project", isDirectory: true)
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)

        let messagesURL = root.appendingPathComponent("messages.jsonl")
        let startsURL = root.appendingPathComponent("starts.log")
        let sshArgumentsURL = root.appendingPathComponent("ssh-arguments.txt")
        let appServerURL = root.appendingPathComponent("fake-quill-code")
        let sshURL = root.appendingPathComponent("fake-ssh")

        try #"""
        #!/bin/sh
        printf 'started\n' >> "$QUILLCODE_TEST_STARTS"
        process_number=$(wc -l < "$QUILLCODE_TEST_STARTS" | tr -d ' ')
        count=0
        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$QUILLCODE_TEST_MESSAGES"
          id=$(printf '%s\n' "$line" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p')
          case "$line" in
            *'"method":"initialize"'*)
              printf '{"id":%s,"result":{}}\n' "$id"
              ;;
            *'"method":"command/exec"'*|*'"method":"command\/exec"'*)
              count=$((count + 1))
              case "$QUILLCODE_TEST_MODE" in
                disconnect-after-command) exit 0 ;;
                failure)
                  printf '{"id":%s,"result":{"exitCode":7,"stderr":"failed\\n","stdout":"partial\\n"}}\n' "$id"
                  ;;
                response-error-once)
                  if [ "$count" -eq 1 ]; then
                    printf '{"error":{"code":-32600,"message":"profile denied"},"id":%s}\n' "$id"
                  else
                    printf '{"id":%s,"result":{"exitCode":0,"stderr":"","stdout":"remote-%s\\n"}}\n' "$id" "$count"
                  fi
                  ;;
                hang-first-process)
                  if [ "$process_number" -eq 1 ]; then
                    while :; do sleep 1; done
                  else
                    printf '{"id":%s,"result":{"exitCode":0,"stderr":"","stdout":"remote-%s\\n"}}\n' "$id" "$count"
                  fi
                  ;;
                *)
                  printf '{"id":%s,"result":{"exitCode":0,"stderr":"","stdout":"remote-%s\\n"}}\n' "$id" "$count"
                  ;;
              esac
              ;;
          esac
        done
        """#.write(to: appServerURL, atomically: true, encoding: .utf8)

        try #"""
        #!/bin/sh
        : > "$QUILLCODE_TEST_SSH_ARGUMENTS"
        for argument in "$@"; do
          printf '%s\n' "$argument" >> "$QUILLCODE_TEST_SSH_ARGUMENTS"
          remote_command=$argument
        done
        exec /bin/sh -c "$remote_command"
        """#.write(to: sshURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: appServerURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sshURL.path)

        return SSHRemoteAppServerFixture(
            root: root,
            remoteRoot: remoteRoot,
            sshURL: sshURL,
            appServerURL: appServerURL,
            messagesURL: messagesURL,
            startsURL: startsURL,
            sshArgumentsURL: sshArgumentsURL,
            mode: mode
        )
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: () throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Condition was not satisfied before the timeout.")
    }
}

private struct SSHRemoteAppServerFixture {
    var root: URL
    var remoteRoot: URL
    var sshURL: URL
    var appServerURL: URL
    var messagesURL: URL
    var startsURL: URL
    var sshArgumentsURL: URL
    var mode: String

    var connection: ProjectConnection {
        .ssh(path: remoteRoot.path, host: "feather.local", user: "quill", port: 2222)
    }

    func pool(quillCodeExecutable: String? = nil) -> SSHRemoteAppServerPool {
        SSHRemoteAppServerPool(
            sshExecutable: sshURL.path,
            quillCodeExecutable: quillCodeExecutable ?? appServerURL.path,
            connectTimeoutSeconds: 2,
            handshakeTimeoutSeconds: 2,
            environment: [
                "QUILLCODE_TEST_MESSAGES": messagesURL.path,
                "QUILLCODE_TEST_STARTS": startsURL.path,
                "QUILLCODE_TEST_SSH_ARGUMENTS": sshArgumentsURL.path,
                "QUILLCODE_TEST_MODE": mode
            ]
        )
    }

    func messages() throws -> [String] {
        guard FileManager.default.fileExists(atPath: messagesURL.path) else { return [] }
        return try String(contentsOf: messagesURL, encoding: .utf8)
            .split(separator: "\n")
            .map { String($0).replacingOccurrences(of: "\\/", with: "/") }
    }

    func startCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: startsURL.path) else { return 0 }
        return try String(contentsOf: startsURL, encoding: .utf8).split(separator: "\n").count
    }

    func sshArguments() throws -> [String] {
        try String(contentsOf: sshArgumentsURL, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
