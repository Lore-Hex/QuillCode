import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentImmediateActionTests: XCTestCase {
    func testRunWhoamiExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("run whoami", in: ChatThread(mode: .auto), workspaceRoot: root)
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
    }

    func testWhoamiQuestionExecutesImmediatelyWithoutConfirmationLoop() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("whoami?", in: ChatThread(mode: .auto), workspaceRoot: root)

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("I'll run") })
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("No shell command was specified") })

        XCTAssertEqual(try queuedShellCommand(in: result), "whoami")
    }

    func testDiskUsageQuestionExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("How much hd?", in: ChatThread(mode: .auto), workspaceRoot: root)

        XCTAssertEqual(result.toolResults.count, 1)
        let toolResult = try XCTUnwrap(result.toolResults.first)
        XCTAssertTrue(toolResult.ok, toolResult.error ?? "")
        XCTAssertEqual(try queuedShellCommand(in: result), "df -h / /Quill 2>/dev/null || df -h /")
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("I'll check") })
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("No shell command was specified") })
    }

    func testOpenClawDiscoveryExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("Do you have openclaw?", in: ChatThread(mode: .auto), workspaceRoot: root)

        XCTAssertEqual(result.toolResults.count, 1)
        let toolResult = try XCTUnwrap(result.toolResults.first)
        XCTAssertTrue(toolResult.ok, toolResult.error ?? "")
        XCTAssertEqual(try queuedShellCommand(in: result), "command -v openclaw || which openclaw || echo 'not found'")
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("I'll check") })
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("No shell command was specified") })
    }

    func testDownloadDomainExecutesImmediatelyWithWorkspaceBoundedPath() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(toolExecutionOverride: { call, _ in
            guard call.name == ToolDefinition.shellRun.name else { return nil }
            return ToolResult(
                ok: true,
                stdout: "-rw-r--r--  1 mock  staff  42K downloads/linkedin.com.html\n",
                stderr: "",
                exitCode: 0
            )
        })

        let result = try await runner.send("Can you download LinkedIn.com?", in: ChatThread(mode: .auto), workspaceRoot: root)

        XCTAssertEqual(result.toolResults.count, 1)
        let toolResult = try XCTUnwrap(result.toolResults.first)
        XCTAssertTrue(toolResult.ok, toolResult.error ?? "")
        XCTAssertEqual(
            try queuedShellCommand(in: result),
            "mkdir -p downloads && curl -L --fail --silent --show-error --output 'downloads/linkedin.com.html' 'https://LinkedIn.com' && ls -lh 'downloads/linkedin.com.html'"
        )
        XCTAssertEqual(result.thread.messages.last?.content, "Downloaded to `downloads/linkedin.com.html`.")
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("I'll download") })
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("No shell command was specified") })
    }

    func testBacktickCommandDoesNotBecomeEmptyToolCall() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("Run `pwd`", in: ChatThread(mode: .auto), workspaceRoot: root)
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
    }

    func testMakeHelloWorldFileExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send(
            "Can you write a file that says hello world",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        let text = try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8)
        XCTAssertEqual(text, "hello world\n")
        XCTAssertEqual(result.thread.messages.last?.content, "Wrote `hello.txt`.")
    }

    func testCommitChangesExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)

        let result = try await AgentRunner().send(
            "commit these changes with message Add hello file",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        let log = ShellToolExecutor().run(.init(command: "git log -1 --pretty=%s", cwd: root))
        XCTAssertEqual(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Add hello file")
    }

    func testPushCurrentBranchExecutesImmediately() async throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        let remote = parent.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepo(at: root)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init --bare '\(remote.path)'", cwd: parent)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git remote add origin '\(remote.path)'", cwd: root)).ok)
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "Add hello").ok)

        let result = try await AgentRunner().send(
            "push this branch",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(result.thread.events.filter { $0.summary.contains("host.git.push") }.count, 3)
    }

    private func queuedShellCommand(in result: AgentRunResult) throws -> String {
        let queued = try XCTUnwrap(result.thread.events.first { $0.kind == .toolQueued })
        let payloadJSON = try XCTUnwrap(queued.payloadJSON)
        let call = try JSONDecoder().decode(ToolCall.self, from: Data(payloadJSON.utf8))
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        return try arguments.requiredString("cmd")
    }
}
