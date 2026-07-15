import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerSessionTests: XCTestCase {
    func testHandshakeRequiresInitializedNotification() async throws {
        let fixture = try await makeSession(llm: AppServerEchoLLM())

        try await sendRequest(id: 1, method: "thread/list", params: [:], to: fixture.session)
        try await initialize(fixture.session)
        try await sendRequest(id: 2, method: "thread/list", params: [:], to: fixture.session)
        try await sendNotification(method: "initialized", params: [:], to: fixture.session)
        try await sendRequest(id: 3, method: "thread/list", params: [:], to: fixture.session)

        let records = try await fixture.output.records()
        XCTAssertEqual(errorMessage(for: 1, in: records), "Not initialized")
        XCTAssertEqual(errorMessage(for: 2, in: records), "Not initialized")
        XCTAssertNotNil(result(for: 3, in: records))
        let initializeResult = try XCTUnwrap(result(for: 100, in: records))
        XCTAssertNotNil(initializeResult["userAgent"])
        XCTAssertEqual(initializeResult["codexHome"]?.stringValue, fixture.home.path)
    }

    func testMalformedJSONAndInvalidEnvelopeReturnDistinctProtocolErrors() async throws {
        let fixture = try await makeSession(llm: AppServerEchoLLM())

        await fixture.session.receive(Data("{".utf8))
        await fixture.session.receive(Data(#"{"id":1}"#.utf8))

        let records = try await fixture.output.records()
        XCTAssertEqual(records[0]["error"]?.objectValue?["code"]?.numberValue, -32_700)
        XCTAssertEqual(records[1]["error"]?.objectValue?["code"]?.numberValue, -32_600)
    }

    func testGranularApprovalPolicyAndGuardianReviewerRoundTripExactly() async throws {
        let fixture = try await makeSession(llm: AppServerEchoLLM())
        try await initialize(fixture.session)
        try await sendNotification(method: "initialized", params: [:], to: fixture.session)
        let granular: [String: Any] = [
            "sandbox_approval": true,
            "rules": false,
            "skill_approval": true,
            "request_permissions": false,
            "mcp_elicitations": true
        ]
        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: [
                "cwd": fixture.workspace.path,
                "sandbox": "workspace-write",
                "approvalPolicy": ["granular": granular],
                "approvalsReviewer": "guardian_subagent"
            ],
            to: fixture.session
        )

        let records = try await fixture.output.records()
        let response = try XCTUnwrap(result(for: 2, in: records))
        XCTAssertEqual(response["approvalsReviewer"]?.stringValue, "guardian_subagent")
        let policy = try XCTUnwrap(response["approvalPolicy"]?.objectValue?["granular"]?.objectValue)
        XCTAssertEqual(policy["sandbox_approval"]?.boolValue, true)
        XCTAssertEqual(policy["rules"]?.boolValue, false)
        XCTAssertEqual(policy["skill_approval"]?.boolValue, true)
        XCTAssertEqual(policy["request_permissions"]?.boolValue, false)
        XCTAssertEqual(policy["mcp_elicitations"]?.boolValue, true)
    }

    func testThreadListRejectsMalformedEnumsAndHonorsSourceFilter() async throws {
        let fixture = try await makeSession(llm: AppServerEchoLLM())
        try await initialize(fixture.session)
        try await sendNotification(method: "initialized", params: [:], to: fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/list",
            params: ["sortKey": "bogus"],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "thread/list",
            params: ["sortDirection": "sideways"],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "thread/list",
            params: ["modelProviders": [42]],
            to: fixture.session
        )
        try await sendRequest(
            id: 5,
            method: "thread/list",
            params: ["sourceKinds": ["bogus"]],
            to: fixture.session
        )
        try await sendRequest(
            id: 6,
            method: "thread/list",
            params: ["limit": 0],
            to: fixture.session
        )
        try await sendRequest(
            id: 7,
            method: "thread/list",
            params: ["sourceKinds": ["cli"]],
            to: fixture.session
        )
        try await sendRequest(
            id: 8,
            method: "thread/start",
            params: ["baseInstructions": 42],
            to: fixture.session
        )
        try await sendRequest(
            id: 9,
            method: "thread/start",
            params: ["modelProvider": "openai"],
            to: fixture.session
        )
        try await sendRequest(
            id: 10,
            method: "thread/start",
            params: ["model": "   "],
            to: fixture.session
        )
        try await sendRequest(
            id: 11,
            method: "thread/start",
            params: ["serviceTier": "priority"],
            to: fixture.session
        )

        let records = try await fixture.output.records()
        for id in 2...6 {
            XCTAssertEqual(errorCode(for: id, in: records), -32_602)
        }
        XCTAssertEqual(result(for: 7, in: records)?["data"]?.arrayValue, [])
        XCTAssertEqual(errorCode(for: 8, in: records), -32_602)
        XCTAssertEqual(errorCode(for: 9, in: records), -32_602)
        XCTAssertEqual(errorCode(for: 10, in: records), -32_602)
        XCTAssertEqual(errorCode(for: 11, in: records), -32_602)
    }

    func testTurnStreamsCodexLifecycleAndPersistsTranscript() async throws {
        let llm = AppServerStreamingLLM(chunks: [
            #"{"type":"say","text":""#,
            "hel",
            "lo",
            #""}"#
        ])
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(in: fixture)

        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "clientUserMessageId": "client-message-1",
                "input": [["type": "text", "text": "Say hello", "text_elements": []]]
            ],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let records = try await fixture.output.records()
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 3 })
        let activeIndex = try XCTUnwrap(records.firstIndex {
            $0["method"]?.stringValue == "thread/status/changed"
        })
        XCTAssertLessThan(responseIndex, activeIndex, "turn/start must respond before streaming notifications")

        let methods = records.compactMap { $0["method"]?.stringValue }
        XCTAssertTrue(methods.contains("turn/started"))
        XCTAssertTrue(methods.contains("item/started"))
        XCTAssertTrue(methods.contains("item/completed"))
        XCTAssertTrue(methods.contains("item/agentMessage/delta"))
        XCTAssertTrue(methods.contains("turn/completed"))
        XCTAssertEqual(methods.filter { $0 == "thread/status/changed" }.count, 2)

        let deltas = records.compactMap { record -> String? in
            guard record["method"]?.stringValue == "item/agentMessage/delta" else { return nil }
            return record["params"]?.objectValue?["delta"]?.stringValue
        }
        XCTAssertEqual(deltas.joined(), "hello")

        let completion = try XCTUnwrap(records.last { $0["method"]?.stringValue == "turn/completed" })
        let turn = try XCTUnwrap(completion["params"]?.objectValue?["turn"]?.objectValue)
        XCTAssertEqual(turn["status"]?.stringValue, "completed")
        let items = try XCTUnwrap(turn["items"]?.arrayValue?.compactMap(\.objectValue))
        XCTAssertEqual(items.compactMap { $0["type"]?.stringValue }, ["userMessage", "agentMessage"])
        XCTAssertEqual(items.first?["clientId"]?.stringValue, "client-message-1")

        let stored = try XCTUnwrap(
            JSONThreadStore(directory: fixture.home.appendingPathComponent("threads")).list().first
        )
        XCTAssertEqual(stored.id.uuidString.lowercased(), threadID)
        XCTAssertEqual(stored.messages.filter { $0.role == .user }.map(\.content), ["Say hello"])
        XCTAssertEqual(stored.messages.filter { $0.role == .assistant }.map(\.content), ["hello"])
    }

    func testLocalImageInputIsCopiedIntoManagedAttachmentStorage() async throws {
        let fixture = try await makeSession(llm: AppServerEchoLLM())
        let source = fixture.workspace.appendingPathComponent("sample.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: source)
        let threadID = try await startThread(in: fixture)

        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [
                    ["type": "text", "text": ""],
                    ["type": "localImage", "path": source.path]
                ]
            ],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let stored = try XCTUnwrap(
            JSONThreadStore(directory: fixture.home.appendingPathComponent("threads")).list().first
        )
        let attachment = try XCTUnwrap(stored.messages.first(where: { $0.role == .user })?.attachments.first)
        XCTAssertEqual(attachment.displayName, "sample.png")
        XCTAssertNotEqual(attachment.localURL, source)
        XCTAssertTrue(attachment.localURL.path.hasPrefix(
            fixture.home.appendingPathComponent("attachments").path + "/"
        ))
        XCTAssertEqual(try Data(contentsOf: attachment.localURL), try Data(contentsOf: source))
    }

    func testSteerQueuesInputInsideActiveTurn() async throws {
        let llm = AppServerSteerableLLM()
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(in: fixture)
        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: ["threadId": threadID, "input": [["type": "text", "text": "first"]]],
            to: fixture.session
        )
        await llm.waitUntilStarted()
        let recordsAfterStart = try await fixture.output.records()
        let turnID = try responseTurnID(id: 3, records: recordsAfterStart)

        try await sendRequest(
            id: 4,
            method: "turn/steer",
            params: [
                "threadId": threadID,
                "expectedTurnId": turnID,
                "input": [["type": "text", "text": "second"]]
            ],
            to: fixture.session
        )
        await llm.releaseFirstAction()
        await fixture.session.waitForActiveTurns()

        let prompts = await llm.receivedPrompts()
        XCTAssertEqual(prompts, ["first", "second"])
        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 4, in: records)?["turnId"]?.stringValue, turnID)
        let completion = try XCTUnwrap(records.last { $0["method"]?.stringValue == "turn/completed" })
        let items = try XCTUnwrap(
            completion["params"]?.objectValue?["turn"]?.objectValue?["items"]?.arrayValue?
                .compactMap(\.objectValue)
        )
        XCTAssertEqual(items.filter { $0["type"]?.stringValue == "userMessage" }.count, 2)
        XCTAssertEqual(items.filter { $0["type"]?.stringValue == "agentMessage" }.count, 2)
    }

    func testInterruptCancelsActiveTurnAndReportsInterruptedCompletion() async throws {
        let llm = AppServerBlockingLLM()
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(in: fixture)
        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: ["threadId": threadID, "input": [["type": "text", "text": "wait"]]],
            to: fixture.session
        )
        await llm.waitUntilStarted()
        let turnID = try responseTurnID(id: 3, records: await fixture.output.records())
        try await sendRequest(
            id: 4,
            method: "turn/interrupt",
            params: ["threadId": threadID, "turnId": turnID],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let records = try await fixture.output.records()
        XCTAssertNotNil(result(for: 4, in: records))
        let completion = try XCTUnwrap(records.last { $0["method"]?.stringValue == "turn/completed" })
        let turn = try XCTUnwrap(completion["params"]?.objectValue?["turn"]?.objectValue)
        XCTAssertEqual(turn["status"]?.stringValue, "interrupted")
    }

    func testShellToolProjectsCommandExecutionAndOutput() async throws {
        let llm = AppServerScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: #"{"cmd":"printf app-server-tool"}"#
            )),
            .say("Command completed.")
        ])
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(in: fixture, sandbox: "workspace-write")
        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: ["threadId": threadID, "input": [["type": "text", "text": "run the command"]]],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let records = try await fixture.output.records()
        let completion = try XCTUnwrap(records.last { $0["method"]?.stringValue == "turn/completed" })
        let items = try XCTUnwrap(
            completion["params"]?.objectValue?["turn"]?.objectValue?["items"]?.arrayValue?
                .compactMap(\.objectValue)
        )
        let command = try XCTUnwrap(items.first { $0["type"]?.stringValue == "commandExecution" })
        XCTAssertEqual(command["command"]?.stringValue, "printf app-server-tool")
        XCTAssertEqual(command["status"]?.stringValue, "completed")
        XCTAssertEqual(command["aggregatedOutput"]?.stringValue, "app-server-tool")
        XCTAssertEqual(command["exitCode"]?.numberValue, 0)
        let output = records.compactMap { record -> String? in
            guard record["method"]?.stringValue == "item/commandExecution/outputDelta" else { return nil }
            return record["params"]?.objectValue?["delta"]?.stringValue
        }.joined()
        XCTAssertEqual(output, "app-server-tool")
    }

    func testDangerFullAccessRoundTripsWithDedicatedPermissionProfile() async throws {
        let outside = try temporaryDirectory(prefix: "app-server-full-access")
        let externalFile = outside.appendingPathComponent("external.txt")
        try "app-server-full-access-proof\n".write(
            to: externalFile,
            atomically: true,
            encoding: .utf8
        )
        let fixture = try await makeSession(llm: AppServerScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": externalFile.path])
            )),
            .say("External file inspected.")
        ]))
        let threadID = try await startThread(in: fixture, sandbox: "danger-full-access")

        let records = try await fixture.output.records()
        let response = try XCTUnwrap(result(for: 2, in: records))
        XCTAssertEqual(response["sandbox"]?.objectValue?["type"]?.stringValue, "dangerFullAccess")
        XCTAssertEqual(
            response["activePermissionProfile"]?.objectValue?["id"]?.stringValue,
            ":danger-full-access"
        )

        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": "read the external file"]]
            ],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let stored = try JSONThreadStore(
            directory: fixture.home.appendingPathComponent("threads")
        ).load(try XCTUnwrap(UUID(uuidString: threadID)))
        XCTAssertTrue(stored.messages.contains { message in
            message.role == .tool && message.content.contains("app-server-full-access-proof")
        })
    }

    func testReviewModeRoundTripsCommandApprovalBeforeExecution() async throws {
        let llm = AppServerScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: #"{"cmd":"printf approved-command"}"#
            )),
            .say("Approved command completed.")
        ])
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(
            in: fixture,
            sandbox: "workspace-write",
            approvalsReviewer: "user"
        )
        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: ["threadId": threadID, "input": [["type": "text", "text": "run it"]]],
            to: fixture.session
        )

        let approval = try await waitForRecord(
            method: "item/commandExecution/requestApproval",
            in: fixture.output
        )
        let approvalID = try XCTUnwrap(approval["id"]?.stringValue)
        let params = try XCTUnwrap(approval["params"]?.objectValue)
        XCTAssertEqual(params["threadId"]?.stringValue, threadID)
        XCTAssertEqual(params["command"]?.stringValue, "printf approved-command")
        XCTAssertEqual(params["cwd"]?.stringValue, fixture.workspace.path)

        try await send(
            ["id": approvalID, "result": ["decision": "accept"]],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let records = try await fixture.output.records()
        let completion = try XCTUnwrap(records.last { $0["method"]?.stringValue == "turn/completed" })
        let items = try XCTUnwrap(
            completion["params"]?.objectValue?["turn"]?.objectValue?["items"]?.arrayValue?
                .compactMap(\.objectValue)
        )
        let command = try XCTUnwrap(items.first { $0["type"]?.stringValue == "commandExecution" })
        XCTAssertEqual(command["status"]?.stringValue, "completed")
        XCTAssertEqual(command["aggregatedOutput"]?.stringValue, "approved-command")
    }

    func testClientEOFResolvesApprovalWithoutExecutingTheCommand() async throws {
        let forbidden = "should-not-exist"
        let llm = AppServerScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: #"{"cmd":"touch should-not-exist"}"#
            )),
            .say("The command was not run.")
        ])
        let fixture = try await makeSession(llm: llm)
        let threadID = try await startThread(
            in: fixture,
            sandbox: "workspace-write",
            approvalsReviewer: "user"
        )
        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: ["threadId": threadID, "input": [["type": "text", "text": "run it"]]],
            to: fixture.session
        )
        await fixture.session.finishInput()
        await fixture.session.waitForActiveTurns()

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.workspace.appendingPathComponent(forbidden).path
        ))
        let records = try await fixture.output.records()
        let completion = try XCTUnwrap(records.last { $0["method"]?.stringValue == "turn/completed" })
        XCTAssertEqual(
            completion["params"]?.objectValue?["turn"]?.objectValue?["status"]?.stringValue,
            "completed"
        )
    }

    func testThreadLifecycleForkArchiveNameAndGoalRemainConsistent() async throws {
        let fixture = try await makeSession(llm: AppServerEchoLLM())
        let threadID = try await startThread(in: fixture)
        try await sendRequest(
            id: 3,
            method: "thread/name/set",
            params: ["threadId": threadID, "name": "Protocol work"],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "thread/goal/set",
            params: ["threadId": threadID, "objective": "Finish app-server parity", "status": "active"],
            to: fixture.session
        )
        try await sendRequest(
            id: 5,
            method: "thread/fork",
            params: ["threadId": threadID],
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let forkID = try XCTUnwrap(
            result(for: 5, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        let fork = try XCTUnwrap(result(for: 5, in: records)?["thread"]?.objectValue)
        XCTAssertNotEqual(forkID, threadID)
        XCTAssertEqual(fork["sessionId"]?.stringValue, threadID)
        XCTAssertEqual(fork["forkedFromId"]?.stringValue, threadID)
        XCTAssertEqual(fork["parentThreadId"], .null)

        try await sendRequest(
            id: 6,
            method: "thread/archive",
            params: ["threadId": threadID],
            to: fixture.session
        )
        try await sendRequest(
            id: 7,
            method: "thread/list",
            params: ["archived": true],
            to: fixture.session
        )
        try await sendRequest(
            id: 8,
            method: "thread/goal/get",
            params: ["threadId": threadID],
            to: fixture.session
        )
        try await sendRequest(
            id: 9,
            method: "thread/unarchive",
            params: ["threadId": threadID],
            to: fixture.session
        )
        try await sendRequest(
            id: 10,
            method: "thread/delete",
            params: ["threadId": forkID],
            to: fixture.session
        )

        records = try await fixture.output.records()
        let archived = try XCTUnwrap(result(for: 7, in: records)?["data"]?.arrayValue)
        XCTAssertEqual(archived.compactMap { $0.objectValue?["id"]?.stringValue }, [threadID])
        let goal = try XCTUnwrap(result(for: 8, in: records)?["goal"]?.objectValue)
        XCTAssertEqual(goal["objective"]?.stringValue, "Finish app-server parity")
        XCTAssertEqual(goal["status"]?.stringValue, "active")
        XCTAssertNotNil(result(for: 10, in: records))

        try await sendRequest(
            id: 11,
            method: "thread/read",
            params: ["threadId": threadID],
            to: fixture.session
        )
        records = try await fixture.output.records()
        let thread = try XCTUnwrap(result(for: 11, in: records)?["thread"]?.objectValue)
        XCTAssertEqual(thread["name"]?.stringValue, "Protocol work")
        XCTAssertEqual(thread["status"]?.objectValue?["type"]?.stringValue, "idle")
    }

    private func makeSession(llm: any LLMClient) async throws -> AppServerFixture {
        let home = try temporaryDirectory(prefix: "app-server-home")
        let workspace = try temporaryDirectory(prefix: "app-server-workspace")
        let output = AppServerOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: false
                )
            },
            sink: { line in await output.append(line) }
        )
        return AppServerFixture(session: session, output: output, home: home, workspace: workspace)
    }

    private func startThread(
        in fixture: AppServerFixture,
        sandbox: String = "read-only",
        approvalsReviewer: String? = nil
    ) async throws -> String {
        try await initialize(fixture.session)
        try await sendNotification(method: "initialized", params: [:], to: fixture.session)
        var params: [String: Any] = [
            "cwd": fixture.workspace.path,
            "model": "trustedrouter/fast",
            "sandbox": sandbox
        ]
        if let approvalsReviewer {
            params["approvalsReviewer"] = approvalsReviewer
        }
        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: params,
            to: fixture.session
        )
        let records = try await fixture.output.records()
        let result = try XCTUnwrap(result(for: 2, in: records))
        let thread = try XCTUnwrap(result["thread"]?.objectValue)
        let threadID = try XCTUnwrap(thread["id"]?.stringValue)
        XCTAssertEqual(thread["sessionId"]?.stringValue, threadID)
        XCTAssertEqual(thread["turns"]?.arrayValue, [])
        let started = try XCTUnwrap(records.first { $0["method"]?.stringValue == "thread/started" })
        XCTAssertEqual(
            started["params"]?.objectValue?["thread"]?.objectValue?["turns"]?.arrayValue,
            []
        )
        return threadID
    }

    private func initialize(_ session: AppServerSession) async throws {
        try await sendRequest(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "QuillCodeTests", "version": "1"]],
            to: session
        )
    }

    private func sendRequest(
        id: Int,
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["id": id, "method": method, "params": params], to: session)
    }

    private func sendNotification(
        method: String,
        params: [String: Any],
        to session: AppServerSession
    ) async throws {
        try await send(["method": method, "params": params], to: session)
    }

    private func send(_ object: [String: Any], to session: AppServerSession) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        await session.receive(data)
    }

    private func result(for id: Int, in records: [[String: CLIJSONValue]]) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func errorMessage(for id: Int, in records: [[String: CLIJSONValue]]) -> String? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["message"]?.stringValue
    }

    private func errorCode(for id: Int, in records: [[String: CLIJSONValue]]) -> Double? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["code"]?.numberValue
    }

    private func responseTurnID(id: Int, records: [[String: CLIJSONValue]]) throws -> String {
        let turn = try XCTUnwrap(result(for: id, in: records)?["turn"]?.objectValue)
        return try XCTUnwrap(turn["id"]?.stringValue)
    }

    private func waitForRecord(
        method: String,
        in output: AppServerOutputCollector
    ) async throws -> [String: CLIJSONValue] {
        for _ in 0..<200 {
            if let record = try await output.records().first(where: {
                $0["method"]?.stringValue == method
            }) {
                return record
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw AppServerTestError.timedOut
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct AppServerFixture {
    var session: AppServerSession
    var output: AppServerOutputCollector
    var home: URL
    var workspace: URL
}

private actor AppServerOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let record = try CLIJSONCodec.decode(line).objectValue else {
                throw AppServerTestError.invalidRecord
            }
            return record
        }
    }
}

private enum AppServerTestError: Error {
    case nonStreamingPathUsed
    case invalidRecord
    case timedOut
}

private struct AppServerEchoLLM: LLMClient {
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .say(userMessage)
    }
}

private actor AppServerScriptedLLM: LLMClient {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        guard !actions.isEmpty else { return .say("No scripted action remains.") }
        return actions.removeFirst()
    }
}

private struct AppServerStreamingLLM: StreamingLLMClient {
    var chunks: [String]

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw AppServerTestError.nonStreamingPathUsed
    }

    func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            chunks.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

private actor AppServerSteerableLLM: LLMClient {
    private var prompts: [String] = []
    private var firstStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        prompts.append(userMessage)
        if prompts.count == 1 {
            firstStarted = true
            startWaiters.forEach { $0.resume() }
            startWaiters.removeAll()
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
            return .say("first answer")
        }
        return .say("second answer")
    }

    func waitUntilStarted() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseFirstAction() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func receivedPrompts() -> [String] { prompts }
}

private actor AppServerBlockingLLM: LLMClient {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        try await Task.sleep(for: .seconds(30))
        return .say("unexpected")
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
