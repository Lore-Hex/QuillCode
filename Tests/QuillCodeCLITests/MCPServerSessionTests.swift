import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
import XCTest

final class MCPServerSessionTests: XCTestCase {
    func testInitializesListsToolsAndReturnsProtocolErrors() async throws {
        let fixture = try makeFixture(llm: MCPTestEchoLLM())
        try await fixture.initialize()
        try await fixture.send(id: .integer(2), method: "tools/list", params: .object([:]))
        try await fixture.send(id: .integer(3), method: "missing/method", params: .object([:]))

        let initialized = try await fixture.waitForMessage { $0["id"] == .number(1) }
        XCTAssertEqual(initialized["jsonrpc"], .string("2.0"))
        XCTAssertEqual(
            initialized["result"]?.objectValue?["serverInfo"]?.objectValue?["name"],
            .string("quillcode-mcp-server")
        )
        XCTAssertEqual(
            initialized["result"]?.objectValue?["protocolVersion"],
            .string(MCPServerSession.protocolVersion)
        )

        let list = try await fixture.waitForMessage { $0["id"] == .number(2) }
        XCTAssertEqual(
            list["result"]?.objectValue?["tools"]?.arrayValue?.compactMap {
                $0.objectValue?["name"]?.stringValue
            },
            ["codex", "codex-reply"]
        )
        let missing = try await fixture.waitForMessage { $0["id"] == .number(3) }
        XCTAssertEqual(missing["error"]?.objectValue?["code"], .number(-32601))
        await fixture.finish()
    }

    func testInitializeRejectsIncompleteParametersWithoutAdvancingHandshake() async throws {
        let fixture = try makeFixture(llm: MCPTestEchoLLM())
        try await fixture.send(
            id: .integer(1),
            method: "initialize",
            params: .object(["protocolVersion": .string("future-version")])
        )
        let invalid = try await fixture.waitForMessage { $0["id"] == .number(1) }
        XCTAssertEqual(invalid["error"]?.objectValue?["code"], .number(-32602))

        try await fixture.initialize(requestID: 2, protocolVersion: "future-version")
        let initialized = try await fixture.waitForMessage { $0["id"] == .number(2) }
        XCTAssertEqual(
            initialized["result"]?.objectValue?["protocolVersion"],
            .string(MCPServerSession.protocolVersion)
        )
        await fixture.finish()
    }

    func testStartAndReplyPersistOneDurableThreadWithRuntimeSettings() async throws {
        let fixture = try makeFixture(llm: MCPTestEchoLLM())
        try await fixture.initialize()
        try await fixture.callTool(
            id: .string("start"),
            name: "codex",
            arguments: .object([
                "prompt": .string("first prompt"),
                "cwd": .string(fixture.workspace.path),
                "approval-policy": .string("never"),
                "sandbox": .string("workspace-write"),
                "base-instructions": .string("Use concise output."),
                "developer-instructions": .string("Preserve tests."),
                "compact-prompt": .string("Retain decisions."),
                "config": .object(["max_tool_steps": .number(11)])
            ])
        )
        let start = try await fixture.waitForMessage { $0["id"] == .string("start") }
        let startResult = try XCTUnwrap(start["result"]?.objectValue)
        XCTAssertEqual(startResult["isError"], .bool(false))
        let threadIDText = try XCTUnwrap(
            startResult["structuredContent"]?.objectValue?["threadId"]?.stringValue
        )
        let threadID = try XCTUnwrap(UUID(uuidString: threadIDText))

        try await fixture.callTool(
            id: .string("reply"),
            name: "codex-reply",
            arguments: .object([
                "threadId": .string(threadIDText),
                "prompt": .string("second prompt")
            ])
        )
        let reply = try await fixture.waitForMessage { $0["id"] == .string("reply") }
        XCTAssertEqual(
            reply["result"]?.objectValue?["structuredContent"]?.objectValue?["content"],
            .string("second prompt")
        )
        await fixture.finish()

        let record = try await AppServerThreadRepository(
            paths: QuillCodePaths(home: fixture.home),
            fallbackCWD: fixture.workspace
        ).load(threadID)
        XCTAssertEqual(record.settings.runtimeAppConfig?.maxToolSteps, 11)
        XCTAssertEqual(record.settings.compactPrompt, "Retain decisions.")
        XCTAssertEqual(record.settings.sandbox, .workspaceWrite)
        XCTAssertEqual(record.settings.approvalPolicy, .string("never"))
        XCTAssertEqual(record.thread.messages.filter { $0.role == .system }.map(\.content), [
            "Base instructions:\nUse concise output.",
            "Developer instructions:\nPreserve tests."
        ])
        XCTAssertEqual(record.thread.messages.filter { $0.role == .user }.map(\.content), [
            "first prompt", "second prompt"
        ])
        XCTAssertEqual(record.thread.messages.filter { $0.role == .assistant }.map(\.content), [
            "first prompt", "second prompt"
        ])

        let messages = await fixture.sink.snapshot()
        XCTAssertTrue(messages.contains { message in
            message["method"] == .string("codex/event")
                && message["params"]?.objectValue?["msg"]?.objectValue?["type"] == .string("session_configured")
                && message["params"]?.objectValue?["_meta"]?.objectValue?["threadId"] == .string(threadIDText)
        })
    }

    func testReviewModeElicitsApprovalAndRunsAfterApprovedResponse() async throws {
        let llm = MCPTestScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json(["path": "approved.txt", "content": "approved\n"])
            )),
            .say("File created.")
        ])
        let fixture = try makeFixture(llm: llm)
        try await fixture.initialize()
        try await fixture.callTool(
            id: .string("approval-call"),
            name: "codex",
            arguments: .object([
                "prompt": .string("create approved.txt"),
                "cwd": .string(fixture.workspace.path),
                "approval-policy": .string("on-request"),
                "sandbox": .string("workspace-write")
            ])
        )

        let approval = try await fixture.waitForMessage { message in
            message["method"] == .string("elicitation/create")
        }
        let approvalID = try XCTUnwrap(MCPServerRequestID(jsonValue: approval["id"]))
        XCTAssertEqual(
            approval["params"]?.objectValue?["codex_elicitation"],
            .string("patch-approval")
        )
        let params = try XCTUnwrap(approval["params"]?.objectValue)
        let fileChanges = try XCTUnwrap(params["codex_file_changes"]?.objectValue)
        XCTAssertEqual(fileChanges["approved.txt"]?.objectValue?["kind"], .string("write"))
        XCTAssertEqual(
            params["codex_changes"]?.objectValue?["changes"]?.objectValue?["approved.txt"]?.objectValue?["path"],
            .string("approved.txt")
        )
        try await fixture.respond(
            id: approvalID,
            result: .object(["decision": .string("approved")])
        )

        let response = try await fixture.waitForMessage { $0["id"] == .string("approval-call") }
        XCTAssertEqual(response["result"]?.objectValue?["isError"], .bool(false))
        XCTAssertEqual(
            try String(contentsOf: fixture.workspace.appendingPathComponent("approved.txt"), encoding: .utf8),
            "approved\n"
        )
        await fixture.finish()
    }

    func testNestedApprovalDenialCannotBeOverriddenByCompatibilityAction() async throws {
        let llm = MCPTestScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json(["path": "denied.txt", "content": "denied\n"])
            )),
            .say("Request handled.")
        ])
        let fixture = try makeFixture(llm: llm)
        try await fixture.initialize()
        try await fixture.callTool(
            id: .string("conflicting-approval"),
            name: "codex",
            arguments: .object([
                "prompt": .string("create denied.txt"),
                "cwd": .string(fixture.workspace.path),
                "approval-policy": .string("on-request"),
                "sandbox": .string("workspace-write")
            ])
        )

        let approval = try await fixture.waitForMessage { message in
            message["method"] == .string("elicitation/create")
        }
        let approvalID = try XCTUnwrap(MCPServerRequestID(jsonValue: approval["id"]))
        try await fixture.respond(id: approvalID, result: .object([
            "action": .string("accept"),
            "content": .object(["decision": .string("denied")])
        ]))

        _ = try await fixture.waitForMessage { $0["id"] == .string("conflicting-approval") }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.workspace.appendingPathComponent("denied.txt").path
        ))
        await fixture.finish()
    }

    func testPatchApprovalIncludesPathKeyedFileChangeMetadata() async throws {
        let patch = """
        diff --git a/created.txt b/created.txt
        new file mode 100644
        index 0000000..3b18e51
        --- /dev/null
        +++ b/created.txt
        @@ -0,0 +1 @@
        +hello
        diff --git a/existing.txt b/existing.txt
        index 3b18e51..f2ba8f8 100644
        --- a/existing.txt
        +++ b/existing.txt
        @@ -1 +1 @@
        -old
        +new
        """
        let llm = MCPTestScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.applyPatch.name,
                argumentsJSON: ToolArguments.json(["patch": patch])
            )),
            .say("Patch applied.")
        ])
        let fixture = try makeFixture(llm: llm)
        try "old\n".write(
            to: fixture.workspace.appendingPathComponent("existing.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await fixture.initialize()
        try await fixture.callTool(
            id: .string("patch-approval-call"),
            name: "codex",
            arguments: .object([
                "prompt": .string("apply patch"),
                "cwd": .string(fixture.workspace.path),
                "approval-policy": .string("on-request"),
                "sandbox": .string("workspace-write")
            ])
        )

        let approval = try await fixture.waitForMessage { message in
            message["method"] == .string("elicitation/create")
        }
        let approvalID = try XCTUnwrap(MCPServerRequestID(jsonValue: approval["id"]))
        let changes = try XCTUnwrap(
            approval["params"]?.objectValue?["codex_file_changes"]?.objectValue
        )
        XCTAssertEqual(changes["created.txt"]?.objectValue?["kind"], .string("create"))
        XCTAssertEqual(changes["existing.txt"]?.objectValue?["kind"], .string("modify"))
        XCTAssertNil(changes["/dev/null"])

        try await fixture.respond(
            id: approvalID,
            result: .object(["decision": .string("denied")])
        )

        let response = try await fixture.waitForMessage { $0["id"] == .string("patch-approval-call") }
        XCTAssertEqual(response["result"]?.objectValue?["isError"], .bool(false))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.workspace.appendingPathComponent("created.txt").path
        ))
        XCTAssertEqual(
            try String(contentsOf: fixture.workspace.appendingPathComponent("existing.txt"), encoding: .utf8),
            "old\n"
        )
        await fixture.finish()
    }

    func testCancelledNotificationCancelsActiveToolCallAndReturnsTypedError() async throws {
        let llm = MCPTestBlockingLLM()
        let fixture = try makeFixture(llm: llm)
        try await fixture.initialize()
        try await fixture.callTool(
            id: .string("cancel-me"),
            name: "codex",
            arguments: .object([
                "prompt": .string("wait"),
                "cwd": .string(fixture.workspace.path),
                "approval-policy": .string("never")
            ])
        )
        await llm.waitUntilStarted()
        try await fixture.notify(
            method: "notifications/cancelled",
            params: .object(["requestId": .string("cancel-me"), "reason": .string("test")])
        )
        let response = try await fixture.waitForMessage { $0["id"] == .string("cancel-me") }
        XCTAssertEqual(response["result"]?.objectValue?["isError"], .bool(true))
        XCTAssertTrue(
            response["result"]?.objectValue?["structuredContent"]?.objectValue?["content"]?
                .stringValue?.contains("cancelled") == true
        )
        await fixture.finish()
    }

    func testDuplicateActiveRequestIDIsRejectedWithoutReplacingOriginalCall() async throws {
        let llm = MCPTestBlockingLLM()
        let fixture = try makeFixture(llm: llm)
        try await fixture.initialize()
        let arguments: CLIJSONValue = .object([
            "prompt": .string("wait"),
            "cwd": .string(fixture.workspace.path),
            "approval-policy": .string("never")
        ])
        try await fixture.callTool(id: .string("same-id"), name: "codex", arguments: arguments)
        await llm.waitUntilStarted()
        try await fixture.callTool(id: .string("same-id"), name: "codex", arguments: arguments)

        let duplicate = try await fixture.waitForMessage { message in
            message["id"] == .string("same-id")
                && message["error"]?.objectValue?["code"] == .number(-32600)
        }
        XCTAssertEqual(
            duplicate["error"]?.objectValue?["message"],
            .string("Request id is already active")
        )

        try await fixture.notify(
            method: "notifications/cancelled",
            params: .object(["requestId": .string("same-id")])
        )
        let cancelled = try await fixture.waitForMessage { message in
            message["id"] == .string("same-id")
                && message["result"]?.objectValue?["isError"] == .bool(true)
        }
        XCTAssertNotNil(cancelled["result"])
        await fixture.finish()
    }

    func testUnknownToolAndMissingReplyThreadAreMCPToolErrorsNotJSONRPCErrors() async throws {
        let fixture = try makeFixture(llm: MCPTestEchoLLM())
        try await fixture.initialize()
        try await fixture.callTool(id: .integer(8), name: "unknown", arguments: .object([:]))
        try await fixture.callTool(
            id: .integer(9),
            name: "codex-reply",
            arguments: .object([
                "threadId": .string(UUID().uuidString),
                "prompt": .string("continue")
            ])
        )
        let unknown = try await fixture.waitForMessage { $0["id"] == .number(8) }
        XCTAssertNil(unknown["error"])
        XCTAssertEqual(unknown["result"]?.objectValue?["isError"], .bool(true))
        let missing = try await fixture.waitForMessage { $0["id"] == .number(9) }
        XCTAssertNil(missing["error"])
        XCTAssertEqual(missing["result"]?.objectValue?["isError"], .bool(true))
        await fixture.finish()
    }

    private func makeFixture(llm: any LLMClient) throws -> MCPServerTestFixture {
        try MCPServerTestFixture(testCase: self, llm: llm)
    }
}

private struct MCPServerTestFixture {
    let home: URL
    let workspace: URL
    let sink: MCPServerTestSink
    let session: MCPServerSession

    init(testCase: XCTestCase, llm: any LLMClient) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quillcode-mcp-server-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        home = root.appendingPathComponent("home", isDirectory: true)
        workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        sink = MCPServerTestSink()
        session = try MCPServerSession(
            request: CLIMCPServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: true
                )
            },
            sink: { [sink] line in await sink.append(line) }
        )
    }

    func initialize(
        requestID: Int64 = 1,
        protocolVersion: String = MCPServerSession.protocolVersion
    ) async throws {
        try await send(id: .integer(requestID), method: "initialize", params: .object([
            "protocolVersion": .string(protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("tests"), "version": .string("1")])
        ]))
        try await notify(method: "notifications/initialized", params: .object([:]))
    }

    func callTool(
        id: MCPServerRequestID,
        name: String,
        arguments: CLIJSONValue
    ) async throws {
        try await send(id: id, method: "tools/call", params: .object([
            "name": .string(name),
            "arguments": arguments
        ]))
    }

    func send(id: MCPServerRequestID, method: String, params: CLIJSONValue) async throws {
        await session.receive(try MCPServerWireTestCodec.data(
            id: id,
            method: method,
            params: params
        ))
    }

    func notify(method: String, params: CLIJSONValue) async throws {
        await session.receive(try MCPServerWireTestCodec.notificationData(
            method: method,
            params: params
        ))
    }

    func respond(id: MCPServerRequestID, result: CLIJSONValue) async throws {
        await session.receive(try MCPServerWireTestCodec.responseData(id: id, result: result))
    }

    func waitForMessage(
        _ predicate: @escaping ([String: CLIJSONValue]) -> Bool
    ) async throws -> [String: CLIJSONValue] {
        for _ in 0..<300 {
            if let message = await sink.snapshot().first(where: predicate) { return message }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw MCPServerTestError.timeout
    }

    func finish() async {
        await session.finishInput()
        await session.waitForActiveCalls()
    }
}

private actor MCPServerTestSink {
    private var messages: [[String: CLIJSONValue]] = []

    func append(_ line: String) {
        guard let value = try? CLIJSONCodec.decode(line), let object = value.objectValue else { return }
        messages.append(object)
    }

    func snapshot() -> [[String: CLIJSONValue]] { messages }
}

private enum MCPServerWireTestCodec {
    static func data(
        id: MCPServerRequestID,
        method: String,
        params: CLIJSONValue
    ) throws -> Data {
        try CLIJSONCodec.encode(.object([
            "jsonrpc": .string("2.0"),
            "id": id.jsonValue,
            "method": .string(method),
            "params": params
        ]))
    }

    static func notificationData(method: String, params: CLIJSONValue) throws -> Data {
        try CLIJSONCodec.encode(.object([
            "jsonrpc": .string("2.0"),
            "method": .string(method),
            "params": params
        ]))
    }

    static func responseData(id: MCPServerRequestID, result: CLIJSONValue) throws -> Data {
        try CLIJSONCodec.encode(.object([
            "jsonrpc": .string("2.0"),
            "id": id.jsonValue,
            "result": result
        ]))
    }
}

private extension MCPServerRequestID {
    init?(jsonValue: CLIJSONValue?) {
        if let string = jsonValue?.stringValue {
            self = .string(string)
        } else if let number = jsonValue?.numberValue, number.rounded() == number {
            self = .integer(Int64(number))
        } else {
            return nil
        }
    }

    var jsonValue: CLIJSONValue {
        switch self {
        case .string(let value): .string(value)
        case .integer(let value): .number(Double(value))
        }
    }
}

private struct MCPTestEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        .say(userMessage)
    }
}

private actor MCPTestScriptedLLM: LLMClient {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        actions.isEmpty ? .say("No scripted action remains.") : actions.removeFirst()
    }
}

private actor MCPTestBlockingLLM: LLMClient {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        try await Task.sleep(for: .seconds(30))
        return .say("Unexpected completion")
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in waiters.append(continuation) }
    }
}

private enum MCPServerTestError: Error {
    case timeout
}
