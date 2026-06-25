import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceAgentSendSessionFactoryTests: XCTestCase {
    func testBuildsLocalSendSessionWithCoreToolContext() throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let thread = ChatThread(title: "Local")
        let session = WorkspaceAgentSendSessionFactory(
            selectedProject: nil,
            browser: BrowserState(),
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).makeSession(
            prompt: "run whoami",
            thread: thread,
            runner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            workspaceRoot: workspaceRoot
        )

        XCTAssertEqual(session.prompt, "run whoami")
        XCTAssertEqual(session.threadID, thread.id)
        XCTAssertEqual(session.workspaceRoot, workspaceRoot)
        XCTAssertEqual(session.runner.baseToolDefinitions.map(\.name), ToolRouter.definitions.map(\.name))
        XCTAssertEqual(session.runner.additionalToolDefinitions.map(\.name), [
            ToolDefinition.planUpdate.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.browserOpen.name
        ])
    }

    func testBuildsRemoteSendSessionWithRemoteToolContext() throws {
        let remoteProject = ProjectRef(
            name: "Feather",
            path: "/Quill",
            connection: .ssh(path: "/Quill", host: "quill-feather.local", user: "quill")
        )

        let session = WorkspaceAgentSendSessionFactory(
            selectedProject: remoteProject,
            browser: BrowserState(),
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).makeSession(
            prompt: "git status",
            thread: ChatThread(title: "Remote"),
            runner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            workspaceRoot: try makeQuillCodeTestDirectory()
        )

        XCTAssertEqual(
            session.runner.baseToolDefinitions.map(\.name),
            WorkspaceRemoteProjectToolExecutor.toolDefinitions.map(\.name)
        )
    }

    func testBuildsSendSessionWithOptionalComputerMemoryAndMCPContext() async throws {
        let memoryDirectory = try makeQuillCodeTestDirectory()
        let mcpTool = ToolDefinition(
            name: "mcp.echo",
            description: "Echo through MCP",
            parametersJSON: #"{"type":"object","properties":{}}"#,
            host: .mcp
        )
        let mcpOverride: AgentToolExecutionOverride = { call, _ in
            call.name == "mcp.echo"
                ? ToolResult(ok: true, stdout: "mcp echo")
                : nil
        }

        let session = WorkspaceAgentSendSessionFactory(
            selectedProject: nil,
            browser: BrowserState(),
            computerUseBackend: SendSessionFactoryStubComputerUseBackend(),
            globalMemoryDirectory: memoryDirectory,
            mcpToolDefinitions: [mcpTool],
            mcpToolExecutionOverride: mcpOverride,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).makeSession(
            prompt: "use tools",
            thread: ChatThread(title: "Optional tools"),
            runner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            workspaceRoot: try makeQuillCodeTestDirectory()
        )

        let expectedNames = [
            ToolDefinition.planUpdate.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.browserOpen.name
        ] + ToolDefinition.computerUseDefinitions.map(\.name)
            + [ToolDefinition.memoryRemember.name, mcpTool.name]
        XCTAssertEqual(session.runner.additionalToolDefinitions.map(\.name), expectedNames)

        let override = try XCTUnwrap(session.runner.toolExecutionOverride)
        let mcpResult = await override(ToolCall(name: "mcp.echo", argumentsJSON: "{}"), memoryDirectory)

        XCTAssertEqual(mcpResult?.ok, true)
        XCTAssertEqual(mcpResult?.stdout, "mcp echo")
    }
}

private struct SendSessionFactoryStubComputerUseBackend: ComputerUseBackend {
    var status: ComputerUseStatus {
        .permissionStatus(screenRecordingGranted: true, accessibilityGranted: true)
    }

    func screenshot() async throws -> ComputerScreenshot {
        ComputerScreenshot(width: 1, height: 1, pngBase64: "")
    }

    func leftClick(x: Int, y: Int) async throws {}

    func type(_ text: String) async throws {}

    func scroll(dx: Int, dy: Int) async throws {}

    func moveCursor(x: Int, y: Int) async throws {}

    func pressKey(_ key: String) async throws {}
}
