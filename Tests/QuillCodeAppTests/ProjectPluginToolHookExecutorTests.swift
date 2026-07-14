import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

final class ProjectPluginToolHookExecutorTests: XCTestCase {
    func testRealPreAndPostHooksReceiveCanonicalPayloadAndShapeAgentFeedback() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        try preScript.write(
            to: pluginRoot.appendingPathComponent("pre.sh"),
            atomically: true,
            encoding: .utf8
        )
        try postScript.write(
            to: pluginRoot.appendingPathComponent("post.sh"),
            atomically: true,
            encoding: .utf8
        )

        let pluginDataBase = root.appendingPathComponent(".test-plugin-data", isDirectory: true)
        let executor = ProjectPluginToolHookExecutor(
            hooks: [
                hook(event: .preToolUse, command: #"sh "$PLUGIN_ROOT/pre.sh""#),
                hook(event: .postToolUse, command: #"sh "$PLUGIN_ROOT/post.sh""#)
            ],
            pluginDataBaseDirectory: pluginDataBase,
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let original = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )
        let runner = AgentRunner(
            llm: ToolHookSequenceLLM(actions: [.tool(original), .say("Finished.")]),
            safety: TestApprovingSafetyReviewer(),
            preToolUseHook: try XCTUnwrap(executor.preToolUseHook),
            postToolUseHook: try XCTUnwrap(executor.postToolUseHook)
        )

        let result = try await runner.send(
            "Run the command",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.first?.stdout, "post-hook feedback")
        XCTAssertEqual(
            result.thread.messages.filter { $0.role == .system }.map(\.content),
            [
                "Standard plugin hook context from Demo Hooks:\npre-only guidance",
                "Standard plugin hook context from Demo Hooks:\npost-only guidance"
            ]
        )
        XCTAssertEqual(
            result.thread.events.filter { $0.kind == .notice }.map(\.summary),
            [
                "Hook warning from Demo Hooks: pre warning",
                "Hook warning from Demo Hooks: post warning"
            ]
        )
        let transcriptBuilder = WorkspaceTranscriptSurfaceBuilder(thread: result.thread)
        let transcript = TranscriptSurface(
            messages: transcriptBuilder.messageSurfaces(),
            toolCards: transcriptBuilder.toolCards(),
            timelineItems: transcriptBuilder.timelineItems()
        )
        let exported = TranscriptMarkdownExporter.markdown(for: transcript)
        XCTAssertFalse(exported.contains("pre-only guidance"))
        XCTAssertFalse(exported.contains("post-only guidance"))
        XCTAssertFalse(
            WorkspaceThreadSeedBuilder.forkSeedMessages(from: result.thread.messages)
                .contains { $0.content.contains("only guidance") }
        )
        XCTAssertFalse(
            WorkspaceThreadSeedBuilder.compactSeedMessages(from: result.thread)
                .contains { $0.content.contains("only guidance") }
        )

        let pluginData = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: pluginDataBase,
            workspaceRoot: root,
            pluginID: "plugin:demo"
        )
        let pre = try jsonObject(at: pluginData.appendingPathComponent("pre.json"))
        XCTAssertEqual(pre["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(pre["tool_name"] as? String, "Bash")
        XCTAssertEqual(pre["tool_use_id"] as? String, original.id)
        XCTAssertEqual((pre["tool_input"] as? [String: Any])?["command"] as? String, "printf original")

        let post = try jsonObject(at: pluginData.appendingPathComponent("post.json"))
        XCTAssertEqual(post["hook_event_name"] as? String, "PostToolUse")
        XCTAssertEqual((post["tool_input"] as? [String: Any])?["command"] as? String, "printf rewritten")
        XCTAssertEqual((post["tool_response"] as? [String: Any])?["stdout"] as? String, "rewritten")
        XCTAssertEqual((post["tool_response"] as? [String: Any])?["ok"] as? Bool, true)
    }

    func testDenyWinsOverRewriteAndNonmatchingHookNeverRuns() async throws {
        let root = try makeQuillCodeTestDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true),
            withIntermediateDirectories: true
        )
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":"touch must-not-run"}}}"#.write(
            to: pluginRoot.appendingPathComponent("allow.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"denied by policy"}}"#.write(
            to: pluginRoot.appendingPathComponent("deny.json"),
            atomically: true,
            encoding: .utf8
        )
        let marker = root.appendingPathComponent("must-not-run")
        let ignored = root.appendingPathComponent("ignored-hook-ran")
        let executor = ProjectPluginToolHookExecutor(
            hooks: [
                hook(
                    event: .preToolUse,
                    command: #"cat "$PLUGIN_ROOT/allow.json""#
                ),
                hook(
                    event: .preToolUse,
                    command: #"cat "$PLUGIN_ROOT/deny.json""#
                ),
                hook(
                    event: .preToolUse,
                    matcher: "^Write$",
                    command: "touch \(ignored.path)"
                )
            ],
            pluginDataBaseDirectory: root.appendingPathComponent(".test-plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )

        let outcome = try await executor.runPreToolUse(
            call: call,
            thread: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(outcome.blockedReason, "denied by policy", outcome.notices.joined(separator: " | "))
        XCTAssertTrue(outcome.call.argumentsJSON.contains("touch must-not-run"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ignored.path))
    }

    func testFirstConfiguredRewriteWinsDeterministically() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        try #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":"printf first"}}}"#.write(
            to: pluginRoot.appendingPathComponent("first.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"command":"printf second"}}}"#.write(
            to: pluginRoot.appendingPathComponent("second.json"),
            atomically: true,
            encoding: .utf8
        )
        let executor = ProjectPluginToolHookExecutor(
            hooks: [
                hook(event: .preToolUse, command: #"cat "$PLUGIN_ROOT/first.json""#),
                hook(event: .preToolUse, command: #"cat "$PLUGIN_ROOT/second.json""#)
            ],
            pluginDataBaseDirectory: root.appendingPathComponent(".test-plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )

        let outcome = try await executor.runPreToolUse(
            call: call,
            thread: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertTrue(outcome.call.argumentsJSON.contains("printf first"))
        XCTAssertFalse(outcome.call.argumentsJSON.contains("printf second"))
        XCTAssertEqual(outcome.notices, ["Ignored another tool rewrite from Demo Hooks."])
    }

    func testPatchAliasRewritesThePatchBeforeRealExecution() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let rewrittenPatch = """
        diff --git a/rewritten.txt b/rewritten.txt
        new file mode 100644
        --- /dev/null
        +++ b/rewritten.txt
        @@ -0,0 +1 @@
        +rewritten
        """
        let output = try JSONSerialization.data(withJSONObject: [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "allow",
                "updatedInput": ["command": rewrittenPatch]
            ]
        ], options: [.sortedKeys])
        try output.write(to: pluginRoot.appendingPathComponent("rewrite.json"))
        let executor = ProjectPluginToolHookExecutor(
            hooks: [hook(
                event: .preToolUse,
                matcher: "^(Edit|Write)$",
                command: #"cat "$PLUGIN_ROOT/rewrite.json""#
            )],
            pluginDataBaseDirectory: root.appendingPathComponent(".test-plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let originalPatch = """
        diff --git a/original.txt b/original.txt
        new file mode 100644
        --- /dev/null
        +++ b/original.txt
        @@ -0,0 +1 @@
        +original
        """
        let call = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": originalPatch])
        )
        let runner = AgentRunner(
            llm: ToolHookSequenceLLM(actions: [.tool(call), .say("Finished.")]),
            safety: TestApprovingSafetyReviewer(),
            preToolUseHook: try XCTUnwrap(executor.preToolUseHook)
        )

        let result = try await runner.send(
            "Apply the patch",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertTrue(try XCTUnwrap(result.toolResults.first).ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("original.txt").path))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("rewritten.txt"), encoding: .utf8),
            "rewritten\n"
        )
    }

    func testMCPMatcherRewritesArgumentsBeforeExecutionOverride() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        try #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"path":"rewritten.txt"}}}"#.write(
            to: pluginRoot.appendingPathComponent("rewrite.json"),
            atomically: true,
            encoding: .utf8
        )
        let executor = ProjectPluginToolHookExecutor(
            hooks: [hook(
                event: .preToolUse,
                matcher: "^mcp__files__read_file$",
                command: #"cat "$PLUGIN_ROOT/rewrite.json""#
            )],
            pluginDataBaseDirectory: root.appendingPathComponent(".test-plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let capture = ToolCallCapture()
        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: ToolArguments.json([
                "serverID": "files",
                "toolName": "read_file",
                "arguments": ["path": "original.txt"]
            ])
        )
        let runner = AgentRunner(
            llm: ToolHookSequenceLLM(actions: [.tool(call), .say("Finished.")]),
            safety: TestApprovingSafetyReviewer(),
            additionalToolDefinitions: [.mcpCall],
            toolExecutionOverride: { call, _ in
                await capture.record(call)
                return ToolResult(ok: true, stdout: "mcp result")
            },
            preToolUseHook: try XCTUnwrap(executor.preToolUseHook)
        )

        let result = try await runner.send(
            "Read the file",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.first?.stdout, "mcp result")
        let capturedCall = await capture.value()
        let executed = try XCTUnwrap(capturedCall)
        let arguments = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(executed.argumentsJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(arguments["serverID"] as? String, "files")
        XCTAssertEqual(arguments["toolName"] as? String, "read_file")
        XCTAssertEqual((arguments["arguments"] as? [String: Any])?["path"] as? String, "rewritten.txt")
    }

    func testHookFailureWarnsAndLeavesOriginalCallUntouched() async throws {
        let root = try makeQuillCodeTestDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true),
            withIntermediateDirectories: true
        )
        let executor = ProjectPluginToolHookExecutor(
            hooks: [hook(event: .preToolUse, command: "printf invalid-json; exit 4")],
            pluginDataBaseDirectory: root.appendingPathComponent(".test-plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )

        let outcome = try await executor.runPreToolUse(
            call: call,
            thread: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(outcome.call, call)
        XCTAssertNil(outcome.blockedReason)
        XCTAssertEqual(outcome.notices.count, 1)
        XCTAssertTrue(outcome.notices[0].lowercased().contains("exit code 4"), outcome.notices[0])
        XCTAssertTrue(outcome.notices[0].contains("original tool call continued"))
    }

    func testPostHookRunsAfterFailedShellAndReceivesActualFailure() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        try #"cat > "$PLUGIN_DATA/failed-post.json""#.write(
            to: pluginRoot.appendingPathComponent("capture.sh"),
            atomically: true,
            encoding: .utf8
        )
        let pluginDataBase = root.appendingPathComponent(".test-plugin-data", isDirectory: true)
        let executor = ProjectPluginToolHookExecutor(
            hooks: [hook(event: .postToolUse, command: #"sh "$PLUGIN_ROOT/capture.sh""#)],
            pluginDataBaseDirectory: pluginDataBase,
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf failed >&2; exit 7"])
        )
        let runner = AgentRunner(
            llm: ToolHookSequenceLLM(actions: [.tool(call), .say("Handled.")]),
            safety: TestApprovingSafetyReviewer(),
            postToolUseHook: try XCTUnwrap(executor.postToolUseHook)
        )

        let result = try await runner.send(
            "Run the failing command",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertFalse(try XCTUnwrap(result.toolResults.first).ok)
        XCTAssertEqual(result.toolResults.first?.exitCode, 7)
        let pluginData = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: pluginDataBase,
            workspaceRoot: root,
            pluginID: "plugin:demo"
        )
        let payload = try jsonObject(at: pluginData.appendingPathComponent("failed-post.json"))
        let response = try XCTUnwrap(payload["tool_response"] as? [String: Any])
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["exitCode"] as? Int, 7)
        XCTAssertEqual(response["stderr"] as? String, "failed")
    }

    func testPermissionRequestUsesCanonicalPayloadAndDenyWinsAcrossHooks() async throws {
        let root = try makeQuillCodeTestDirectory()
        let pluginRoot = root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginRoot, withIntermediateDirectories: true)
        let pluginDataBase = root.appendingPathComponent(".test-plugin-data", isDirectory: true)
        let executor = ProjectPluginToolHookExecutor(
            hooks: [
                hook(
                    event: .permissionRequest,
                    command: #"cat > "$PLUGIN_DATA/permission.json"; printf '%s' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'"#
                ),
                hook(
                    event: .permissionRequest,
                    command: #"printf '%s' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"denied by policy"}}}'"#
                )
            ],
            pluginDataBaseDirectory: pluginDataBase,
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )

        let outcome = try await executor.runPermissionRequest(
            call: call,
            approvalReason: "Review mode requires approval.",
            thread: ChatThread(mode: .review),
            workspaceRoot: root
        )

        XCTAssertEqual(outcome.decision, .deny(reason: "denied by policy"))
        let pluginData = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: pluginDataBase,
            workspaceRoot: root,
            pluginID: "plugin:demo"
        )
        let payload = try jsonObject(at: pluginData.appendingPathComponent("permission.json"))
        XCTAssertEqual(payload["hook_event_name"] as? String, "PermissionRequest")
        XCTAssertEqual(payload["tool_name"] as? String, "Bash")
        XCTAssertNil(payload["tool_use_id"])
        let input = try XCTUnwrap(payload["tool_input"] as? [String: Any])
        XCTAssertEqual(input["command"] as? String, "printf original")
        XCTAssertEqual(input["description"] as? String, "Review mode requires approval.")

        let describedCall = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "printf described",
                "description": "Tool-provided reason"
            ])
        )
        let describedPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(ProjectPluginToolHookInvocationBuilder.inputJSON(
                event: .permissionRequest,
                adapter: try XCTUnwrap(ProjectPluginToolCallAdapter.make(for: describedCall)),
                toolResult: nil,
                approvalReason: "Safety-review fallback",
                thread: ChatThread(mode: .review),
                workspaceRoot: root
            ).utf8)) as? [String: Any]
        )
        XCTAssertEqual(
            (describedPayload["tool_input"] as? [String: Any])?["description"] as? String,
            "Tool-provided reason"
        )

        let boundedPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(ProjectPluginToolHookInvocationBuilder.inputJSON(
                event: .permissionRequest,
                adapter: try XCTUnwrap(ProjectPluginToolCallAdapter.make(for: call)),
                toolResult: nil,
                approvalReason: String(repeating: "r", count: 8_192) + "\0secret-tail",
                thread: ChatThread(mode: .review),
                workspaceRoot: root
            ).utf8)) as? [String: Any]
        )
        let boundedDescription = try XCTUnwrap(
            (boundedPayload["tool_input"] as? [String: Any])?["description"] as? String
        )
        XCTAssertEqual(
            boundedDescription.count,
            ProjectPluginToolHookInvocationBuilder.maximumApprovalReasonCharacters
        )
        XCTAssertFalse(boundedDescription.contains("\0"))
        XCTAssertFalse(boundedDescription.contains("secret-tail"))
    }

    func testPermissionRequestCommandFailurePreservesNormalApproval() async throws {
        let root = try makeQuillCodeTestDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".quillcode/plugins/demo", isDirectory: true),
            withIntermediateDirectories: true
        )
        let executor = ProjectPluginToolHookExecutor(
            hooks: [hook(event: .permissionRequest, command: "printf ignored; exit 2")],
            pluginDataBaseDirectory: root.appendingPathComponent(".test-plugin-data", isDirectory: true),
            selectedProject: nil,
            sshRemoteShellExecutor: SSHRemoteShellExecutor()
        )
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "printf original"])
        )

        let outcome = try await executor.runPermissionRequest(
            call: call,
            approvalReason: "Approval required.",
            thread: ChatThread(mode: .review),
            workspaceRoot: root
        )

        XCTAssertEqual(outcome.decision, .noDecision)
        XCTAssertEqual(outcome.notices.count, 1)
        XCTAssertTrue(outcome.notices[0].contains("Normal approval is still required"))
    }

    private func hook(
        event: ProjectPluginToolHookEvent,
        matcher: String? = "^Bash$",
        command: String
    ) -> ProjectPluginHook {
        ProjectPluginHook(
            id: "\(event.rawValue)-\(UUID().uuidString)",
            pluginID: "plugin:demo",
            pluginName: "Demo Hooks",
            event: event.rawValue,
            matcher: matcher,
            handlerType: "command",
            command: command,
            timeoutSeconds: 5,
            relativePath: ".quillcode/plugins/demo/hooks/hooks.json#\(event.rawValue)",
            pluginRootRelativePath: ".quillcode/plugins/demo",
            definitionHash: String(repeating: "a", count: 64),
            trustStatus: .trusted,
            supportStatus: .supported
        )
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private let preScript = #"""
    cat > "$PLUGIN_DATA/pre.json"
    printf '%s' '{"systemMessage":"pre warning","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"bounded rewrite","updatedInput":{"command":"printf rewritten"},"additionalContext":"pre-only guidance"}}'
    """#

    private let postScript = #"""
    cat > "$PLUGIN_DATA/post.json"
    printf '%s' '{"systemMessage":"post warning","decision":"block","reason":"post-hook feedback","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"post-only guidance"}}'
    """#
}

private actor ToolHookSequenceLLM: LLMClient {
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

private actor ToolCallCapture {
    private var call: ToolCall?

    func record(_ call: ToolCall) {
        self.call = call
    }

    func value() -> ToolCall? {
        call
    }
}

private struct TestApprovingSafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        SafetyReview(verdict: .approve, rationale: "Approved for test.", userIntentMatched: true)
    }
}
