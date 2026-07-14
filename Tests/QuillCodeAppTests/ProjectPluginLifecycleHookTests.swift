import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class ProjectPluginLifecycleHookTests: XCTestCase {
    func testSessionStartInvocationUsesActiveSessionAndOmitsTurnID() throws {
        let root = try workspaceWithPluginRoot()
        let thread = ChatThread(mode: .auto, model: "trustedrouter/fast")
        let invocation = try ProjectPluginLifecycleHookInvocationBuilder.build(
            hook: hook(event: "SessionStart", command: "true"),
            event: .sessionStart(.resume),
            sessionThread: thread,
            workspaceRoot: root,
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true)
        )

        let payload = try invocationPayload(invocation)

        XCTAssertEqual(payload["session_id"] as? String, thread.id.uuidString.lowercased())
        XCTAssertEqual(payload["hook_event_name"] as? String, "SessionStart")
        XCTAssertEqual(payload["source"] as? String, "resume")
        XCTAssertEqual(payload["permission_mode"] as? String, "dontAsk")
        XCTAssertEqual(payload["model"] as? String, "trustedrouter/fast")
        XCTAssertNil(payload["turn_id"])
    }

    func testSubagentStopInvocationUsesParentIdentityAndStopFields() throws {
        let root = try workspaceWithPluginRoot()
        var parent = ChatThread(mode: .review, model: "trustedrouter/synth")
        let turn = ChatMessage(role: .user, content: "Delegate this")
        parent.messages.append(turn)
        let child = ChatThread(title: "Subagent")
        let context = ProjectPluginSubagentHookContext(
            parentThread: parent,
            agentID: "worker-7",
            agentType: "Verifier",
            transcriptPath: "/tmp/worker-7.json"
        )
        let invocation = try ProjectPluginLifecycleHookInvocationBuilder.build(
            hook: hook(event: "SubagentStop", command: "true"),
            event: .subagentStop(
                context,
                stopHookActive: true,
                lastAssistantMessage: "Verified."
            ),
            sessionThread: child,
            workspaceRoot: root,
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true)
        )

        let payload = try invocationPayload(invocation)

        XCTAssertEqual(payload["session_id"] as? String, parent.id.uuidString.lowercased())
        XCTAssertEqual(payload["turn_id"] as? String, turn.id.uuidString.lowercased())
        XCTAssertEqual(payload["agent_id"] as? String, "worker-7")
        XCTAssertEqual(payload["agent_type"] as? String, "Verifier")
        XCTAssertEqual(payload["agent_transcript_path"] as? String, "/tmp/worker-7.json")
        XCTAssertEqual(payload["stop_hook_active"] as? Bool, true)
        XCTAssertEqual(payload["last_assistant_message"] as? String, "Verified.")
        XCTAssertEqual(payload["permission_mode"] as? String, "default")
    }

    func testParserSupportsContextAndStrictSubagentStopContinuation() throws {
        let start = try ProjectPluginLifecycleHookOutputParser.parse(
            event: .sessionStart(.startup),
            result: ToolResult(ok: true, stdout: "workspace guidance")
        )
        XCTAssertEqual(start.additionalContext, "workspace guidance")

        let specific = try ProjectPluginLifecycleHookOutputParser.parse(
            event: .subagentStart(subagentContext()),
            result: ToolResult(
                ok: true,
                stdout: #"{"systemMessage":"notice","hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"worker guidance"}}"#
            )
        )
        XCTAssertEqual(specific.additionalContext, "worker guidance")
        XCTAssertEqual(specific.systemMessage, "notice")

        XCTAssertThrowsError(try ProjectPluginLifecycleHookOutputParser.parse(
            event: .subagentStop(subagentContext(), stopHookActive: false, lastAssistantMessage: nil),
            result: ToolResult(ok: true, stdout: "continue working")
        ))

        let blocked = try ProjectPluginLifecycleHookOutputParser.parse(
            event: .subagentStop(subagentContext(), stopHookActive: false, lastAssistantMessage: nil),
            result: ToolResult(ok: true, stdout: #"{"decision":"block","reason":"run tests"}"#)
        )
        XCTAssertEqual(blocked.continuationReason, "run tests")

        let exitTwo = try ProjectPluginLifecycleHookOutputParser.parse(
            event: .subagentStop(subagentContext(), stopHookActive: false, lastAssistantMessage: nil),
            result: ToolResult(ok: false, stderr: "check the diff", exitCode: 2)
        )
        XCTAssertEqual(exitTwo.continuationReason, "check the diff")
    }

    func testExecutorHonorsMatchersAndEventControlSemantics() async throws {
        let root = try workspaceWithPluginRoot()
        let executor = ProjectPluginLifecycleHookExecutor(
            hooks: [
                hook(
                    event: "SubagentStart",
                    matcher: "^Verifier$",
                    command: #"printf '%s' '{"continue":false,"stopReason":"ignored","hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"verify carefully"}}'"#
                ),
                hook(
                    event: "SubagentStart",
                    matcher: "^Builder$",
                    command: "touch should-not-run"
                )
            ],
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )

        let report = await executor.run(
            event: .subagentStart(subagentContext()),
            sessionThread: ChatThread(),
            workspaceRoot: root
        )

        XCTAssertTrue(report.continues)
        XCTAssertEqual(report.contexts.map(\.content), ["verify carefully"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("should-not-run").path))

        let stopExecutor = ProjectPluginLifecycleHookExecutor(
            hooks: [hook(
                event: "SubagentStop",
                command: #"printf '%s' '{"continue":false,"stopReason":"stop now","decision":"block","reason":"ignored continuation"}'"#
            )],
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let stop = await stopExecutor.run(
            event: .subagentStop(subagentContext(), stopHookActive: false, lastAssistantMessage: nil),
            sessionThread: ChatThread(),
            workspaceRoot: root
        )
        XCTAssertFalse(stop.continues)
        XCTAssertEqual(stop.stopReason, "stop now")
        XCTAssertNil(stop.continuationReason)
    }

    func testSessionStartRunsOnceUntilCoordinatorIsReset() async throws {
        let root = try workspaceWithPluginRoot()
        let coordinator = WorkspaceSessionStartHookCoordinator()
        let lifecycleExecutor = ProjectPluginLifecycleHookExecutor(
            hooks: [hook(event: "SessionStart", command: "printf session-context")],
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let first = try await WorkspaceAgentSendSession(
            prompt: "first",
            thread: ChatThread(title: "Lifecycle"),
            runner: AgentRunner(llm: LifecycleSequenceLLM(actions: [.say("one")])),
            workspaceRoot: root,
            pluginLifecycleHooks: lifecycleExecutor,
            lifecycle: .primary(coordinator)
        ).run()
        let second = try await WorkspaceAgentSendSession(
            prompt: "second",
            thread: first.thread,
            runner: AgentRunner(llm: LifecycleSequenceLLM(actions: [.say("two")])),
            workspaceRoot: root,
            pluginLifecycleHooks: lifecycleExecutor,
            lifecycle: .primary(coordinator)
        ).run()

        XCTAssertEqual(
            second.thread.messages.filter { $0.role == .system }.map(\.content),
            ["Standard plugin SessionStart context from Demo Hooks:\nsession-context"]
        )
        XCTAssertEqual(second.thread.messages.filter { $0.role == .assistant }.map(\.content), ["one", "two"])

        coordinator.reset(threadID: second.thread.id, source: .clear)
        let third = try await WorkspaceAgentSendSession(
            prompt: "third",
            thread: second.thread,
            runner: AgentRunner(llm: LifecycleSequenceLLM(actions: [.say("three")])),
            workspaceRoot: root,
            pluginLifecycleHooks: lifecycleExecutor,
            lifecycle: .primary(coordinator)
        ).run()
        XCTAssertEqual(third.thread.messages.filter { $0.role == .system }.count, 2)
    }

    func testSessionStartStopKeepsTheSubmittedPrompt() async throws {
        let root = try workspaceWithPluginRoot()
        let lifecycleExecutor = ProjectPluginLifecycleHookExecutor(
            hooks: [hook(
                event: "SessionStart",
                command: #"printf '%s' '{"continue":false,"stopReason":"workspace unavailable"}'"#
            )],
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let result = try await WorkspaceAgentSendSession(
            prompt: "keep this request",
            thread: ChatThread(title: "Lifecycle"),
            runner: AgentRunner(llm: LifecycleSequenceLLM(actions: [.say("must not run")])),
            workspaceRoot: root,
            pluginLifecycleHooks: lifecycleExecutor
        ).run()

        XCTAssertEqual(result.thread.messages.first?.role, .user)
        XCTAssertEqual(result.thread.messages.first?.content, "keep this request")
        XCTAssertTrue(result.thread.messages.last?.content.contains("workspace unavailable") == true)
        XCTAssertFalse(result.thread.messages.contains { $0.content == "must not run" })
    }

    func testSubagentStopCanRequestOnlyOneContinuation() async throws {
        let root = try workspaceWithPluginRoot()
        let lifecycleExecutor = ProjectPluginLifecycleHookExecutor(
            hooks: [hook(
                event: "SubagentStop",
                matcher: "^Verifier$",
                command: #"printf '%s' '{"decision":"block","reason":"Run one final verification."}'"#
            )],
            pluginDataBaseDirectory: root.appendingPathComponent("plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let session = WorkspaceAgentSendSession(
            prompt: "inspect",
            thread: ChatThread(title: "Subagent"),
            runner: AgentRunner(llm: LifecycleSequenceLLM(actions: [.say("Inspected."), .say("Verified.")])),
            workspaceRoot: root,
            pluginLifecycleHooks: lifecycleExecutor,
            lifecycle: .subagent(subagentContext(), runsStartHook: false)
        )

        let result = try await session.run()

        XCTAssertEqual(result.thread.messages.filter { $0.role == .assistant }.map(\.content), ["Inspected.", "Verified."])
        XCTAssertEqual(result.thread.messages.filter { $0.role == .user }.map(\.content), ["inspect", "Run one final verification."])
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary == "Ignored another SubagentStop-hook continuation."
        })
    }

    private func workspaceWithPluginRoot() throws -> URL {
        let root = try makeQuillCodeTestDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }

    private func hook(
        event: String,
        matcher: String? = nil,
        command: String
    ) -> ProjectPluginHook {
        ProjectPluginHook(
            id: "\(event)-\(UUID().uuidString)",
            pluginID: "plugin:demo",
            pluginName: "Demo Hooks",
            event: event,
            matcher: matcher,
            handlerType: "command",
            command: command,
            timeoutSeconds: 5,
            relativePath: ".quillcode/plugins/demo/hooks/hooks.json#\(event)",
            pluginRootRelativePath: ".quillcode/plugins/demo",
            definitionHash: String(repeating: "a", count: 64),
            trustStatus: .trusted,
            supportStatus: .supported
        )
    }

    private func subagentContext() -> ProjectPluginSubagentHookContext {
        ProjectPluginSubagentHookContext(
            parentThread: ChatThread(mode: .auto),
            agentID: "worker-7",
            agentType: "Verifier",
            transcriptPath: nil
        )
    }

    private func invocationPayload(
        _ invocation: ProjectPluginLifecycleHookInvocation
    ) throws -> [String: Any] {
        let arguments = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(invocation.call.argumentsJSON.utf8))
                as? [String: Any]
        )
        let stdin = try XCTUnwrap(arguments["stdin"] as? String)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(stdin.utf8)) as? [String: Any]
        )
    }
}

private actor LifecycleSequenceLLM: LLMClient {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        actions.isEmpty ? .say("Done.") : actions.removeFirst()
    }
}

final class WorkspaceSessionStartHookCoordinatorTests: XCTestCase {
    func testSourcesAreOneShotAndCanBeRearmed() {
        let resumedID = UUID()
        let coordinator = WorkspaceSessionStartHookCoordinator(resumedThreadIDs: [resumedID])

        XCTAssertEqual(coordinator.consumeSource(for: resumedID), .resume)
        XCTAssertNil(coordinator.consumeSource(for: resumedID))

        let createdID = UUID()
        coordinator.registerCreatedThread(createdID)
        XCTAssertEqual(coordinator.consumeSource(for: createdID), .startup)

        coordinator.reset(threadID: createdID, source: .compact)
        XCTAssertEqual(coordinator.consumeSource(for: createdID), .compact)

        coordinator.reset(threadID: createdID, source: .clear)
        XCTAssertEqual(coordinator.consumeSource(for: createdID), .clear)

        coordinator.remove(threadID: createdID)
        XCTAssertEqual(coordinator.consumeSource(for: createdID), .startup)
    }
}
