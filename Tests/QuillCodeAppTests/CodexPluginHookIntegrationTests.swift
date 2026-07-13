import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class CodexPluginHookIntegrationTests: XCTestCase {
    func testDefaultHookFileDiscoversSupportedAndInertDefinitions() throws {
        let root = try makeQuillCodeTestDirectory()
        try writePlugin(in: root)
        try writeHooks(
            #"""
            {
              "hooks": {
                "UserPromptSubmit": [
                  {"hooks":[{"type":"command","command":"printf before","statusMessage":"Prepare context","timeout":42}]},
                  {"matcher":"tool:*","hooks":[{"type":"command","command":"printf matched"}]},
                  {"hooks":[{"type":"prompt","command":"ignored"}]},
                  {"hooks":[{"type":"command","async":true,"command":"printf later"}]},
                  {"hooks":[{"type":"command"}]}
                ],
                "Stop": [{"matcher":"*","hooks":[{"type":"command","command":"printf after"}]}],
                "PreToolUse": [{"hooks":[{"type":"command","command":"printf unsupported"}]}]
              }
            }
            """#,
            in: root
        )

        let package = try XCTUnwrap(CodexPluginPackageLoader.loadPackage(
            at: ".quillcode/plugins/demo",
            in: root,
            maxManifestBytes: ProjectExtensionManifestLoader.maxManifestBytes
        ))

        XCTAssertEqual(package.hooks.count, 7)
        XCTAssertTrue(package.hooks.allSatisfy {
            $0.id.hasPrefix("plugin_hook:demo.")
                && $0.definitionHash.count == 64
                && $0.definitionHash.allSatisfy(\.isHexDigit)
                && $0.trustStatus == .reviewRequired
        })
        XCTAssertEqual(hook(event: "Stop", in: package.hooks)?.supportStatus, .supported)
        XCTAssertEqual(hook(event: "PreToolUse", in: package.hooks)?.supportStatus, .unsupportedEvent)
        XCTAssertEqual(
            package.hooks.first { $0.matcher == "tool:*" }?.supportStatus,
            .unsupportedMatcher
        )
        XCTAssertEqual(
            package.hooks.first { $0.handlerType == "prompt" }?.supportStatus,
            .unsupportedHandler
        )
        XCTAssertEqual(package.hooks.first { $0.isAsync }?.supportStatus, .asynchronousHandler)
        XCTAssertEqual(
            package.hooks.first { $0.handlerType == "command" && $0.command == nil }?.supportStatus,
            .missingCommand
        )
        let before = try XCTUnwrap(package.hooks.first { $0.statusMessage == "Prepare context" })
        XCTAssertEqual(before.timeoutSeconds, 42)
        XCTAssertEqual(before.relativePath, ".quillcode/plugins/demo/hooks/hooks.json#UserPromptSubmit/0/0")
    }

    func testExplicitHookReferenceLoadsAndUnsafeReferenceIsRejected() throws {
        let root = try makeQuillCodeTestDirectory()
        try writePlugin(in: root, hooksReference: "config/lifecycle.json")
        try writeHooks(
            #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf done"}]}]}}"#,
            in: root,
            relativePath: "config/lifecycle.json"
        )

        let loaded = CodexPluginPackageLoader.loadPackage(
            at: ".quillcode/plugins/demo",
            in: root,
            maxManifestBytes: ProjectExtensionManifestLoader.maxManifestBytes
        )
        XCTAssertEqual(loaded?.hooks.map(\.relativePath), [
            ".quillcode/plugins/demo/config/lifecycle.json#Stop/0/0"
        ])

        try writePlugin(in: root, hooksReference: "../outside.json")
        XCTAssertTrue(CodexPluginPackageLoader.loadPackage(
            at: ".quillcode/plugins/demo",
            in: root,
            maxManifestBytes: ProjectExtensionManifestLoader.maxManifestBytes
        )?.hooks.isEmpty == true)
    }

    func testHookCountIsBoundedAndDirectManifestShadowsPackageHooks() throws {
        let root = try makeQuillCodeTestDirectory()
        try writePlugin(in: root)
        let handlers = (0..<(CodexPluginPackageLoader.maxHooksPerPackage + 8))
            .map { #"{"type":"command","command":"printf \#($0)"}"# }
            .joined(separator: ",")
        try writeHooks(#"{"hooks":{"Stop":[{"hooks":[\#(handlers)]}]}}"#, in: root)

        let package = try XCTUnwrap(CodexPluginPackageLoader.loadPackage(
            at: ".quillcode/plugins/demo",
            in: root,
            maxManifestBytes: ProjectExtensionManifestLoader.maxManifestBytes
        ))
        XCTAssertEqual(package.hooks.count, CodexPluginPackageLoader.maxHooksPerPackage)

        try #"{"id":"demo","name":"Direct Demo"}"#.write(
            to: root.appendingPathComponent(".quillcode/plugins/demo.json"),
            atomically: true,
            encoding: .utf8
        )
        let discovery = ProjectExtensionManifestLoader.discover(from: root)
        XCTAssertTrue(discovery.pluginHooks.isEmpty)
        XCTAssertEqual(discovery.manifests.filter { $0.id == "plugin:demo" }.map(\.name), ["Direct Demo"])
    }

    func testMetadataRequiresExactTrustBeforeMappingHooksIntoRunPipeline() throws {
        let root = try makeQuillCodeTestDirectory()
        try writePlugin(in: root)
        try writeHooks(
            #"{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"printf before"}]}],"Stop":[{"hooks":[{"type":"command","command":"printf after"}]}]}}"#,
            in: root
        )
        let trustStore = ProjectHookTrustFileStore(
            directory: root.appendingPathComponent(".test-hook-trust", isDirectory: true)
        )

        let unreviewed = WorkspaceProjectMetadataLoader.loadLocal(from: root, hookTrustStore: trustStore)
        XCTAssertEqual(unreviewed.pluginHooks.map(\.trustStatus), [.reviewRequired, .reviewRequired])
        XCTAssertTrue(unreviewed.runHooks.filter { $0.id.hasPrefix("plugin_hook:") }.isEmpty)

        for hook in unreviewed.pluginHooks {
            try trustStore.setDecision(.trusted, for: hook, workspaceRoot: root)
        }
        let trusted = WorkspaceProjectMetadataLoader.loadLocal(from: root, hookTrustStore: trustStore)
        XCTAssertEqual(trusted.pluginHooks.map(\.trustStatus), [.trusted, .trusted])
        XCTAssertEqual(
            trusted.runHooks.filter { $0.id.hasPrefix("plugin_hook:") }.map(\.timing),
            [.afterAgentRun, .beforeAgentRun]
        )

        try writeHooks(
            #"{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"printf changed"}]}],"Stop":[{"hooks":[{"type":"command","command":"printf after"}]}]}}"#,
            in: root
        )
        let changed = WorkspaceProjectMetadataLoader.loadLocal(from: root, hookTrustStore: trustStore)
        XCTAssertEqual(hook(event: "UserPromptSubmit", in: changed.pluginHooks)?.trustStatus, .reviewRequired)
        XCTAssertEqual(hook(event: "Stop", in: changed.pluginHooks)?.trustStatus, .trusted)
        XCTAssertFalse(changed.runHooks.contains { $0.command == "printf changed" })
    }

    func testTrustCommandsUpdateVisibleStateAndDisableExecution() throws {
        let root = try makeQuillCodeTestDirectory()
        try writePlugin(in: root)
        try writeHooks(
            #"{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"printf ready","statusMessage":"Prepare workspace"}]}]}}"#,
            in: root
        )
        let trustStore = ProjectHookTrustFileStore(
            directory: root.appendingPathComponent(".test-hook-trust", isDirectory: true)
        )
        let model = QuillCodeWorkspaceModel(projectHookTrustStore: trustStore)
        let projectID = model.addProject(path: root, name: "Hook Project")
        model.selectProject(projectID)
        let hookID = try XCTUnwrap(model.selectedProject?.pluginHooks.first?.id)

        XCTAssertTrue(model.runWorkspaceCommand("show-hooks", workspaceRoot: root))
        XCTAssertEqual(model.surface().extensions.focusedKind, .hook)
        XCTAssertEqual(model.surface().extensions.hookItems.first?.statusLabel, "Review required")
        XCTAssertNotNil(model.surface().commands.first { $0.id == "hook-trust:\(hookID)" })
        XCTAssertTrue(model.selectedProject?.runHooks.isEmpty == true)

        XCTAssertTrue(model.runWorkspaceCommand("hook-trust:\(hookID)", workspaceRoot: root))
        XCTAssertEqual(model.surface().extensions.hookItems.first?.statusLabel, "Trusted")
        XCTAssertEqual(model.selectedProject?.runHooks.map(\.command), ["printf ready"])
        XCTAssertNotNil(model.surface().commands.first { $0.id == "hook-disable:\(hookID)" })

        XCTAssertTrue(model.runWorkspaceCommand("hook-disable:\(hookID)", workspaceRoot: root))
        XCTAssertEqual(model.surface().extensions.hookItems.first?.statusLabel, "Disabled")
        XCTAssertTrue(model.selectedProject?.runHooks.isEmpty == true)
    }

    func testUnsupportedHookIsVisibleButCannotBeTrustedOrExecuted() throws {
        let root = try makeQuillCodeTestDirectory()
        try writePlugin(in: root)
        try writeHooks(
            #"{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"printf unsafe"}]}]}}"#,
            in: root
        )
        let trustStore = ProjectHookTrustFileStore(
            directory: root.appendingPathComponent(".test-hook-trust", isDirectory: true)
        )
        let model = QuillCodeWorkspaceModel(projectHookTrustStore: trustStore)
        let projectID = model.addProject(path: root, name: "Hook Project")
        model.selectProject(projectID)
        let hookID = try XCTUnwrap(model.selectedProject?.pluginHooks.first?.id)

        XCTAssertEqual(model.surface().extensions.totalHookItems.first?.statusLabel, "Unsupported")
        XCTAssertNil(model.surface().extensions.totalHookItems.first?.actionCommandID)
        XCTAssertFalse(model.runWorkspaceCommand("hook-trust:\(hookID)", workspaceRoot: root))
        XCTAssertTrue(model.selectedProject?.runHooks.isEmpty == true)
    }

    func testTrustedPluginHooksExecuteAroundAgentRunWithVisibleToolEvents() async throws {
        let root = try makeQuillCodeTestDirectory()
        try writePlugin(in: root)
        try writeHooks(
            #"{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"printf before > plugin-before.txt"}]}],"Stop":[{"hooks":[{"type":"command","command":"printf after > plugin-after.txt"}]}]}}"#,
            in: root
        )
        let trustStore = ProjectHookTrustFileStore(
            directory: root.appendingPathComponent(".test-hook-trust", isDirectory: true)
        )
        let discovered = WorkspaceProjectMetadataLoader.loadLocal(from: root, hookTrustStore: trustStore)
        for hook in discovered.pluginHooks {
            try trustStore.setDecision(.trusted, for: hook, workspaceRoot: root)
        }
        let trusted = WorkspaceProjectMetadataLoader.loadLocal(from: root, hookTrustStore: trustStore)
        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: ChatThread(title: "Plugin hooks"),
            runner: AgentRunner(llm: HookCompletionLLM()),
            workspaceRoot: root,
            runHooks: trusted.runHooks
        )

        let result = try await session.run()

        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("plugin-before.txt"), encoding: .utf8),
            "before"
        )
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("plugin-after.txt"), encoding: .utf8),
            "after"
        )
        XCTAssertEqual(result.thread.messages.map(\.content), ["say hello", "hello"])
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolCompleted }.count, 2)
        XCTAssertEqual(
            result.thread.events.filter { $0.kind == .notice }.map(\.summary),
            ["Running before-run hook: Demo Hooks · UserPromptSubmit", "Running after-run hook: Demo Hooks · Stop"]
        )
    }

    func testHTMLSurfaceShowsReviewActionAndKeepsUnsupportedHookInert() {
        let reviewHook = makeSurfaceHook(
            id: "plugin_hook:demo.userpromptsubmit.0.0",
            event: "UserPromptSubmit",
            supportStatus: .supported
        )
        let unsupportedHook = makeSurfaceHook(
            id: "plugin_hook:demo.pretooluse.0.0",
            event: "PreToolUse",
            supportStatus: .unsupportedEvent
        )
        let project = ProjectRef(
            name: "Hooks",
            path: "/tmp/hooks",
            runHooks: [],
            pluginHooks: [reviewHook, unsupportedHook]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(isVisible: true, focusedKind: .hook)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertEqual(model.surface().extensions.subtitle, "2 plugin hooks")
        XCTAssertEqual(html.components(separatedBy: #"data-testid="hook-item""#).count - 1, 2)
        XCTAssertTrue(html.contains(#"data-testid="hook-status">Review required"#))
        XCTAssertTrue(html.contains(#"data-testid="hook-status">Unsupported"#))
        XCTAssertTrue(html.contains(#"data-testid="hook-trust""#))
        XCTAssertEqual(html.components(separatedBy: #"data-testid="hook-trust""#).count - 1, 1)
        XCTAssertTrue(html.contains("This lifecycle event is not executable in this build."))
    }

    private func writePlugin(
        in root: URL,
        hooksReference: String? = nil
    ) throws {
        let manifest = root.appendingPathComponent(".quillcode/plugins/demo/.codex-plugin/plugin.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let hooks = hooksReference.map { #", "hooks":"\#($0)""# } ?? ""
        try #"{"name":"demo","version":"1.0.0","interface":{"displayName":"Demo Hooks"}\#(hooks)}"#.write(
            to: manifest,
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeHooks(
        _ content: String,
        in root: URL,
        relativePath: String = "hooks/hooks.json"
    ) throws {
        let url = root.appendingPathComponent(".quillcode/plugins/demo/\(relativePath)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func hook(event: String, in hooks: [ProjectPluginHook]) -> ProjectPluginHook? {
        hooks.first { $0.event == event }
    }

    private func makeSurfaceHook(
        id: String,
        event: String,
        supportStatus: ProjectHookSupportStatus
    ) -> ProjectPluginHook {
        ProjectPluginHook(
            id: id,
            pluginID: "plugin:demo",
            pluginName: "Demo Hooks",
            event: event,
            handlerType: "command",
            command: "printf ready",
            relativePath: ".quillcode/plugins/demo/hooks/hooks.json#\(event)/0/0",
            definitionHash: String(repeating: "a", count: 64),
            supportStatus: supportStatus
        )
    }
}

private struct HookCompletionLLM: LLMClient {
    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        .say("hello")
    }
}
