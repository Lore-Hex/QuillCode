import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentImmediateGitActionTests: XCTestCase {
    func testPoliteGitStatusUsesStructuredGitStatusBeforeGenericShellRecovery() async throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        try "working tree\n".write(to: root.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Please check git status.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        let call = try queuedToolCall(in: result)
        XCTAssertEqual(call.name, ToolDefinition.gitStatus.name)
        XCTAssertEqual(call.argumentsJSON, "{}")
        XCTAssertTrue(result.thread.messages.last?.content.contains("Git status:") == true)
        XCTAssertTrue(result.thread.messages.last?.content.contains("status.txt") == true)
        XCTAssertNoAssistantMessageContains("I'll check", in: result)
    }

    func testGitStatusExecutesImmediatelyWithoutProviderRoundTrip() async throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        try "working tree\n".write(to: root.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send("git status", in: ChatThread(mode: .auto), workspaceRoot: root)

        try assertSingleSuccessfulToolResult(in: result)
        let call = try queuedToolCall(in: result)
        XCTAssertEqual(call.name, ToolDefinition.gitStatus.name)
        XCTAssertEqual(call.argumentsJSON, "{}")
        XCTAssertTrue(result.thread.messages.last?.content.contains("Git status:") == true)
        XCTAssertNoAssistantMessageContains("I'll check", in: result)
    }

    func testWhatChangedUsesGitDiffImmediatelyWithoutProviderRoundTrip() async throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let path = root.appendingPathComponent("tracked.txt")
        try "before\n".write(to: path, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "tracked.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "Add tracked file").ok)
        try "after\n".write(to: path, atomically: true, encoding: .utf8)
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send("what changed?", in: ChatThread(mode: .auto), workspaceRoot: root)

        try assertSingleSuccessfulToolResult(in: result)
        let call = try queuedToolCall(in: result)
        XCTAssertEqual(call.name, ToolDefinition.gitDiff.name)
        XCTAssertEqual(call.argumentsJSON, "{}")
        XCTAssertTrue(result.thread.messages.last?.content.contains("Git diff:") == true)
        XCTAssertTrue(result.thread.messages.last?.content.contains("tracked.txt") == true)
        XCTAssertNoAssistantMessageContains("I'll review", in: result)
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

        try assertSingleSuccessfulToolResult(in: result)
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

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(result.thread.events.filter { $0.summary.contains("host.git.push") }.count, 3)
    }
}
