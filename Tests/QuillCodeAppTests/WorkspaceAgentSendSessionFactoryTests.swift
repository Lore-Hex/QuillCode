import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceAgentSendSessionFactoryTests: XCTestCase {
    func testMakeSessionPreservesThreadWorkspaceAndConfiguredTools() throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let memoryRoot = try makeQuillCodeTestDirectory()
        let mcpTool = ToolDefinition(
            name: "mcp.echo",
            description: "Echo through MCP",
            parametersJSON: #"{"type":"object","properties":{}}"#,
            host: .mcp
        )
        let thread = ChatThread(title: "Agent")
        let session = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: memoryRoot,
            mcpToolDefinitions: [mcpTool],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: workspaceRoot
        ).makeSession(prompt: "hello", thread: thread)

        XCTAssertEqual(session.threadID, thread.id)
        XCTAssertEqual(session.workspaceRoot, workspaceRoot)
        XCTAssertEqual(session.runner.baseToolDefinitions.map(\.name), ToolRouter.definitions.map(\.name))
        XCTAssertEqual(session.runner.additionalToolDefinitions.map(\.name), [
            ToolDefinition.planUpdate.name,
            ToolDefinition.handoffUpdate.name,
            ToolDefinition.subagentsUpdate.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.browserOpen.name,
            ToolDefinition.browserClick.name,
            ToolDefinition.browserType.name,
            ToolDefinition.browserScript.name,
            ToolDefinition.memoryRemember.name,
            mcpTool.name
        ])
    }

    func testFactoryUsesRemoteProjectToolDefinitions() {
        let project = ProjectRef(
            name: "Feather",
            path: "/Quill",
            connection: .ssh(path: "/Quill", host: "quill-feather.local", user: "quill")
        )
        let session = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            selectedProject: project,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: URL(fileURLWithPath: "/tmp/quill")
        ).makeSession(prompt: "git status", thread: ChatThread(title: "Remote"))

        XCTAssertEqual(
            session.runner.baseToolDefinitions.map(\.name),
            WorkspaceRemoteProjectToolExecutor.toolDefinitions.map(\.name)
        )
    }

    func testFactoryHonorsInjectedBrowserOverride() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let session = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: { call, _ in
                guard call.name == ToolDefinition.browserInspect.name else { return nil }
                return ToolResult(ok: true, stdout: "custom browser snapshot")
            },
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: workspaceRoot
        ).makeSession(prompt: "inspect browser", thread: ChatThread(title: "Browser"))
        let override = try XCTUnwrap(session.runner.toolExecutionOverride)

        let result = await override(
            ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
            workspaceRoot
        )

        XCTAssertEqual(result?.ok, true)
        XCTAssertEqual(result?.stdout, "custom browser snapshot")
    }
}
