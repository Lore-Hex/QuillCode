import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeHooks
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class GlobalHookConfigurationLoaderTests: XCTestCase {
    func testMergesUserSystemAndManagedSourcesInStableOrder() throws {
        let roots = try makeRoots()
        try writeJSONHook("system-codex", event: "SessionStart", in: roots.systemCodex)
        try writeJSONHook("system-quill", event: "PreToolUse", in: roots.systemQuillCode)
        try writeJSONHook("user-codex", event: "PostToolUse", in: roots.userCodex)
        try writeJSONHook("user-quill", event: "Stop", in: roots.userQuillCode)
        try write(
            """
            [hooks]
            managed_dir = "/enterprise/hooks"

            [[hooks.UserPromptSubmit]]

            [[hooks.UserPromptSubmit.hooks]]
            type = "command"
            command = "printf managed"
            statusMessage = "managed"
            """,
            to: roots.requirements
        )

        let loaded = GlobalHookConfigurationLoader.load(from: roots.paths)

        XCTAssertEqual(loaded.hooks.map(\.statusMessage), [
            "system-codex", "system-quill", "user-codex", "user-quill", "managed"
        ])
        XCTAssertEqual(loaded.hooks.map(\.effectiveTrustScope), [
            .managed, .managed, .user, .user, .managed
        ])
        XCTAssertEqual(loaded.hooks.map(\.trustStatus), [
            .trusted, .trusted, .reviewRequired, .reviewRequired, .trusted
        ])
        XCTAssertTrue(loaded.hooksEnabled)
        XCTAssertFalse(loaded.managedOnly)
        XCTAssertEqual(
            loaded.hooks.last?.relativePath,
            roots.requirements.path + "#UserPromptSubmit/0/0"
        )
    }

    func testManagedOnlyPolicySkipsUserAndProjectEligibleSources() throws {
        let roots = try makeRoots()
        try writeJSONHook("system", event: "Stop", in: roots.systemCodex)
        try writeJSONHook("user", event: "Stop", in: roots.userQuillCode)
        try write(
            """
            allow_managed_hooks_only = true

            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf policy"
            statusMessage = "policy"
            """,
            to: roots.requirements
        )

        let loaded = GlobalHookConfigurationLoader.load(from: roots.paths)

        XCTAssertTrue(loaded.managedOnly)
        XCTAssertEqual(loaded.hooks.map(\.statusMessage), ["system", "policy"])
        XCTAssertTrue(loaded.hooks.allSatisfy(\.isManaged))
    }

    func testManagedFeaturePinCanDisableEveryHookSource() throws {
        let roots = try makeRoots()
        try writeJSONHook("user", event: "Stop", in: roots.userQuillCode)
        try write(
            """
            [features]
            hooks = false

            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf policy"
            """,
            to: roots.requirements
        )

        let loaded = GlobalHookConfigurationLoader.load(from: roots.paths)

        XCTAssertFalse(loaded.hooksEnabled)
        XCTAssertTrue(loaded.hooks.isEmpty)
    }

    func testManagedPolicyAndHookAreNotStarvedByOrdinaryHookCap() throws {
        let roots = try makeRoots()
        let handlers = (0..<(GlobalHookConfigurationLoader.maxHooks + 20))
            .map { #"{"type":"command","command":"printf \#($0)"}"# }
            .joined(separator: ",")
        try #"{"hooks":{"Stop":[{"hooks":[\#(handlers)]}]}}"#
            .write(
                to: roots.userCodex.appendingPathComponent("hooks.json"),
                atomically: true,
                encoding: .utf8
            )
        try write(
            """
            allow_managed_hooks_only = true

            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf policy"
            statusMessage = "policy"
            """,
            to: roots.requirements
        )

        let loaded = GlobalHookConfigurationLoader.load(from: roots.paths)

        XCTAssertTrue(loaded.managedOnly)
        XCTAssertEqual(loaded.hooks.map(\.statusMessage), ["policy"])
        XCTAssertEqual(loaded.hooks.first?.effectiveTrustScope, .managed)
    }

    func testUserFeatureOverrideWinsOverSystemDefault() throws {
        let roots = try makeRoots()
        try write(
            """
            [features]
            hooks = false

            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf system"
            """,
            to: roots.systemCodex.appendingPathComponent("config.toml")
        )
        try write(
            """
            [features]
            hooks = true

            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf user"
            """,
            to: roots.userQuillCode.appendingPathComponent("config.toml")
        )

        let loaded = GlobalHookConfigurationLoader.load(from: roots.paths)

        XCTAssertTrue(loaded.hooksEnabled)
        XCTAssertEqual(loaded.hooks.count, 2)
    }

    func testUserTrustIsGlobalAndExecutesWithoutAProject() async throws {
        let roots = try makeRoots()
        try write(
            """
            [[hooks.UserPromptSubmit]]

            [[hooks.UserPromptSubmit.hooks]]
            type = "command"
            command = "printf before > global-before.txt"

            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf after > global-after.txt"
            """,
            to: roots.userQuillCode.appendingPathComponent("config.toml")
        )
        let trustStore = ProjectHookTrustFileStore(directory: roots.trust)
        let raw = GlobalHookConfigurationLoader.load(from: roots.paths)
        let unreviewed = raw.resolvingTrust(
            trustStore.load(forWorkspaceRoot: roots.userQuillCode)
        )
        XCTAssertEqual(unreviewed.hooks.map(\.trustStatus), [.reviewRequired, .reviewRequired])
        XCTAssertTrue(ProjectPluginHookResolver.executableRunHooks(from: unreviewed.hooks).isEmpty)

        for hook in unreviewed.hooks {
            try trustStore.setDecision(.trusted, for: hook, workspaceRoot: roots.userQuillCode)
        }
        let trusted = raw.resolvingTrust(
            trustStore.load(forWorkspaceRoot: roots.userQuillCode)
        )
        let session = WorkspaceAgentSendSession(
            prompt: "hello",
            thread: ChatThread(title: "Global hooks"),
            runner: AgentRunner(llm: GlobalHookCompletionLLM()),
            workspaceRoot: roots.workspace,
            runHooks: ProjectPluginHookResolver.executableRunHooks(from: trusted.hooks)
        )

        let result = try await session.run()

        XCTAssertEqual(try contents(of: "global-before.txt", in: roots.workspace), "before")
        XCTAssertEqual(try contents(of: "global-after.txt", in: roots.workspace), "after")
        XCTAssertEqual(result.thread.messages.map(\.content), ["hello", "done"])
    }

    func testUserRunHookStaysLocalWhenSelectedProjectIsRemote() async throws {
        let roots = try makeRoots()
        let remoteProject = ProjectRef(
            name: "Remote",
            path: "/remote/workspace",
            connection: .ssh(path: "/remote/workspace", host: "127.0.0.1", user: "nobody")
        )
        let hook = ProjectRunHook(
            id: "user-before",
            timing: .beforeAgentRun,
            title: "User before",
            relativePath: "~/.quillcode/config.toml#UserPromptSubmit",
            command: "printf local > user-hook-location.txt",
            trustScope: .user
        )
        let session = WorkspaceAgentSendSession(
            prompt: "hello",
            thread: ChatThread(title: "Global hook routing"),
            runner: AgentRunner(llm: GlobalHookCompletionLLM()),
            workspaceRoot: roots.workspace,
            runHooks: [hook],
            selectedProject: remoteProject,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let result = try await session.run()

        XCTAssertEqual(try contents(of: "user-hook-location.txt", in: roots.workspace), "local")
        XCTAssertEqual(result.thread.messages.map(\.content), ["hello", "done"])
        XCTAssertEqual(
            ProjectHookExecutionRouting.selectedProject(
                for: .workspace,
                selectedProject: remoteProject
            ),
            remoteProject
        )
        XCTAssertNil(ProjectHookExecutionRouting.selectedProject(for: .user, selectedProject: remoteProject))
        XCTAssertNil(ProjectHookExecutionRouting.selectedProject(for: .managed, selectedProject: remoteProject))
    }

    func testProjectlessModelCanReviewUserHookButNotManagedHook() throws {
        let roots = try makeRoots()
        try writeJSONHook("user", event: "Stop", in: roots.userQuillCode)
        try write(
            """
            [[hooks.Stop]]

            [[hooks.Stop.hooks]]
            type = "command"
            command = "printf managed"
            statusMessage = "managed"
            """,
            to: roots.requirements
        )
        let trustStore = ProjectHookTrustFileStore(directory: roots.trust)
        let configuration = GlobalHookConfigurationLoader.load(from: roots.paths)
            .resolvingTrust(trustStore.load(forWorkspaceRoot: roots.userQuillCode))
        let model = QuillCodeWorkspaceModel(
            projectHookTrustStore: trustStore,
            hookConfigurationPaths: roots.paths,
            globalHookTrustScope: roots.userQuillCode,
            globalHookConfiguration: configuration
        )
        let user = try XCTUnwrap(model.effectiveHookDefinitions(for: nil).first { !$0.isManaged })
        let managed = try XCTUnwrap(model.effectiveHookDefinitions(for: nil).first( where: \.isManaged))

        XCTAssertTrue(model.setProjectHookTrust(id: user.id, decision: .trusted))
        XCTAssertEqual(
            model.effectiveHookDefinitions(for: nil).first { $0.id == user.id }?.trustStatus,
            .trusted
        )
        XCTAssertFalse(model.setProjectHookTrust(id: managed.id, decision: .disabled))

        let surface = model.surface()
        XCTAssertEqual(surface.extensions.totalHookItems.count, 2)
        XCTAssertEqual(surface.extensions.totalHookItems.first { $0.id == managed.id }?.statusLabel, "Managed")
        XCTAssertNil(surface.extensions.totalHookItems.first { $0.id == managed.id }?.actionTitle)
        XCTAssertEqual(
            surface.commands.first { $0.id == "show-hooks" }?.isEnabled,
            true
        )
    }

    func testSymlinkedAndOversizedGlobalDocumentsFailClosed() throws {
        let roots = try makeRoots()
        try String(repeating: "x", count: CodexHookDocumentLoader.maxDocumentBytes + 1)
            .write(
                to: roots.userQuillCode.appendingPathComponent("config.toml"),
                atomically: true,
                encoding: .utf8
            )
        let outside = roots.workspace.appendingPathComponent("outside.json")
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"printf escaped"}]}]}}"#
            .write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: roots.userQuillCode.appendingPathComponent("hooks.json"),
            withDestinationURL: outside
        )

        XCTAssertTrue(GlobalHookConfigurationLoader.load(from: roots.paths).hooks.isEmpty)
    }

    private struct Roots {
        var workspace: URL
        var userQuillCode: URL
        var userCodex: URL
        var systemQuillCode: URL
        var systemCodex: URL
        var requirements: URL
        var trust: URL

        var paths: HookConfigurationPaths {
            HookConfigurationPaths(
                userQuillCodeDirectory: userQuillCode,
                userCodexDirectory: userCodex,
                systemQuillCodeDirectory: systemQuillCode,
                systemCodexDirectory: systemCodex,
                managedRequirementFiles: [requirements]
            )
        }
    }

    private func makeRoots() throws -> Roots {
        let root = try makeQuillCodeTestDirectory()
        let result = Roots(
            workspace: root.appendingPathComponent("workspace", isDirectory: true),
            userQuillCode: root.appendingPathComponent("user-quillcode", isDirectory: true),
            userCodex: root.appendingPathComponent("user-codex", isDirectory: true),
            systemQuillCode: root.appendingPathComponent("system-quillcode", isDirectory: true),
            systemCodex: root.appendingPathComponent("system-codex", isDirectory: true),
            requirements: root.appendingPathComponent("managed/requirements.toml"),
            trust: root.appendingPathComponent("trust", isDirectory: true)
        )
        for directory in [
            result.workspace,
            result.userQuillCode,
            result.userCodex,
            result.systemQuillCode,
            result.systemCodex,
            result.requirements.deletingLastPathComponent()
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return result
    }

    private func writeJSONHook(_ name: String, event: String, in root: URL) throws {
        try #"{"hooks":{"\#(event)":[{"hooks":[{"type":"command","command":"printf \#(name)","statusMessage":"\#(name)"}]}]}}"#
            .write(
                to: root.appendingPathComponent("hooks.json"),
                atomically: true,
                encoding: .utf8
            )
    }

    private func write(_ content: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    private func contents(of relativePath: String, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}

private struct GlobalHookCompletionLLM: LLMClient {
    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        .say("done")
    }
}
