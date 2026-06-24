import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceToolCallExecutorTests: XCTestCase {
    func testBrowserInspectRoutesBeforeLocalRouter() throws {
        let root = try makeQuillCodeTestDirectory()
        let executor = WorkspaceToolCallExecutor(
            selectedProject: nil,
            browser: BrowserState(
                currentURL: "https://example.com",
                title: "Example",
                status: "Ready",
                snapshot: BrowserSnapshotState(
                    sourceLabel: "Web page",
                    summary: "Example snapshot",
                    details: ["Host: example.com"],
                    outline: ["Example"]
                )
            ),
            router: ToolRouter(workspaceRoot: root),
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let execution = executor.execute(ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"))

        XCTAssertTrue(execution.ok, execution.primary.result.error ?? "")
        XCTAssertEqual(execution.primary.call.name, ToolDefinition.browserInspect.name)
        XCTAssertTrue(execution.primary.result.stdout.contains("Example snapshot"))
        XCTAssertTrue(execution.followUps.isEmpty)
    }

    func testBrowserOpenRoutesThroughBrowserWorkflow() throws {
        let root = try makeQuillCodeTestDirectory()
        var browser = BrowserState()
        var lastError: String?
        let executor = WorkspaceToolCallExecutor(
            selectedProject: nil,
            browser: browser,
            router: ToolRouter(workspaceRoot: root),
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let execution = executor.execute(
            ToolCall(
                name: ToolDefinition.browserOpen.name,
                argumentsJSON: ToolArguments.json(["url": "localhost:5173/dashboard"])
            ),
            browser: &browser,
            lastError: &lastError
        )
        let output = try JSONHelpers.decode(BrowserInspectionToolOutput.self, from: execution.primary.result.stdout)

        XCTAssertTrue(execution.ok, execution.primary.result.error ?? "")
        XCTAssertEqual(browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(browser.status, "Preview ready")
        XCTAssertNil(lastError)
        XCTAssertEqual(output.url, "http://localhost:5173/dashboard")
        XCTAssertEqual(output.inspectionDepth, .metadataOnly)
        XCTAssertTrue(execution.followUps.isEmpty)
    }

    func testPlanUpdateRoutesBeforeLocalRouter() throws {
        let root = try makeQuillCodeTestDirectory()
        let update = AgentPlanUpdate(plan: [
            AgentPlanItem(step: "Inspect", status: .completed),
            AgentPlanItem(step: "Ship", status: .inProgress)
        ])
        let executor = WorkspaceToolCallExecutor(
            selectedProject: nil,
            browser: BrowserState(),
            router: ToolRouter(workspaceRoot: root),
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let execution = executor.execute(ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        ))
        let decoded = try JSONHelpers.decode(AgentPlanUpdate.self, from: execution.primary.result.stdout)

        XCTAssertTrue(execution.ok, execution.primary.result.error ?? "")
        XCTAssertEqual(decoded.plan.map(\.step), ["Inspect", "Ship"])
        XCTAssertTrue(execution.followUps.isEmpty)
    }

    func testApplyPatchReturnsReviewDiffFollowUp() throws {
        let root = try temporaryGitRepository()
        let executor = WorkspaceToolCallExecutor(
            selectedProject: nil,
            browser: BrowserState(),
            router: ToolRouter(workspaceRoot: root),
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let patch = """
        diff --git a/hello.txt b/hello.txt
        index e45c9c2..ce01362 100644
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -old
        +hello
        """

        let execution = executor.execute(ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": patch])
        ))

        XCTAssertTrue(execution.primary.result.ok, execution.primary.result.error ?? "")
        XCTAssertEqual(execution.followUps.map(\.call.name), [ToolDefinition.gitDiff.name])
        XCTAssertTrue(execution.ok, execution.followUps.first?.result.error ?? "")
        XCTAssertTrue(execution.followUps.first?.result.stdout.contains("+hello") == true)
    }

    func testRemoteProjectRejectsUnsupportedToolsWithoutFallingBackLocal() throws {
        let root = try makeQuillCodeTestDirectory()
        let project = ProjectRef(
            name: "Remote",
            path: "/Quill",
            connection: .ssh(path: "/Quill", host: "quill.example", user: "quill")
        )
        let executor = WorkspaceToolCallExecutor(
            selectedProject: project,
            browser: BrowserState(),
            router: ToolRouter(workspaceRoot: root),
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let execution = executor.execute(ToolCall(name: "host.unavailable", argumentsJSON: "{}"))

        XCTAssertFalse(execution.ok)
        XCTAssertEqual(
            execution.primary.result.error,
            "Tool is not available for SSH Remote projects: host.unavailable"
        )
        XCTAssertTrue(execution.followUps.isEmpty)
    }

    private func temporaryGitRepository() throws -> URL {
        let root = try makeQuillCodeTestDirectory()
        try initializeGitRepository(at: root)
        try "old\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "hello.txt"], cwd: root)
        _ = try runGit(["commit", "-m", "initial"], cwd: root)
        return root
    }
}
