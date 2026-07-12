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
            ToolDefinition.handoffUpdate.name,
            ToolDefinition.subagentsUpdate.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.browserOpen.name,
            ToolDefinition.browserClick.name,
            ToolDefinition.browserType.name,
            ToolDefinition.browserScript.name
        ])
    }

    func testContextPreservesUnrelatedToolFeedbackAttachmentProvider() {
        let baseRunner = AgentRunner(
            baseToolDefinitions: [],
            additionalToolDefinitions: [],
            toolFeedbackAttachmentProvider: { _, _ in [] }
        )
        let runner = WorkspaceAgentRunContextBuilder(
            selectedProject: nil,
            browser: BrowserState(),
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).configuredRunner(from: baseRunner)

        XCTAssertNotNil(runner.toolFeedbackAttachmentProvider)
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
            ToolDefinition.handoffUpdate.name,
            ToolDefinition.subagentsUpdate.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.browserOpen.name,
            ToolDefinition.browserClick.name,
            ToolDefinition.browserType.name,
            ToolDefinition.browserScript.name
        ] + ToolDefinition.computerUseDefinitions.map(\.name)
            + [ToolDefinition.memoryRemember.name, mcpTool.name]
        XCTAssertEqual(runner.additionalToolDefinitions.map(\.name), expectedNames)
    }

    func testConfiguredRunnerWiresSpendFusePolicyFromConfigAndCatalog() {
        let runner = WorkspaceAgentRunContextBuilder(
            selectedProject: nil,
            config: AppConfig(runSpendFuseUSD: 0.25),
            modelCatalog: [
                ModelInfo(
                    id: "trustedrouter/fast",
                    provider: "trustedrouter",
                    displayName: "Nike 1.0",
                    category: "Fast",
                    capabilities: ModelCapabilities(
                        inputPricePerMillionTokens: 1.0,
                        outputPricePerMillionTokens: 2.0
                    )
                )
            ],
            browser: BrowserState(),
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).configuredRunner(from: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []))

        let policy = runner.runSpendFusePolicy
        XCTAssertEqual(policy?.fuseUSD, 0.25)
        XCTAssertEqual(policy?.modelCatalog.map(\.id), ["trustedrouter/fast"])
    }

    func testConfiguredRunnerWiresSpendPeriodLimitsAndThreadSnapshot() {
        let thread = ChatThread(title: "Existing spend")
        let runner = WorkspaceAgentRunContextBuilder(
            selectedProject: nil,
            config: AppConfig(
                runSpendFuseUSD: nil,
                runSpendPeriodLimits: RunSpendPeriodLimits(dailyUSD: 1, weeklyUSD: 5, monthlyUSD: 20)
            ),
            modelCatalog: [
                ModelInfo(
                    id: "trustedrouter/fast",
                    provider: "trustedrouter",
                    displayName: "Nike 1.0",
                    category: "Fast"
                )
            ],
            spendPeriodThreads: [thread],
            browser: BrowserState(),
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).configuredRunner(from: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []))

        let policy = runner.runSpendFusePolicy
        XCTAssertNil(policy?.fuseUSD)
        XCTAssertEqual(policy?.periodLimits.dailyUSD, 1)
        XCTAssertEqual(policy?.periodLimits.weeklyUSD, 5)
        XCTAssertEqual(policy?.periodLimits.monthlyUSD, 20)
        XCTAssertEqual(policy?.periodThreads.map(\.id), [thread.id])
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

        let handoffResult = await override(
            ToolCall(
                name: ToolDefinition.handoffUpdate.name,
                argumentsJSON: try JSONHelpers.encodePretty(AgentHandoffUpdate(summary: "Ready to continue."))
            ),
            memoryDirectory
        )
        XCTAssertEqual(handoffResult?.ok, true)

        let subagentsResult = await override(
            ToolCall(
                name: ToolDefinition.subagentsUpdate.name,
                argumentsJSON: try JSONHelpers.encodePretty(SubagentProgressUpdate(subagents: [
                    SubagentProgressItem(name: "Verifier", role: "Run checks.", status: .running)
                ]))
            ),
            memoryDirectory
        )
        XCTAssertEqual(subagentsResult?.ok, true)

        let browserResult = await override(
            ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
            memoryDirectory
        )
        XCTAssertEqual(browserResult?.ok, true)
        XCTAssertTrue(browserResult?.stdout.contains("Example") == true)

        let browserOpenResult = await override(
            ToolCall(
                name: ToolDefinition.browserOpen.name,
                argumentsJSON: ToolArguments.json(["url": "https://example.com/docs"])
            ),
            memoryDirectory
        )
        XCTAssertEqual(browserOpenResult?.ok, true)
        XCTAssertTrue(browserOpenResult?.stdout.contains("example.com") == true)

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

    func testComputerUseOverrideHonorsConfiguredAppApprovals() async throws {
        let runner = WorkspaceAgentRunContextBuilder(
            selectedProject: nil,
            config: AppConfig(computerUseApprovedAppNames: ["Terminal"]),
            browser: BrowserState(),
            computerUseBackend: StubComputerUseBackend(
                foregroundApplication: ComputerUseApplication(
                    name: "Passwords",
                    bundleIdentifier: "com.apple.Passwords"
                )
            ),
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        ).configuredRunner(from: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []))
        let override = try XCTUnwrap(runner.toolExecutionOverride)

        let result = await override(
            ToolCall(
                name: ToolDefinition.computerType.name,
                argumentsJSON: ToolArguments.json(["text": "secret"])
            ),
            try makeQuillCodeTestDirectory()
        )

        XCTAssertEqual(result?.ok, false)
        XCTAssertEqual(
            result?.error,
            "Computer Use is not approved for Passwords. Add this app to Computer Use approvals before controlling it."
        )
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

private struct StubComputerUseBackend: ComputerUseBackend, ComputerUseForegroundApplicationProviding {
    var foregroundApplicationValue: ComputerUseApplication?

    init(foregroundApplication: ComputerUseApplication? = nil) {
        self.foregroundApplicationValue = foregroundApplication
    }

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

    func foregroundApplication() async -> ComputerUseApplication? {
        foregroundApplicationValue
    }
}
