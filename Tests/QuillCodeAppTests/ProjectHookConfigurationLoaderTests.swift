import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeHooks
import QuillCodePersistence
@testable import QuillCodeApp

@MainActor
final class ProjectHookConfigurationLoaderTests: XCTestCase {
    func testDiscoversAndMergesJSONAndTOMLFromNativeAndCodexLayers() throws {
        let root = try makeQuillCodeTestDirectory()
        try write(
            #"{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"printf native-json","statusMessage":"Native JSON"}]}]}}"#,
            to: ".quillcode/hooks.json",
            in: root
        )
        try write(
            """
            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf native-toml"
            status_message = "Native TOML"
            timeout = 12
            """,
            to: ".quillcode/config.toml",
            in: root
        )
        try write(
            #"{"hooks":{"SessionStart":[{"matcher":"startup","hooks":[{"type":"prompt","command":"ignored"}]}]}}"#,
            to: ".codex/hooks.json",
            in: root
        )
        try write(
            """
            [[hooks.PreToolUse]]
            matcher = "^Bash$"

            [[hooks.PreToolUse.hooks]]
            type = "command"
            command = "printf codex-toml"
            command_windows = "Write-Output codex-toml"
            statusMessage = "Codex TOML"
            """,
            to: ".codex/config.toml",
            in: root
        )

        let hooks = ProjectHookConfigurationLoader.load(from: root)

        XCTAssertEqual(hooks.count, 4)
        XCTAssertEqual(hooks.map(\.id), [
            "config_hook:quillcode-json.userpromptsubmit.0.0",
            "config_hook:quillcode-config.stop.0.0",
            "config_hook:codex-json.sessionstart.0.0",
            "config_hook:codex-config.pretooluse.0.0"
        ])
        XCTAssertEqual(hooks.map(\.pluginRootRelativePath), [nil, nil, nil, nil])
        XCTAssertTrue(hooks.allSatisfy {
            $0.definitionHash.count == 64
                && $0.definitionHash.allSatisfy(\.isHexDigit)
                && $0.effectiveTrustScope == .workspace
                && $0.trustStatus == .reviewRequired
        })

        let nativeTOML = try XCTUnwrap(hooks.first { $0.statusMessage == "Native TOML" })
        XCTAssertEqual(nativeTOML.command, "printf native-toml")
        XCTAssertEqual(nativeTOML.timeoutSeconds, 12)
        XCTAssertEqual(nativeTOML.supportStatus, .supported)
        XCTAssertEqual(nativeTOML.relativePath, ".quillcode/config.toml#Stop/0/0")

        let codexTOML = try XCTUnwrap(hooks.first { $0.statusMessage == "Codex TOML" })
        XCTAssertEqual(codexTOML.commandWindows, "Write-Output codex-toml")
        XCTAssertEqual(codexTOML.matcher, "^Bash$")
        XCTAssertEqual(codexTOML.supportStatus, .supported)
        XCTAssertEqual(
            hooks.first { $0.handlerType == "prompt" }?.supportStatus,
            .unsupportedHandler
        )
    }

    func testAsyncAndInvalidHandlersStayVisibleButInert() throws {
        let root = try makeQuillCodeTestDirectory()
        try write(
            #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf later","async":true},{"type":"agent","command":"ignored"},{"type":"command"}]}]}}"#,
            to: ".codex/hooks.json",
            in: root
        )

        let hooks = ProjectHookConfigurationLoader.load(from: root)

        XCTAssertEqual(hooks.map(\.supportStatus), [
            .asynchronousHandler,
            .unsupportedHandler,
            .missingCommand
        ])
        XCTAssertTrue(ProjectPluginHookResolver.executableRunHooks(from: hooks).isEmpty)
    }

    func testMalformedOversizedAndSymlinkedDocumentsFailClosed() throws {
        let root = try makeQuillCodeTestDirectory()
        try write("not valid json", to: ".quillcode/hooks.json", in: root)
        try write(
            String(repeating: "x", count: ProjectHookConfigurationLoader.maxDocumentBytes + 1),
            to: ".quillcode/config.toml",
            in: root
        )

        let outside = try makeQuillCodeTestDirectory()
        let outsideHooks = outside.appendingPathComponent("hooks.json")
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf escaped"}]}]}}"#
            .write(to: outsideHooks, atomically: true, encoding: .utf8)
        let symlink = root.appendingPathComponent(".codex/hooks.json")
        try FileManager.default.createDirectory(
            at: symlink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideHooks)

        XCTAssertTrue(ProjectHookConfigurationLoader.load(from: root).isEmpty)
    }

    func testExactDefinitionTrustControlsDiscoveryAndExecution() async throws {
        let root = try makeQuillCodeTestDirectory()
        try writeExecutableHooks(commandSuffix: "v1", in: root)
        let trustStore = ProjectHookTrustFileStore(
            directory: root.appendingPathComponent(".test-hook-trust", isDirectory: true)
        )

        let unreviewed = WorkspaceProjectMetadataLoader.loadLocal(
            from: root,
            hookTrustStore: trustStore
        )
        XCTAssertEqual(unreviewed.pluginHooks.map(\.trustStatus), [.reviewRequired, .reviewRequired])
        XCTAssertTrue(unreviewed.runHooks.filter { $0.id.hasPrefix("config_hook:") }.isEmpty)

        for hook in unreviewed.pluginHooks {
            try trustStore.setDecision(.trusted, for: hook, workspaceRoot: root)
        }
        let trusted = WorkspaceProjectMetadataLoader.loadLocal(
            from: root,
            hookTrustStore: trustStore
        )
        XCTAssertEqual(trusted.pluginHooks.map(\.trustStatus), [.trusted, .trusted])
        XCTAssertEqual(trusted.runHooks.map(\.timing), [.afterAgentRun, .beforeAgentRun])

        let session = WorkspaceAgentSendSession(
            prompt: "say hello",
            thread: ChatThread(title: "Config hooks"),
            runner: AgentRunner(llm: ConfigurationHookCompletionLLM()),
            workspaceRoot: root,
            runHooks: trusted.runHooks
        )
        let result = try await session.run()

        XCTAssertEqual(try contents(of: "before-v1.txt", in: root), "before")
        XCTAssertEqual(try contents(of: "after-v1.txt", in: root), "after")
        XCTAssertEqual(result.thread.messages.map(\.content), ["say hello", "hello"])
        XCTAssertEqual(result.thread.events.filter { $0.kind == .toolCompleted }.count, 2)

        try writeExecutableHooks(commandSuffix: "v2", in: root)
        let changed = WorkspaceProjectMetadataLoader.loadLocal(
            from: root,
            hookTrustStore: trustStore
        )
        XCTAssertEqual(changed.pluginHooks.map(\.trustStatus), [.reviewRequired, .reviewRequired])
        XCTAssertTrue(changed.runHooks.filter { $0.id.hasPrefix("config_hook:") }.isEmpty)
    }

    func testTotalHookCountAcrossConfigurationDocumentsIsBounded() throws {
        let root = try makeQuillCodeTestDirectory()
        let handlers = (0..<(ProjectHookConfigurationLoader.maxHooks + 12))
            .map { #"{"type":"command","command":"printf \#($0)"}"# }
            .joined(separator: ",")
        try write(
            #"{"hooks":{"Stop":[{"hooks":[\#(handlers)]}]}}"#,
            to: ".quillcode/hooks.json",
            in: root
        )
        try write(
            #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf extra"}]}]}}"#,
            to: ".codex/hooks.json",
            in: root
        )

        let hooks = ProjectHookConfigurationLoader.load(from: root)

        XCTAssertEqual(hooks.count, ProjectHookConfigurationLoader.maxHooks)
        XCTAssertTrue(hooks.allSatisfy { $0.id.hasPrefix("config_hook:quillcode-json.") })
    }

    private func writeExecutableHooks(commandSuffix: String, in root: URL) throws {
        try write(
            """
            [[hooks.UserPromptSubmit]]

            [[hooks.UserPromptSubmit.hooks]]
            type = "command"
            command = "printf before > before-\(commandSuffix).txt"

            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf after > after-\(commandSuffix).txt"
            """,
            to: ".quillcode/config.toml",
            in: root
        )
    }

    private func write(_ content: String, to relativePath: String, in root: URL) throws {
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func contents(of relativePath: String, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private struct ConfigurationHookCompletionLLM: LLMClient {
    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        .say("hello")
    }
}
