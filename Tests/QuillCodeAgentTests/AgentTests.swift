import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentTests: XCTestCase {
    func testRunWhoamiExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("run whoami", in: ChatThread(mode: .auto), workspaceRoot: root)
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertTrue(result.thread.messages.last?.content.contains("Output:") == true)
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

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeAgentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func initializeGitRepo(at root: URL) throws {
        let result = ShellToolExecutor().run(.init(
            command: "git init && git config user.email test@example.com && git config user.name QuillCodeTests",
            cwd: root
        ))
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }
}
