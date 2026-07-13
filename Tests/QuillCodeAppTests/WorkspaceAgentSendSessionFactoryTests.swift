import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit
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
            ToolDefinition.subagentsRun.name,
            ToolDefinition.browserInspect.name,
            ToolDefinition.browserOpen.name,
            ToolDefinition.browserClick.name,
            ToolDefinition.browserType.name,
            ToolDefinition.browserScript.name,
            ToolDefinition.memoryRemember.name,
            mcpTool.name
        ])
        XCTAssertNotNil(session.runner.threadToolExecutionOverride)
    }

    func testSideConversationDoesNotAdvertiseSubagentTool() throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let parentID = UUID()
        let thread = ChatThread(
            title: "Side",
            runtimeContext: .sideConversation(parentThreadID: parentID)
        )

        let session = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: workspaceRoot
        ).makeSession(prompt: "Explain this", thread: thread)

        XCTAssertFalse(session.runner.additionalToolDefinitions.contains {
            $0.name == ToolDefinition.subagentsRun.name
        })
        XCTAssertNil(session.runner.threadToolExecutionOverride)
        XCTAssertTrue(session.runner.additionalToolDefinitions.contains {
            $0.name == ToolDefinition.planUpdate.name
        })
    }

    func testFactoryWiresEnabledPluginSkillsIntoLiveRunner() throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let skillDirectory = workspaceRoot.appendingPathComponent(".quillcode/plugins/acme/skills/review")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try "# Review".write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let project = ProjectRef(
            name: "Plugin Project",
            path: workspaceRoot.path,
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "plugin:acme",
                    kind: .plugin,
                    name: "Acme",
                    relativePath: ".quillcode/plugins/acme/.codex-plugin/plugin.json",
                    skillDirectoryRelativePaths: [".quillcode/plugins/acme/skills"]
                )
            ]
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
            workspaceRoot: workspaceRoot
        ).makeSession(prompt: "Use review", thread: ChatThread(title: "Plugin"))

        let resolved = try XCTUnwrap(session.runner.skillResolver).resolve(name: "review")
        XCTAssertEqual(resolved.baseDirectory.standardizedFileURL.path, skillDirectory.standardizedFileURL.path)
        XCTAssertTrue(
            session.runner.baseToolDefinitions.first { $0.name == ToolDefinition.skillLoad.name }?
                .description.contains("Available now: `review`.") == true
        )
    }

    func testFactoryUsesRemoteProjectToolDefinitionsAndRunHooks() {
        let hook = ProjectRunHook(
            id: "before:.quillcode/hooks/before-agent-run/01-prepare.sh",
            timing: .beforeAgentRun,
            title: "Prepare",
            relativePath: ".quillcode/hooks/before-agent-run/01-prepare.sh",
            command: "sh '.quillcode/hooks/before-agent-run/01-prepare.sh'"
        )
        let project = ProjectRef(
            name: "Feather",
            path: "/Quill",
            connection: .ssh(path: "/Quill", host: "quill-feather.local", user: "quill"),
            runHooks: [hook]
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
        XCTAssertEqual(session.runHooks, [hook])
        XCTAssertEqual(session.selectedProject, project)
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

    func testFactoryStoresComputerScreenshotsAsThreadOwnedModelFeedback() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let store = ImageAttachmentStore(
            directory: workspaceRoot.appendingPathComponent("attachments", isDirectory: true)
        )
        let thread = ChatThread(title: "Computer Use")
        let session = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            selectedProject: nil,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: StubComputerUseBackend(),
            imageAttachmentStore: store,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: workspaceRoot
        ).makeSession(prompt: "Inspect the screen", thread: thread)
        let override = try XCTUnwrap(session.runner.toolExecutionOverride)
        let optionalResult = await override(
            ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}"),
            workspaceRoot
        )
        let result = try XCTUnwrap(optionalResult)
        let provider = try XCTUnwrap(session.runner.toolFeedbackAttachmentProvider)
        let attachments = provider(
            ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}"),
            result
        )

        XCTAssertTrue(result.ok)
        let artifact = try XCTUnwrap(result.artifacts.first)
        XCTAssertTrue(artifact.contains("/\(thread.id.uuidString)/computer-use/"))
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.localURL.path, artifact)
        XCTAssertTrue(store.contains(try XCTUnwrap(attachments.first?.localURL)))
        XCTAssertFalse(try store.data(for: XCTUnwrap(attachments.first)).isEmpty)
    }
}
