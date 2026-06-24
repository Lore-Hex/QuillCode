import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceAgentRunContextBuilderTests: XCTestCase {
    func testLocalContextUsesLocalToolsAndCoreAgentTools() {
        let runner = WorkspaceAgentRunContextBuilder(
            selectedProject: nil,
            browser: BrowserState(),
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).configuredRunner(from: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []))

        XCTAssertEqual(runner.baseToolDefinitions.map(\.name), ToolRouter.definitions.map(\.name))
        XCTAssertEqual(runner.additionalToolDefinitions.map(\.name), [
            ToolDefinition.planUpdate.name,
            ToolDefinition.browserInspect.name
        ])
    }

    func testRemoteContextUsesRemoteToolDefinitions() {
        let project = ProjectRef(
            name: "Feather",
            path: "/Quill",
            connection: .ssh(path: "/Quill", host: "quill-feather.local", user: "quill")
        )
        let runner = WorkspaceAgentRunContextBuilder(
            selectedProject: project,
            browser: BrowserState(),
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).configuredRunner(from: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []))

        XCTAssertEqual(
            runner.baseToolDefinitions.map(\.name),
            WorkspaceRemoteProjectToolExecutor.toolDefinitions.map(\.name)
        )
    }

    func testOptionalToolDefinitionsAreAppendedInStableOrder() throws {
        let memoryDirectory = try makeQuillCodeTestDirectory()
        let mcpTool = ToolDefinition(
            name: "mcp.echo",
            description: "Echo through MCP",
            parametersJSON: #"{"type":"object","properties":{}}"#,
            host: .mcp
        )
        let runner = WorkspaceAgentRunContextBuilder(
            selectedProject: nil,
            browser: BrowserState(),
            computerUseBackend: StubComputerUseBackend(),
            globalMemoryDirectory: memoryDirectory,
            mcpToolDefinitions: [mcpTool],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).configuredRunner(from: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []))

        let expectedNames = [
            ToolDefinition.planUpdate.name,
            ToolDefinition.browserInspect.name
        ] + ToolDefinition.computerUseDefinitions.map(\.name)
            + [ToolDefinition.memoryRemember.name, mcpTool.name]
        XCTAssertEqual(runner.additionalToolDefinitions.map(\.name), expectedNames)
    }

    func testOverrideHandlesPlanBrowserAndMemoryTools() async throws {
        let memoryDirectory = try makeQuillCodeTestDirectory()
        let runner = WorkspaceAgentRunContextBuilder(
            selectedProject: nil,
            browser: BrowserState(
                currentURL: "https://example.com",
                title: "Example",
                status: "Ready",
                snapshot: BrowserSnapshotState(sourceLabel: "web", summary: "Example page")
            ),
            computerUseBackend: nil,
            globalMemoryDirectory: memoryDirectory,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).configuredRunner(from: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []))
        let override = try XCTUnwrap(runner.toolExecutionOverride)

        let planResult = await override(
            ToolCall(
                name: ToolDefinition.planUpdate.name,
                argumentsJSON: try JSONHelpers.encodePretty(AgentPlanUpdate(plan: [
                    AgentPlanItem(step: "Ship", status: .inProgress)
                ]))
            ),
            memoryDirectory
        )
        XCTAssertEqual(planResult?.ok, true)

        let browserResult = await override(
            ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
            memoryDirectory
        )
        XCTAssertEqual(browserResult?.ok, true)
        XCTAssertTrue(browserResult?.stdout.contains("Example") == true)

        let memoryResult = await override(
            ToolCall(
                name: ToolDefinition.memoryRemember.name,
                argumentsJSON: ToolArguments.json(["content": "Use concise status updates."])
            ),
            memoryDirectory
        )
        XCTAssertEqual(memoryResult?.ok, true)
        XCTAssertEqual(memoryResult?.artifacts.first?.hasPrefix("memories/"), true)
    }

    func testMemoryRememberExecutorDetectsCompletedMemoryToolEvents() throws {
        let result = ToolResult(ok: true, artifacts: ["memories/use-concise-status-updates.md"])
        var thread = ChatThread(title: "Memory")
        thread.events.append(ThreadEvent(
            kind: .toolCompleted,
            summary: "\(ToolDefinition.memoryRemember.name) completed",
            payloadJSON: try JSONHelpers.encodePretty(result)
        ))

        XCTAssertTrue(WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread))
    }
}

private struct StubComputerUseBackend: ComputerUseBackend {
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
