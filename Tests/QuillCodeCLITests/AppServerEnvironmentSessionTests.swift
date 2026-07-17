import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerEnvironmentSessionTests: XCTestCase {
    func testEnvironmentAddInfoAndUnknownIDUseCodexCompatibleRPCShapes() async throws {
        let client = AppServerFakeExecServerClient(info: remoteInfo)
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "environment/add",
            params: [
                "environmentId": "remote",
                "execServerUrl": "ws://remote.example",
                "connectTimeoutMs": 2_000
            ],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "environment/info",
            params: ["environmentId": "remote"],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "environment/info",
            params: ["environmentId": "missing"],
            to: fixture.session
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 2, in: records), [:])
        let info = try XCTUnwrap(result(for: 3, in: records))
        XCTAssertEqual(info["cwd"]?.stringValue, "file:///workspace")
        XCTAssertEqual(info["shell"]?.objectValue?["name"]?.stringValue, "zsh")
        XCTAssertEqual(errorCode(for: 4, in: records), -32_600)
        XCTAssertEqual(errorMessage(for: 4, in: records), "unknown environment id `missing`")
        await registry.closeAll()
    }

    func testThreadEnvironmentSelectionPersistsAndEmptyArrayDisablesAccess() async throws {
        let client = AppServerFakeExecServerClient(info: remoteInfo)
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        _ = try await registry.add(registration(id: "remote"))
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: threadParameters(environments: [[
                "environmentId": "remote",
                "cwd": "/workspace"
            ]], workspace: fixture.workspace),
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        let id = try XCTUnwrap(UUID(uuidString: threadID))
        let repository = await fixture.session.repository
        var stored = try await repository.load(id)
        XCTAssertEqual(stored.settings.environments, [
            .init(environmentID: "remote", cwd: "/workspace")
        ])

        try await sendRequest(
            id: 3,
            method: "thread/resume",
            params: ["threadId": threadID],
            to: fixture.session
        )
        stored = try await repository.load(id)
        XCTAssertEqual(stored.settings.environments?.first?.environmentID, "remote")

        try await sendRequest(
            id: 4,
            method: "thread/resume",
            params: ["threadId": threadID, "environments": []],
            to: fixture.session
        )
        stored = try await repository.load(id)
        XCTAssertEqual(stored.settings.environments, [])

        try await sendRequest(
            id: 5,
            method: "thread/start",
            params: threadParameters(environments: [[
                "environmentId": "missing",
                "cwd": "/workspace"
            ]], workspace: fixture.workspace),
            to: fixture.session
        )
        try await sendRequest(
            id: 6,
            method: "thread/start",
            params: threadParameters(environments: [[
                "environmentId": "remote"
            ]], workspace: fixture.workspace),
            to: fixture.session
        )
        records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 5, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 5, in: records)?.contains("unknown turn environment") == true)
        XCTAssertEqual(errorCode(for: 6, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 6, in: records)?.contains("missing field `cwd`") == true)
        await registry.closeAll()
    }

    func testSelectedRemoteEnvironmentRoutesAgentToolAndKeepsContextTransient() async throws {
        let client = AppServerFakeExecServerClient(
            info: remoteInfo,
            processResults: [
                .init(
                    stdout: "quill\n",
                    stderr: "",
                    exitCode: 0,
                    failure: nil,
                    sandboxDenied: false
                )
            ]
        )
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        _ = try await registry.add(registration(id: "remote"))
        let llm = EnvironmentScriptedLLM(actions: [
            .tool(ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: #"{"cmd":"whoami"}"#
            )),
            .say("Remote command completed.")
        ])
        let fixture = try makeSession(llm: llm, registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace,
                sandbox: "danger-full-access",
                approvalPolicy: "never"
            ),
            to: fixture.session
        )
        let records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": "Run whoami", "text_elements": []]]
            ],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.processRequests.count, 1)
        XCTAssertEqual(snapshot.processRequests.first?.argv, ["/bin/zsh", "-lc", "whoami"])
        let observations = await llm.observations()
        let first = try XCTUnwrap(observations.first)
        XCTAssertTrue(first.toolNames.contains(ToolDefinition.shellRun.name))
        XCTAssertTrue(first.toolNames.contains(ToolDefinition.fileRead.name))
        XCTAssertFalse(first.toolNames.contains(ToolDefinition.gitStatus.name))
        let contextIndex = try XCTUnwrap(first.messages.firstIndex { message in
            message.role == .system
                && message.content.contains("<environment_id>remote</environment_id>")
                && message.content.contains("<cwd>/workspace</cwd>")
        })
        let userIndex = try XCTUnwrap(first.messages.lastIndex { message in
            message.role == .user && message.content == "Run whoami"
        })
        XCTAssertLessThan(contextIndex, userIndex)
        XCTAssertEqual(first.messages.last?.role, .user)

        let repository = await fixture.session.repository
        let stored = try await repository.load(try XCTUnwrap(UUID(uuidString: threadID)))
        XCTAssertFalse(stored.thread.messages.contains { message in
            message.content.contains("<environment_id>remote</environment_id>")
        })
        XCTAssertEqual(
            stored.thread.messages.filter { $0.role == .assistant }.last?.content,
            "Remote command completed."
        )
        await registry.closeAll()
    }

    func testDirectUserShellUsesSelectedRemoteEnvironment() async throws {
        let client = AppServerFakeExecServerClient(
            info: remoteInfo,
            processResults: [
                .init(
                    stdout: "quill\n",
                    stderr: "",
                    exitCode: 0,
                    failure: nil,
                    sandboxDenied: false
                )
            ]
        )
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        _ = try await registry.add(registration(id: "remote"))
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await sendRequest(
            id: 3,
            method: "thread/shellCommand",
            params: ["threadId": threadID, "command": "whoami"],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.processRequests.count, 1)
        XCTAssertEqual(snapshot.processRequests.first?.argv, ["/bin/zsh", "-lc", "whoami"])
        XCTAssertEqual(snapshot.processRequests.first?.cwdURI, "file:///workspace")
        XCTAssertEqual(snapshot.processRequests.first?.timeoutSeconds, 60 * 60)
        records = try await fixture.output.records()
        XCTAssertEqual(result(for: 3, in: records), [:])
        let completedItem = records.first {
            $0["method"]?.stringValue == "item/completed"
        }?["params"]?.objectValue?["item"]?.objectValue
        XCTAssertEqual(completedItem?["status"]?.stringValue, "completed")
        XCTAssertEqual(completedItem?["aggregatedOutput"]?.stringValue, "quill\n")

        let repository = await fixture.session.repository
        let stored = try await repository.load(try XCTUnwrap(UUID(uuidString: threadID)))
        XCTAssertTrue(stored.thread.messages.contains {
            $0.role == .tool && $0.content.contains("quill") && $0.content.contains("whoami")
        })
        await registry.closeAll()
    }

    func testConcurrentRemoteShellLookupsCommitToOneStandaloneTurn() async throws {
        let client = AppServerFakeExecServerClient(
            info: remoteInfo,
            infoDelay: .milliseconds(50),
            processDelay: .milliseconds(250),
            processResults: [
                .init(
                    stdout: "first\n",
                    stderr: "",
                    exitCode: 0,
                    failure: nil,
                    sandboxDenied: false
                ),
                .init(
                    stdout: "second\n",
                    stderr: "",
                    exitCode: 0,
                    failure: nil,
                    sandboxDenied: false
                )
            ]
        )
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        _ = try await registry.add(registration(id: "remote"))
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )
        let initialRecords = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: initialRecords)?["thread"]?.objectValue?["id"]?.stringValue
        )
        let baseline = initialRecords.count
        let firstRequest = try JSONSerialization.data(withJSONObject: [
            "id": 3,
            "method": "thread/shellCommand",
            "params": ["threadId": threadID, "command": "printf first"]
        ], options: [.sortedKeys])
        let secondRequest = try JSONSerialization.data(withJSONObject: [
            "id": 4,
            "method": "thread/shellCommand",
            "params": ["threadId": threadID, "command": "printf second"]
        ], options: [.sortedKeys])

        async let firstReceive: Void = fixture.session.receive(firstRequest)
        async let secondReceive: Void = fixture.session.receive(secondRequest)
        _ = await (firstReceive, secondReceive)
        await fixture.session.waitForActiveTurns()

        let records = Array(try await fixture.output.records().dropFirst(baseline))
        XCTAssertEqual(result(for: 3, in: records), [:])
        XCTAssertEqual(result(for: 4, in: records), [:])
        XCTAssertEqual(records.filter { $0["method"]?.stringValue == "turn/started" }.count, 1)
        XCTAssertEqual(records.filter { $0["method"]?.stringValue == "turn/completed" }.count, 1)
        let itemStarts = records.filter { $0["method"]?.stringValue == "item/started" }
        XCTAssertEqual(itemStarts.count, 2)
        XCTAssertEqual(Set(itemStarts.compactMap {
            $0["params"]?.objectValue?["turnId"]?.stringValue
        }).count, 1)
        let clientSnapshot = await client.snapshot()
        XCTAssertEqual(clientSnapshot.processRequests.count, 2)
        await registry.closeAll()
    }

    func testDirectUserShellRejectsDisabledEnvironmentWithoutDispatch() async throws {
        let client = AppServerFakeExecServerClient(info: remoteInfo)
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: threadParameters(environments: [], workspace: fixture.workspace),
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await sendRequest(
            id: 3,
            method: "thread/shellCommand",
            params: ["threadId": threadID, "command": "whoami"],
            to: fixture.session
        )

        records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 3, in: records), -32_600)
        XCTAssertEqual(
            errorMessage(for: 3, in: records),
            "environment access is disabled for this thread"
        )
        let snapshot = await client.snapshot()
        XCTAssertTrue(snapshot.processRequests.isEmpty)
        XCTAssertFalse(records.contains { record in
            record["method"]?.stringValue == "item/started"
        })
        await registry.closeAll()
    }

    func testTurnLevelEmptyEnvironmentSelectionRemovesHostToolsAndStaysSticky() async throws {
        let client = AppServerFakeExecServerClient(info: remoteInfo)
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        _ = try await registry.add(registration(id: "remote"))
        let llm = EnvironmentScriptedLLM(actions: [.say("No host access.")])
        let fixture = try makeSession(llm: llm, registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )
        let records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "environments": [],
                "input": [["type": "text", "text": "Inspect nothing", "text_elements": []]]
            ],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        let observations = await llm.observations()
        let observation = try XCTUnwrap(observations.first)
        XCTAssertEqual(observation.toolNames, Set([ToolDefinition.webSearch.name]))
        XCTAssertTrue(observation.messages.contains { message in
            message.role == .system
                && message.content.contains("<environment_access>disabled</environment_access>")
        })
        let repository = await fixture.session.repository
        let stored = try await repository.load(try XCTUnwrap(UUID(uuidString: threadID)))
        XCTAssertEqual(stored.settings.environments, [])
        XCTAssertFalse(stored.thread.messages.contains { message in
            message.content.contains("<environment_access>disabled</environment_access>")
        })
        await registry.closeAll()
    }

    func testStatusAndSelectedThreadConnectionLifecycleMatchCodexSemantics() async throws {
        let client = AppServerFakeExecServerClient(
            info: remoteInfo,
            connectDelay: .milliseconds(300)
        )
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "environment/add",
            params: [
                "environmentId": "remote",
                "execServerUrl": "ws://remote.example"
            ],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "environment/status",
            params: ["environmentId": "remote"],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )

        var records = try await fixture.output.records()
        XCTAssertEqual(result(for: 3, in: records)?["status"]?.stringValue, "pending")
        let firstThreadID = try XCTUnwrap(
            result(for: 4, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await waitUntil {
            let records = try? await fixture.output.records()
            return records?.filter {
                $0["method"]?.stringValue == "thread/environment/connected"
            }.count == 1
        }

        try await sendRequest(
            id: 5,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )
        records = try await fixture.output.records()
        let secondThreadID = try XCTUnwrap(
            result(for: 5, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await Task.sleep(for: .milliseconds(40))
        records = try await fixture.output.records()
        XCTAssertEqual(
            records.filter { $0["method"]?.stringValue == "thread/environment/connected" }.count,
            1,
            "Selecting an already-ready environment must not replay connected state."
        )

        await client.setConnectionSnapshot(.disconnected("peer closed"))
        try await waitUntil {
            let records = try? await fixture.output.records()
            return records?.filter {
                $0["method"]?.stringValue == "thread/environment/disconnected"
            }.count == 2
        }
        records = try await fixture.output.records()
        let disconnectedThreadIDs = Set(records.compactMap { record -> String? in
            guard record["method"]?.stringValue == "thread/environment/disconnected" else {
                return nil
            }
            return record["params"]?.objectValue?["threadId"]?.stringValue
        })
        XCTAssertEqual(disconnectedThreadIDs, Set([firstThreadID, secondThreadID]))

        try await sendRequest(
            id: 6,
            method: "environment/status",
            params: ["environmentId": "missing"],
            to: fixture.session
        )
        records = try await fixture.output.records()
        XCTAssertEqual(result(for: 6, in: records)?["status"]?.stringValue, "unknown")
        XCTAssertEqual(
            result(for: 6, in: records)?["error"]?.stringValue,
            "unknown environment id `missing`"
        )

        await fixture.session.finishInput()
        await registry.closeAll()
    }

    func testSelectionChangesAndThreadDeletionRemoveLifecycleSubscriptions() async throws {
        let client = AppServerFakeExecServerClient(
            info: remoteInfo,
            connectDelay: .milliseconds(150)
        )
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)
        _ = try await registry.add(registration(id: "remote"))

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let firstThreadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await sendRequest(
            id: 3,
            method: "thread/resume",
            params: ["threadId": firstThreadID, "environments": []],
            to: fixture.session
        )
        try await Task.sleep(for: .milliseconds(220))
        records = try await fixture.output.records()
        XCTAssertFalse(records.contains {
            $0["method"]?.stringValue == "thread/environment/connected"
        })

        try await sendRequest(
            id: 4,
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )
        records = try await fixture.output.records()
        let secondThreadID = try XCTUnwrap(
            result(for: 4, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await sendRequest(
            id: 5,
            method: "thread/delete",
            params: ["threadId": secondThreadID],
            to: fixture.session
        )
        await client.setConnectionSnapshot(.disconnected("peer closed"))
        try await Task.sleep(for: .milliseconds(40))
        records = try await fixture.output.records()
        XCTAssertFalse(records.contains {
            $0["method"]?.stringValue == "thread/environment/disconnected"
        })

        await fixture.session.finishInput()
        await registry.closeAll()
    }

    func testReplacingImplicitLocalEnvironmentNotifiesDefaultSelectedThread() async throws {
        let client = AppServerFakeExecServerClient(
            info: remoteInfo,
            connectDelay: .milliseconds(80)
        )
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: [
                "cwd": fixture.workspace.path,
                "model": "trustedrouter/fast",
                "sandbox": "read-only"
            ],
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await sendRequest(
            id: 3,
            method: "environment/add",
            params: [
                "environmentId": "local",
                "execServerUrl": "ws://remote.example"
            ],
            to: fixture.session
        )
        try await waitUntil {
            let records = try? await fixture.output.records()
            return records?.contains { record in
                record["method"]?.stringValue == "thread/environment/connected"
                    && record["params"]?.objectValue?["threadId"]?.stringValue == threadID
                    && record["params"]?.objectValue?["environmentId"]?.stringValue == "local"
            } == true
        }
        records = try await fixture.output.records()
        XCTAssertEqual(result(for: 3, in: records), [:])

        await fixture.session.finishInput()
        await registry.closeAll()
    }

    private var remoteInfo: AppServerEnvironmentInfo {
        .init(
            shell: .init(name: "zsh", path: "/bin/zsh"),
            cwd: "file:///workspace"
        )
    }

    private func makeRegistry(
        factory: AppServerFakeExecServerFactory
    ) -> AppServerEnvironmentRegistry {
        AppServerEnvironmentRegistry(
            localCWD: URL(fileURLWithPath: "/tmp"),
            environment: [:],
            monitorInterval: .milliseconds(5),
            clientFactory: { factory.make(websocketURL: $0, connectTimeout: $1) }
        )
    }

    private func registration(id: String) -> CLIJSONValue {
        .object([
            "environmentId": .string(id),
            "execServerUrl": .string("ws://remote.example")
        ])
    }

    private func threadParameters(
        environments: [[String: Any]],
        workspace: URL,
        sandbox: String = "read-only",
        approvalPolicy: String? = nil
    ) -> [String: Any] {
        var parameters: [String: Any] = [
            "cwd": workspace.path,
            "model": "trustedrouter/fast",
            "sandbox": sandbox,
            "environments": environments
        ]
        if let approvalPolicy { parameters["approvalPolicy"] = approvalPolicy }
        return parameters
    }

    private func makeSession(
        llm: any LLMClient,
        registry: AppServerEnvironmentRegistry
    ) throws -> EnvironmentSessionFixture {
        let home = try temporaryDirectory(prefix: "environment-home")
        let workspace = try temporaryDirectory(prefix: "environment-workspace")
        let output = EnvironmentSessionOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: llm,
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps,
                    enablesImmediateActionPreflight: false,
                    compaction: AgentCompactionPolicy(compactor: ThreadCompactor())
                )
            },
            environmentRegistry: registry,
            sink: { line in await output.append(line) }
        )
        return .init(session: session, output: output, workspace: workspace)
    }

    private func initialize(_ session: AppServerSession) async throws {
        try await sendRequest(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "EnvironmentTests", "version": "1"]],
            to: session
        )
        try await sendNotification(method: "initialized", params: [:], to: session)
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

    private func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func errorCode(for id: Int, in records: [[String: CLIJSONValue]]) -> Double? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?
            .objectValue?["code"]?.numberValue
    }

    private func errorMessage(for id: Int, in records: [[String: CLIJSONValue]]) -> String? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?
            .objectValue?["message"]?.stringValue
    }

    private func waitUntil(
        _ condition: @escaping () async -> Bool
    ) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for environment lifecycle notification")
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "quillcode-\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct EnvironmentSessionFixture {
    var session: AppServerSession
    var output: EnvironmentSessionOutputCollector
    var workspace: URL
}

private actor EnvironmentSessionOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let value = try CLIJSONCodec.decode(line).objectValue else {
                throw EnvironmentSessionTestError.invalidRecord
            }
            return value
        }
    }
}

private struct EnvironmentEchoLLM: LLMClient {
    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) -> AgentAction {
        .say(userMessage)
    }
}

private actor EnvironmentScriptedLLM: LLMClient {
    struct Observation: Sendable {
        var messages: [ChatMessage]
        var toolNames: Set<String>
    }

    private var actions: [AgentAction]
    private var captured: [Observation] = []

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) -> AgentAction {
        captured.append(.init(messages: thread.messages, toolNames: Set(tools.map(\.name))))
        guard !actions.isEmpty else { return .say("No scripted action remains.") }
        return actions.removeFirst()
    }

    func observations() -> [Observation] {
        captured
    }
}

private enum EnvironmentSessionTestError: Error {
    case invalidRecord
}
