import XCTest
@testable import QuillCodeApp

final class LinuxNotificationCommandRunnerTests: XCTestCase {
    func testRunnerExecutesFakeNotifySendWithoutShell() async throws {
        let fixture = try FakeNotifySendFixture(script: """
        #!/bin/sh
        printf '%s\\n' "$@" > "$QUILLCODE_NOTIFY_LOG"
        """)
        defer { fixture.remove() }

        let runner = LinuxNotificationCommandRunner(environment: fixture.environment)
        let result = await runner.deliver(AgentRunNotification(
            kind: .needsApproval,
            title: "Approve command",
            body: "Run `ls`; keep $HOME literal",
            threadID: UUID(),
            approvalRequestID: "request-1"
        ))

        XCTAssertEqual(result.status, .delivered)
        XCTAssertEqual(result.command.executable, "notify-send")
        XCTAssertEqual(try fixture.loggedArguments(), [
            "--app-name=QuillCode",
            "--urgency=critical",
            "--expire-time=0",
            "Approve command",
            "Run `ls`; keep $HOME literal"
        ])
    }

    func testRunnerReportsUnavailableWhenNotifySendIsMissing() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = LinuxNotificationCommandRunner(environment: ["PATH": root.path])
        let result = await runner.run(SystemNotificationCommand(
            executable: "notify-send",
            arguments: ["QuillCode", "Hello"]
        ))

        guard case .unavailable(let exitCode, _) = result.status else {
            return XCTFail("Expected unavailable status, got \(result.status)")
        }
        XCTAssertEqual(exitCode, 127)
    }

    func testRunnerReportsHelperFailureWithStderr() async throws {
        let fixture = try FakeNotifySendFixture(script: """
        #!/bin/sh
        echo 'no notification bus' >&2
        exit 42
        """)
        defer { fixture.remove() }

        let runner = LinuxNotificationCommandRunner(environment: fixture.environment)
        let result = await runner.deliver(AutomationRunReport(
            automationID: UUID(),
            followUpThreadID: UUID(),
            title: "Scheduled check",
            body: "Workspace check failed."
        ))

        guard case .failed(let exitCode, let stderr) = result.status else {
            return XCTFail("Expected failed status, got \(result.status)")
        }
        XCTAssertEqual(exitCode, 42)
        XCTAssertTrue(stderr.contains("no notification bus"), stderr)
    }

    func testRunnerRejectsEmptyExecutableWithoutLaunching() async {
        let runner = LinuxNotificationCommandRunner(environment: ["PATH": ""])
        let result = await runner.run(SystemNotificationCommand(
            executable: "   ",
            arguments: ["QuillCode"]
        ))

        guard case .unavailable(let exitCode, let stderr) = result.status else {
            return XCTFail("Expected unavailable status, got \(result.status)")
        }
        XCTAssertEqual(exitCode, 127)
        XCTAssertTrue(stderr.contains("empty"), stderr)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeLinuxNotificationRunner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private struct FakeNotifySendFixture {
        let root: URL
        let log: URL

        var environment: [String: String] {
            [
                "PATH": root.path,
                "QUILLCODE_NOTIFY_LOG": log.path
            ]
        }

        init(script: String) throws {
            root = try LinuxNotificationCommandRunnerTests.makeTemporaryDirectory()
            log = root.appendingPathComponent("notify.log")
            let executable = root.appendingPathComponent("notify-send")
            try script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executable.path
            )
        }

        func loggedArguments() throws -> [String] {
            let contents = try String(contentsOf: log, encoding: .utf8)
            return contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .dropLast()
                .map(String.init)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
