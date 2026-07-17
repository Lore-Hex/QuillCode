import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerEnvironmentSessionTests: AppServerEnvironmentSessionTestCase {
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

    func testEnvironmentAddRejectsUnsupportedWebSocketURLBeforeRegistration() async throws {
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
                "execServerUrl": "https://remote.example/ws"
            ],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "environment/status",
            params: ["environmentId": "remote"],
            to: fixture.session
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 2, in: records), -32_600)
        XCTAssertTrue(
            errorMessage(for: 2, in: records)?.contains("unsupported WebSocket URL") == true
        )
        XCTAssertEqual(result(for: 3, in: records)?["status"]?.stringValue, "unknown")
        XCTAssertTrue(factory.snapshot().isEmpty)
        await registry.closeAll()
    }

    func testEnvironmentStatusUsesCodexCompatibleStatesWithoutUnknownIDError() async throws {
        let client = AppServerFakeExecServerClient()
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        _ = try await registry.add(registration(id: "remote"))
        try await waitUntil { await client.connectionSnapshot() == .ready }
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        try await sendRequest(
            id: 2,
            method: "environment/status",
            params: ["environmentId": "local"],
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
            method: "environment/status",
            params: ["environmentId": "missing"],
            to: fixture.session
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 2, in: records), [
            "error": .null,
            "status": .string("ready")
        ])
        XCTAssertEqual(result(for: 3, in: records), [
            "error": .null,
            "status": .string("ready")
        ])
        XCTAssertEqual(result(for: 4, in: records), [
            "status": .string("unknown"),
            "error": .string("unknown environment id `missing`")
        ])
        XCTAssertNil(errorCode(for: 4, in: records))
        await registry.closeAll()
    }

    func testSelectedThreadsReceiveFutureConnectionTransitionsWithoutReplay() async throws {
        let client = AppServerFakeExecServerClient()
        let factory = AppServerFakeExecServerFactory(clients: [client])
        let registry = makeRegistry(factory: factory)
        _ = try await registry.add(registration(id: "remote"))
        try await waitUntil { await client.connectionSnapshot() == .ready }
        let fixture = try makeSession(llm: EnvironmentEchoLLM(), registry: registry)
        try await initialize(fixture.session)

        for requestID in 2...3 {
            try await sendRequest(
                id: requestID,
                method: "thread/start",
                params: threadParameters(
                    environments: [["environmentId": "remote", "cwd": "/workspace"]],
                    workspace: fixture.workspace
                ),
                to: fixture.session
            )
        }
        var records = try await fixture.output.records()
        let threadIDs = try [2, 3].map { requestID in
            try XCTUnwrap(
                result(for: requestID, in: records)?["thread"]?.objectValue?["id"]?.stringValue
            )
        }
        XCTAssertFalse(records.contains {
            $0["method"]?.stringValue == "thread/environment/connected"
        })

        await client.emitConnectionState(.disconnected)
        try await waitUntil {
            let output = try? await fixture.output.records()
            return output?.filter {
                $0["method"]?.stringValue == "thread/environment/disconnected"
            }.count == 2
        }
        records = try await fixture.output.records()
        let disconnected = records.filter {
            $0["method"]?.stringValue == "thread/environment/disconnected"
        }
        XCTAssertEqual(
            Set(disconnected.compactMap {
                $0["params"]?.objectValue?["threadId"]?.stringValue
            }),
            Set(threadIDs)
        )
        XCTAssertTrue(disconnected.allSatisfy {
            $0["params"]?.objectValue?["environmentId"] == .string("remote")
        })

        try await sendRequest(
            id: 4,
            method: "thread/unsubscribe",
            params: ["threadId": threadIDs[1]],
            to: fixture.session
        )
        await client.emitConnectionState(.connected)
        try await waitUntil {
            let output = try? await fixture.output.records()
            return output?.contains {
                $0["method"]?.stringValue == "thread/environment/connected"
            } == true
        }
        records = try await fixture.output.records()
        let connected = records.filter {
            $0["method"]?.stringValue == "thread/environment/connected"
        }
        XCTAssertEqual(connected.count, 1)
        XCTAssertEqual(
            connected.first?["params"]?.objectValue?["threadId"]?.stringValue,
            threadIDs[0]
        )
        await registry.closeAll()
    }

    func testSelectedThreadReceivesInitialConnectionFailureWithoutStatusRecovery() async throws {
        let client = AppServerFakeExecServerClient(
            connectDelay: .milliseconds(75),
            connectError: .disconnected("initial connection failed")
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
            method: "thread/start",
            params: threadParameters(
                environments: [["environmentId": "remote", "cwd": "/workspace"]],
                workspace: fixture.workspace
            ),
            to: fixture.session
        )

        var records = try await fixture.output.records()
        let threadID = try XCTUnwrap(
            result(for: 3, in: records)?["thread"]?.objectValue?["id"]?.stringValue
        )
        try await waitUntil {
            let output = try? await fixture.output.records()
            return output?.contains {
                $0["method"]?.stringValue == "thread/environment/disconnected"
            } == true
        }
        try await sendRequest(
            id: 4,
            method: "environment/status",
            params: ["environmentId": "remote"],
            to: fixture.session
        )

        records = try await fixture.output.records()
        let disconnected = try XCTUnwrap(records.first {
            $0["method"]?.stringValue == "thread/environment/disconnected"
        })
        XCTAssertEqual(disconnected["params"]?.objectValue?["threadId"]?.stringValue, threadID)
        XCTAssertEqual(
            disconnected["params"]?.objectValue?["environmentId"],
            .string("remote")
        )
        XCTAssertFalse(records.contains {
            $0["method"]?.stringValue == "thread/environment/connected"
        })
        let status = try XCTUnwrap(result(for: 4, in: records))
        XCTAssertEqual(status["status"], .string("disconnected"))
        XCTAssertTrue(status["error"]?.stringValue?.contains("initial connection failed") == true)
        let snapshot = await client.snapshot()
        XCTAssertEqual(snapshot.connectCount, 1)
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
        XCTAssertEqual(
            snapshot.processRequests.first?.sandbox,
            try remoteSandbox(.init(mode: .dangerFullAccess))
        )
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
        XCTAssertEqual(
            snapshot.processRequests.first?.sandbox,
            try remoteSandbox(.init(mode: .readOnly))
        )
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

}
