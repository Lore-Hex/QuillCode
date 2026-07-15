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
                "PreToolUse": [{"hooks":[{"type":"command","command":"printf pre"}]}],
                "PermissionRequest": [{"matcher":"^Bash$","hooks":[{"type":"command","command":"printf permission"}]}],
                "PreCompact": [{"matcher":"^(manual|auto)$","hooks":[{"type":"command","command":"printf compacting"}]}],
                "PostCompact": [{"matcher":"auto","hooks":[{"type":"command","command":"printf compacted"}]}],
                "SessionStart": [{"matcher":"^(startup|resume)$","hooks":[{"type":"command","command":"printf session"}]}],
                "SubagentStart": [{"matcher":"^Verifier$","hooks":[{"type":"command","command":"printf worker"}]}],
                "SubagentStop": [{"matcher":"^Verifier$","hooks":[{"type":"command","command":"printf stopped"}]}]
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

        XCTAssertEqual(package.hooks.count, 13)
        XCTAssertTrue(package.hooks.allSatisfy {
            $0.id.hasPrefix("plugin_hook:demo.")
                && $0.definitionHash.count == 64
                && $0.definitionHash.allSatisfy(\.isHexDigit)
                && $0.trustStatus == .reviewRequired
        })
        XCTAssertEqual(hook(event: "Stop", in: package.hooks)?.supportStatus, .supported)
        XCTAssertEqual(hook(event: "PreToolUse", in: package.hooks)?.supportStatus, .supported)
        XCTAssertEqual(hook(event: "PermissionRequest", in: package.hooks)?.supportStatus, .supported)
        XCTAssertEqual(hook(event: "PreCompact", in: package.hooks)?.supportStatus, .supported)
        XCTAssertEqual(hook(event: "PostCompact", in: package.hooks)?.supportStatus, .supported)
        XCTAssertEqual(hook(event: "SessionStart", in: package.hooks)?.supportStatus, .supported)
        XCTAssertEqual(hook(event: "SubagentStart", in: package.hooks)?.supportStatus, .supported)
        XCTAssertEqual(hook(event: "SubagentStop", in: package.hooks)?.supportStatus, .supported)
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
        XCTAssertEqual(before.pluginRootRelativePath, ".quillcode/plugins/demo")
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

    func testPackageMoveChangesExactHookDefinitionHash() throws {
        let root = try makeQuillCodeTestDirectory()
        try writePlugin(in: root)
        try writeHooks(
            #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf done"}]}]}}"#,
            in: root
        )
        let source = root.appendingPathComponent(".quillcode/plugins/demo")
        let moved = root.appendingPathComponent(".quillcode/plugins/moved")
        try FileManager.default.copyItem(at: source, to: moved)

        let original = try XCTUnwrap(CodexPluginPackageLoader.loadPackage(
            at: ".quillcode/plugins/demo",
            in: root,
            maxManifestBytes: ProjectExtensionManifestLoader.maxManifestBytes
        )?.hooks.first)
        let relocated = try XCTUnwrap(CodexPluginPackageLoader.loadPackage(
            at: ".quillcode/plugins/moved",
            in: root,
            maxManifestBytes: ProjectExtensionManifestLoader.maxManifestBytes
        )?.hooks.first)

        XCTAssertNotEqual(original.pluginRootRelativePath, relocated.pluginRootRelativePath)
        XCTAssertNotEqual(original.definitionHash, relocated.definitionHash)
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
            #"{"hooks":{"Notification":[{"hooks":[{"type":"command","command":"printf unsafe"}]}]}}"#,
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
            #"""
            {
              "hooks": {
                "UserPromptSubmit": [{"hooks":[{"type":"command","command":"printf before > plugin-before.txt; cat > \"$PLUGIN_DATA/before.json\"; printf '%s\\n%s\\n%s\\n%s' \"$PLUGIN_ROOT\" \"$PLUGIN_DATA\" \"$CLAUDE_PLUGIN_ROOT\" \"$CLAUDE_PLUGIN_DATA\" > plugin-env.txt"}]}],
                "Stop": [{"hooks":[{"type":"command","command":"printf after > plugin-after.txt; cat > \"$PLUGIN_DATA/after.json\""}]}]
              }
            }
            """#,
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
        let pluginDataBase = root.appendingPathComponent(".test-plugin-data", isDirectory: true)
        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: ChatThread(title: "Plugin hooks"),
            runner: AgentRunner(llm: HookCompletionLLM()),
            workspaceRoot: root,
            runHooks: trusted.runHooks,
            pluginDataBaseDirectory: pluginDataBase
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
        let pluginData = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: pluginDataBase,
            workspaceRoot: root,
            pluginID: "plugin:demo"
        )
        let beforePayload = try hookPayload(at: pluginData.appendingPathComponent("before.json"))
        let afterPayload = try hookPayload(at: pluginData.appendingPathComponent("after.json"))
        XCTAssertEqual(beforePayload["hook_event_name"] as? String, "UserPromptSubmit")
        XCTAssertEqual(beforePayload["prompt"] as? String, "say hello")
        XCTAssertEqual(afterPayload["hook_event_name"] as? String, "Stop")
        XCTAssertEqual(afterPayload["last_assistant_message"] as? String, "hello")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("plugin-env.txt"), encoding: .utf8)
                .split(separator: "\n").map(String.init),
            [
                root.appendingPathComponent(".quillcode/plugins/demo").path,
                pluginData.path,
                root.appendingPathComponent(".quillcode/plugins/demo").path,
                pluginData.path
            ]
        )
        let queuedPayloads = result.thread.events
            .filter { $0.kind == .toolQueued }
            .compactMap(\.payloadJSON)
        XCTAssertEqual(queuedPayloads.count, 2)
        XCTAssertTrue(queuedPayloads.allSatisfy { $0.contains(ToolCall.redactedStandardInputValue) })
        XCTAssertTrue(queuedPayloads.allSatisfy { $0.contains(ToolCall.redactedEnvironmentValue) })
        XCTAssertTrue(queuedPayloads.allSatisfy { !$0.contains("say hello") && !$0.contains(pluginData.path) })
    }

    func testMatchingPluginHooksLaunchConcurrentlyButRecordInConfigurationOrder() async throws {
        let root = try makeQuillCodeTestDirectory()
        let first = "touch first.started; i=0; while [ ! -f second.started ] && [ $i -lt 50 ]; do sleep 0.02; i=$((i+1)); done; test -f second.started"
        let second = "touch second.started; i=0; while [ ! -f first.started ] && [ $i -lt 50 ]; do sleep 0.02; i=$((i+1)); done; test -f first.started"
        let hooks = [
            ProjectRunHook(
                id: "first",
                timing: .beforeAgentRun,
                title: "First",
                relativePath: "hooks.json#0",
                command: first,
                timeoutSeconds: 3
            ),
            ProjectRunHook(
                id: "second",
                timing: .beforeAgentRun,
                title: "Second",
                relativePath: "hooks.json#1",
                command: second,
                timeoutSeconds: 3
            )
        ]
        let session = WorkspaceAgentSendSession(
            prompt: "continue",
            thread: ChatThread(title: "Concurrent hooks"),
            runner: AgentRunner(llm: HookCompletionLLM()),
            workspaceRoot: root,
            runHooks: hooks
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages.map(\.content), ["continue", "hello"])
        XCTAssertEqual(
            result.thread.events.filter { $0.kind == .notice }.map(\.summary),
            ["Running before-run hook: First", "Running before-run hook: Second"]
        )
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolCompleted }.count, 2)
    }

    func testHTMLSurfaceShowsReviewActionAndKeepsUnsupportedHookInert() {
        let reviewHook = makeSurfaceHook(
            id: "plugin_hook:demo.userpromptsubmit.0.0",
            event: "UserPromptSubmit",
            supportStatus: .supported
        )
        let unsupportedHook = makeSurfaceHook(
            id: "plugin_hook:demo.notification.0.0",
            event: "Notification",
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

        XCTAssertEqual(model.surface().extensions.subtitle, "2 hooks")
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

    private func hookPayload(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
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
