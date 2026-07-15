import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

final class WorkspaceAgentSendSessionFactoryTests: XCTestCase {
    func testDedicatedCodeReviewRunnerExposesOnlyReadToolsAndReportSink() async throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let collector = WorkspaceCodeReviewReportCollector()
        let runner = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(),
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
        ).configuredCodeReviewRunner(
            modelID: "trustedrouter/fast",
            threadID: UUID(),
            reportCollector: collector
        )

        XCTAssertEqual(Set(runner.baseToolDefinitions.map(\.name)), Set([
            ToolDefinition.fileRead.name,
            ToolDefinition.fileList.name,
            ToolDefinition.fileSearch.name,
            ToolDefinition.gitStatus.name,
            ToolDefinition.gitDiff.name,
            ToolDefinition.gitBranchList.name
        ]))
        XCTAssertEqual(runner.additionalToolDefinitions.map(\.name), [WorkspaceCodeReviewSubmitTool.name])
        XCTAssertNil(runner.preToolUseHook)
        XCTAssertNil(runner.postToolUseHook)
        XCTAssertNil(runner.permissionRequestHook)
        XCTAssertNil(runner.threadToolExecutionOverride)
        XCTAssertNil(runner.toolFeedbackAttachmentProvider)
        XCTAssertNil(runner.skillResolver)
        XCTAssertNil(runner.webSearch)
        XCTAssertNil(runner.lsp)
        XCTAssertFalse(runner.enablesImmediateActionPreflight)

        let execute = try XCTUnwrap(runner.toolExecutionOverride)
        let denied = await execute(
            ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: #"{"cmd":"whoami"}"#),
            workspaceRoot
        )
        XCTAssertEqual(denied?.ok, false)
        XCTAssertTrue(denied?.error?.contains("cannot execute") == true)

        let accepted = await execute(
            ToolCall(
                name: WorkspaceCodeReviewSubmitTool.name,
                argumentsJSON: #"{"summary":"No defects.","findings":[]}"#
            ),
            workspaceRoot
        )
        XCTAssertEqual(accepted?.ok, true)
        let report = await collector.report
        XCTAssertEqual(report?.summary, "No defects.")
    }

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
        try """
        ---
        name: review
        description: Review code for correctness defects.
        ---

        # Review
        """.write(
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
        let skillDescription = session.runner.baseToolDefinitions.first {
            $0.name == ToolDefinition.skillLoad.name
        }?.description
        XCTAssertTrue(skillDescription?.contains("Available now:") == true)
        XCTAssertTrue(skillDescription?.contains("`review`") == true)
    }

    func testFactoryExcludesConfiguredDisabledSkillsFromLiveRunner() throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let skillDirectory = workspaceRoot.appendingPathComponent(".agents/skills/review")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: review
        description: Review code for correctness defects.
        ---
        """.write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let factory = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            selectedProject: nil,
            config: AppConfig(
                skillConfiguration: SkillConfiguration(disabledNames: ["review"])
            ),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: workspaceRoot
        )

        let runner = factory.makeSession(
            prompt: "Use review",
            thread: ChatThread(title: "Disabled skill")
        ).runner

        let resolver = try XCTUnwrap(runner.skillResolver)
        XCTAssertFalse(resolver.availableSkillNames().contains("review"))
        XCTAssertThrowsError(try resolver.resolve(name: "review"))
        let description = runner.baseToolDefinitions.first {
            $0.name == ToolDefinition.skillLoad.name
        }?.description
        XCTAssertFalse(description?.contains("`review`") == true)
    }

    func testFactoryWiresOnlyTrustedSupportedPluginToolHooks() throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        let pluginRoot = workspaceRoot.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let trusted = ProjectPluginHook(
            id: "pre",
            pluginID: "plugin:demo",
            pluginName: "Demo",
            event: "PreToolUse",
            matcher: "^Bash$",
            handlerType: "command",
            command: "true",
            relativePath: ".quillcode/plugins/demo/hooks/hooks.json#PreToolUse",
            pluginRootRelativePath: ".quillcode/plugins/demo",
            definitionHash: String(repeating: "a", count: 64),
            trustStatus: .trusted,
            supportStatus: .supported
        )
        var untrusted = trusted
        untrusted.id = "post"
        untrusted.event = "PostToolUse"
        untrusted.trustStatus = .reviewRequired
        var permission = trusted
        permission.id = "permission"
        permission.event = "PermissionRequest"
        var preCompact = trusted
        preCompact.id = "pre-compact"
        preCompact.event = "PreCompact"
        preCompact.matcher = "auto"
        var postCompact = trusted
        postCompact.id = "post-compact"
        postCompact.event = "PostCompact"
        postCompact.matcher = "auto"
        let project = ProjectRef(
            name: "Hook Project",
            path: workspaceRoot.path,
            runHooks: [],
            pluginHooks: [trusted, untrusted, permission, preCompact, postCompact]
        )

        let session = WorkspaceAgentSendSessionFactory(
            baseRunner: AgentRunner(baseToolDefinitions: [], additionalToolDefinitions: []),
            selectedProject: project,
            config: AppConfig(),
            browser: BrowserState(),
            browserToolOverride: nil,
            computerUseBackend: nil,
            globalMemoryDirectory: nil,
            pluginDataBaseDirectory: workspaceRoot.appendingPathComponent("plugin-data", isDirectory: true),
            mcpToolDefinitions: [],
            mcpToolExecutionOverride: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor(),
            workspaceRoot: workspaceRoot
        ).makeSession(prompt: "Run true", thread: ChatThread(title: "Hooks"))

        XCTAssertNotNil(session.runner.preToolUseHook)
        XCTAssertNil(session.runner.postToolUseHook)
        XCTAssertNotNil(session.runner.permissionRequestHook)
        XCTAssertNotNil(session.runner.preCompactHook)
        XCTAssertNotNil(session.runner.postCompactHook)
    }

    func testFactoryWiresExplicitGlobalHooksWithoutASelectedProject() throws {
        let workspaceRoot = try makeQuillCodeTestDirectory()
        func hook(_ id: String, event: String, matcher: String? = nil) -> ProjectPluginHook {
            ProjectPluginHook(
                id: id,
                pluginID: "hook-source:user",
                pluginName: "User hooks",
                event: event,
                matcher: matcher,
                handlerType: "command",
                command: "true",
                relativePath: "~/.quillcode/config.toml#\(event)",
                definitionHash: String(repeating: "a", count: 64),
                trustScope: .user,
                trustStatus: .trusted,
                supportStatus: .supported
            )
        }
        let runHook = ProjectRunHook(
            id: "global-before",
            timing: .beforeAgentRun,
            title: "Global before",
            relativePath: "~/.quillcode/config.toml#UserPromptSubmit",
            command: "true"
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
            hooks: [
                hook("pre", event: "PreToolUse", matcher: "^Bash$"),
                hook("permission", event: "PermissionRequest", matcher: "^Bash$"),
                hook("pre-compact", event: "PreCompact", matcher: "auto"),
                hook("post-compact", event: "PostCompact", matcher: "auto"),
                hook("session", event: "SessionStart", matcher: "startup")
            ],
            runHooks: [runHook],
            workspaceRoot: workspaceRoot
        ).makeSession(prompt: "Run true", thread: ChatThread(title: "Global hooks"))

        XCTAssertNotNil(session.runner.preToolUseHook)
        XCTAssertNotNil(session.runner.permissionRequestHook)
        XCTAssertNotNil(session.runner.preCompactHook)
        XCTAssertNotNil(session.runner.postCompactHook)
        XCTAssertTrue(session.pluginLifecycleHooks.hasExecutableHooks)
        XCTAssertEqual(session.runHooks, [runHook])
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
