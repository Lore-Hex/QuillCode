import Foundation
@testable import QuillCodeCLI
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import XCTest

final class AppServerMCPTests: XCTestCase {
    func testStatusPreservesExactNamesPayloadsFiltersAndPagination() async throws {
        let launcher = FakeMCPLauncher(specifications: [
            "dash": .init(probe: Self.dashProbe),
            "underscore": .init(probe: Self.underscoreProbe)
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.some-server]
            command = "dash"
            enabled_tools = ["search"]

            [mcp_servers.some_server]
            command = "underscore"
            """,
            launcher: launcher
        )

        try await sendRequest(
            id: 2,
            method: "mcpServerStatus/list",
            params: ["detail": "full", "limit": 1],
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let firstResponse = try XCTUnwrap(result(for: 2, in: records))
        let firstPage = try XCTUnwrap(firstResponse["data"]?.arrayValue)
        let first = try XCTUnwrap(firstPage.first?.objectValue)
        let cursor = try XCTUnwrap(firstResponse["nextCursor"]?.stringValue)

        XCTAssertEqual(firstPage.count, 1)
        XCTAssertEqual(first["name"]?.stringValue, "some-server")
        XCTAssertEqual(first["serverInfo"]?.objectValue?["name"]?.stringValue, "Dash MCP")
        XCTAssertEqual(first["tools"]?.objectValue?.keys.sorted(), ["search"])
        let tools = first["tools"]?.objectValue
        let search = tools?["search"]?.objectValue
        let searchAnnotations = search?["annotations"]?.objectValue
        XCTAssertEqual(searchAnnotations?["readOnlyHint"]?.boolValue, true)
        XCTAssertEqual(first["resources"]?.arrayValue?.first?.objectValue?["uri"]?.stringValue, "docs://guide")
        XCTAssertEqual(
            first["resourceTemplates"]?.arrayValue?.first?.objectValue?["uriTemplate"]?.stringValue,
            "file:///{path}"
        )
        XCTAssertEqual(first["authStatus"]?.stringValue, "unsupported")

        try await sendRequest(
            id: 3,
            method: "mcpServerStatus/list",
            params: ["detail": "full", "limit": 1, "cursor": cursor],
            to: fixture.session
        )
        records = try await fixture.output.records()
        let secondResponse = try XCTUnwrap(result(for: 3, in: records))
        let second = try XCTUnwrap(secondResponse["data"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(second["name"]?.stringValue, "some_server")
        XCTAssertEqual(secondResponse["nextCursor"], .null)
        XCTAssertEqual(launcher.recorder(for: "dash").probeDetails, [.full])
        XCTAssertEqual(launcher.recorder(for: "underscore").probeDetails, [.full])

        await fixture.session.finishInput()
    }

    func testThreadScopedStatusUsesProjectOverridesAndSkipsHeavyInventory() async throws {
        let launcher = FakeMCPLauncher(specifications: [
            "global": .init(probe: Self.namedProbe("Global MCP")),
            "override": .init(probe: Self.namedProbe("Project override")),
            "project": .init(probe: Self.namedProbe("Project MCP"))
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.global-server]
            command = "global"
            """,
            launcher: launcher
        )
        let projectConfig = fixture.workspace.appendingPathComponent(".quillcode/config.toml")
        try FileManager.default.createDirectory(
            at: projectConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        [mcp_servers.global-server]
        command = "override"

        [mcp_servers.project-server]
        command = "project"
        """.utf8).write(to: projectConfig)
        let threadID = try await startThread(in: fixture)

        try await sendRequest(
            id: 3,
            method: "mcpServerStatus/list",
            params: ["threadId": threadID, "detail": "toolsAndAuthOnly"],
            to: fixture.session
        )
        var records = try await fixture.output.records()
        let scoped = try XCTUnwrap(result(for: 3, in: records)?["data"]?.arrayValue)
        let scopedRows = scoped.compactMap(\.objectValue)
        XCTAssertEqual(scopedRows.compactMap { $0["name"]?.stringValue }, ["global-server", "project-server"])
        XCTAssertEqual(scopedRows[0]["serverInfo"]?.objectValue?["name"]?.stringValue, "Project override")
        XCTAssertTrue(scopedRows.allSatisfy { $0["resources"]?.arrayValue?.isEmpty == true })
        XCTAssertTrue(scopedRows.allSatisfy { $0["resourceTemplates"]?.arrayValue?.isEmpty == true })
        XCTAssertEqual(launcher.recorder(for: "global").launchCount, 0)
        XCTAssertEqual(launcher.recorder(for: "override").probeDetails, [.toolsAndAuthOnly])
        XCTAssertEqual(launcher.recorder(for: "project").probeDetails, [.toolsAndAuthOnly])

        try await sendRequest(
            id: 4,
            method: "mcpServerStatus/list",
            params: [:],
            to: fixture.session
        )
        let missingThreadID = UUID().uuidString.lowercased()
        try await sendRequest(
            id: 5,
            method: "mcpServerStatus/list",
            params: ["threadId": missingThreadID],
            to: fixture.session
        )
        records = try await fixture.output.records()
        let globalRows = try XCTUnwrap(result(for: 4, in: records)?["data"]?.arrayValue)
        XCTAssertEqual(globalRows.compactMap { $0.objectValue?["name"]?.stringValue }, ["global-server"])
        XCTAssertEqual(launcher.recorder(for: "global").probeDetails, [.full])
        XCTAssertEqual(errorCode(for: 5, in: records), -32_600)
        XCTAssertEqual(errorMessage(for: 5, in: records), "thread not found: \(missingThreadID)")

        await fixture.session.finishInput()
    }

    func testToolCallAndResourceReadPreserveExactWirePayloads() async throws {
        let toolResult = MCPToolCallResult(
            content: [.object(["type": .string("text"), "text": .string("two matches")])],
            structuredContent: .object(["matches": .number(2)]),
            isError: false,
            metadata: .object(["traceID": .string("trace-123")])
        )
        let resourceResult = MCPResourceReadResult(contents: [
            .object([
                "uri": .string("docs://guide"),
                "mimeType": .string("text/markdown"),
                "text": .string("# Guide")
            ])
        ])
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(probe: Self.dashProbe, toolResult: toolResult, resourceResult: resourceResult)
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "fixture"
            """,
            launcher: launcher
        )
        let threadID = try await startThread(in: fixture)

        try await sendRequest(
            id: 3,
            method: "mcpServer/tool/call",
            params: [
                "threadId": threadID,
                "server": "fixture",
                "tool": "search",
                "arguments": ["query": "swift"],
                "_meta": ["requestID": "request-123"]
            ],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "mcpServer/resource/read",
            params: ["threadId": threadID, "server": "fixture", "uri": "docs://guide"],
            to: fixture.session
        )
        let records = try await fixture.output.records()
        let call = try XCTUnwrap(result(for: 3, in: records))
        let read = try XCTUnwrap(result(for: 4, in: records))

        XCTAssertEqual(call["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue, "two matches")
        XCTAssertEqual(call["structuredContent"]?.objectValue?["matches"]?.numberValue, 2)
        XCTAssertEqual(call["isError"]?.boolValue, false)
        XCTAssertEqual(call["_meta"]?.objectValue?["traceID"]?.stringValue, "trace-123")
        XCTAssertEqual(read["contents"]?.arrayValue?.first?.objectValue?["text"]?.stringValue, "# Guide")

        let recorder = launcher.recorder(for: "fixture")
        let recordedCall = try XCTUnwrap(recorder.toolCalls.first)
        XCTAssertEqual(recordedCall.tool, "search")
        XCTAssertEqual(recordedCall.arguments, .object(["query": .string("swift")]))
        XCTAssertEqual(recordedCall.metadata, .object(["requestID": .string("request-123")]))
        XCTAssertEqual(recorder.resourceURIs, ["docs://guide"])

        await fixture.session.finishInput()
    }

    func testReloadAndInputFinishTerminateCachedSessions() async throws {
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(probe: Self.namedProbe("Fixture MCP"))
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "fixture"
            """,
            launcher: launcher
        )

        try await sendRequest(id: 2, method: "mcpServerStatus/list", params: [:], to: fixture.session)
        try await sendRequest(id: 3, method: "config/mcpServer/reload", params: [:], to: fixture.session)
        XCTAssertEqual(launcher.recorder(for: "fixture").launchCount, 1)
        XCTAssertEqual(launcher.recorder(for: "fixture").terminationCount, 1)

        try await sendRequest(id: 4, method: "mcpServerStatus/list", params: [:], to: fixture.session)
        XCTAssertEqual(launcher.recorder(for: "fixture").launchCount, 2)
        try await sendRequest(id: 5, method: "mcpServer/refresh", params: [:], to: fixture.session)
        XCTAssertEqual(launcher.recorder(for: "fixture").terminationCount, 2)
        await fixture.session.finishInput()
        XCTAssertEqual(launcher.recorder(for: "fixture").terminationCount, 2)

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 3, in: records), [:])
        XCTAssertEqual(result(for: 5, in: records), [:])
    }

    func testRequiredServerFailureRejectsThreadBeforePersistence() async throws {
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.required-fixture]
            command = "missing"
            required = true
            """,
            launcher: FakeMCPLauncher(specifications: [:])
        )

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: ["cwd": fixture.workspace.path, "model": "trustedrouter/fast"],
            to: fixture.session
        )
        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 2, in: records), -32_603)
        XCTAssertTrue(
            errorMessage(for: 2, in: records)?.contains(
                "required MCP servers failed to initialize: required-fixture"
            ) == true
        )
        let startup = records.compactMap { record -> [String: CLIJSONValue]? in
            guard record["method"]?.stringValue == "mcpServer/startupStatus/updated" else { return nil }
            return record["params"]?.objectValue
        }
        XCTAssertEqual(startup.compactMap { $0["status"]?.stringValue }, ["starting", "failed"])
        XCTAssertEqual(startup.first?["name"]?.stringValue, "required-fixture")
        XCTAssertEqual(startup.first?["error"], .null)
        XCTAssertEqual(startup.first?["failureReason"], .null)
        XCTAssertTrue(startup.last?["error"]?.stringValue?.contains("no fake MCP server named missing") == true)
        XCTAssertEqual(startup.last?["failureReason"], .null)
        XCTAssertEqual(startup.first?["threadId"], startup.last?["threadId"])
        let threadFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.home.appendingPathComponent("threads", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(threadFiles.isEmpty)

        await fixture.session.finishInput()
    }

    func testThreadStartEmitsRequiredBeforeResponseAndOptionalAfterResponse() async throws {
        let launcher = FakeMCPLauncher(specifications: [
            "required": .init(probe: Self.namedProbe("Required MCP")),
            "optional": .init(probe: Self.namedProbe("Optional MCP"))
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.required-server]
            command = "required"
            required = true

            [mcp_servers.optional-server]
            command = "optional"
            """,
            launcher: launcher
        )

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: ["cwd": fixture.workspace.path, "model": "trustedrouter/fast"],
            to: fixture.session
        )
        _ = try await fixture.output.waitForMCPStartup(server: "optional-server", status: "ready")

        let records = try await fixture.output.records()
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        let response = try XCTUnwrap(result(for: 2, in: records))
        let threadID = try XCTUnwrap(response["thread"]?.objectValue?["id"]?.stringValue)
        let startup = records.enumerated().compactMap { index, record -> (Int, [String: CLIJSONValue])? in
            guard record["method"]?.stringValue == "mcpServer/startupStatus/updated",
                  let params = record["params"]?.objectValue
            else {
                return nil
            }
            return (index, params)
        }
        XCTAssertEqual(startup.map { $0.1["name"]?.stringValue }, [
            "required-server", "required-server", "optional-server", "optional-server"
        ])
        XCTAssertEqual(startup.map { $0.1["status"]?.stringValue }, [
            "starting", "ready", "starting", "ready"
        ])
        XCTAssertTrue(startup.allSatisfy { $0.1["threadId"]?.stringValue == threadID })
        XCTAssertTrue(startup.allSatisfy { $0.1["error"] == .null })
        XCTAssertTrue(startup.allSatisfy { $0.1["failureReason"] == .null })
        XCTAssertTrue(startup.allSatisfy {
            Set($0.1.keys) == Set(["threadId", "name", "status", "error", "failureReason"])
        })
        XCTAssertLessThan(startup[0].0, responseIndex)
        XCTAssertLessThan(startup[1].0, responseIndex)
        XCTAssertLessThan(responseIndex, startup[2].0)
        XCTAssertLessThan(startup[2].0, startup[3].0)
        XCTAssertEqual(launcher.recorder(for: "required").launchCount, 1)
        XCTAssertEqual(launcher.recorder(for: "optional").launchCount, 1)

        await fixture.session.finishInput()
    }

    func testMCPStartupNotificationOptOutStillStartsOptionalServers() async throws {
        let launcher = FakeMCPLauncher(specifications: [
            "optional": .init(probe: Self.namedProbe("Optional MCP"))
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.optional-server]
            command = "optional"
            """,
            launcher: launcher,
            notificationOptOuts: ["mcpServer/startupStatus/updated"]
        )

        _ = try await startThread(in: fixture)
        await fixture.session.waitForActiveTurns()

        let records = try await fixture.output.records()
        XCTAssertFalse(records.contains {
            $0["method"]?.stringValue == "mcpServer/startupStatus/updated"
        })
        XCTAssertEqual(launcher.recorder(for: "optional").launchCount, 1)
        XCTAssertEqual(launcher.recorder(for: "optional").probeDetails, [.toolsAndAuthOnly])

        await fixture.session.finishInput()
    }

    func testOptionalMCPFailureEmitsAfterSuccessfulThreadResponse() async throws {
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.optional-broken]
            command = "missing"
            """,
            launcher: FakeMCPLauncher(specifications: [:])
        )

        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: ["cwd": fixture.workspace.path, "model": "trustedrouter/fast"],
            to: fixture.session
        )
        let failed = try await fixture.output.waitForMCPStartup(
            server: "optional-broken",
            status: "failed"
        )

        let records = try await fixture.output.records()
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        let response = try XCTUnwrap(result(for: 2, in: records))
        let threadID = try XCTUnwrap(response["thread"]?.objectValue?["id"]?.stringValue)
        let startup = records.enumerated().compactMap { index, record -> (Int, [String: CLIJSONValue])? in
            guard record["method"]?.stringValue == "mcpServer/startupStatus/updated",
                  record["params"]?.objectValue?["name"]?.stringValue == "optional-broken",
                  let params = record["params"]?.objectValue
            else {
                return nil
            }
            return (index, params)
        }
        XCTAssertEqual(startup.map { $0.1["status"]?.stringValue }, ["starting", "failed"])
        XCTAssertTrue(startup.allSatisfy { responseIndex < $0.0 })
        XCTAssertTrue(startup.allSatisfy { $0.1["threadId"]?.stringValue == threadID })
        XCTAssertEqual(failed["failureReason"], .null)
        XCTAssertTrue(failed["error"]?.stringValue?.contains("no fake MCP server named missing") == true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.home
                    .appendingPathComponent("threads", isDirectory: true)
                    .appendingPathComponent("\(threadID).json")
                    .path
            )
        )

        await fixture.session.finishInput()
    }

    func testReloadCancelsInFlightOptionalMCPStartup() async throws {
        let launcher = FakeMCPLauncher(specifications: [
            "optional": .init(
                probe: Self.namedProbe("Optional MCP"),
                probeDelay: 0.5
            )
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.optional-server]
            command = "optional"
            """,
            launcher: launcher
        )

        _ = try await startThread(in: fixture)
        _ = try await fixture.output.waitForMCPStartup(server: "optional-server", status: "starting")
        try await sendRequest(
            id: 3,
            method: "config/mcpServer/reload",
            params: [:],
            to: fixture.session
        )
        _ = try await fixture.output.waitForMCPStartup(server: "optional-server", status: "cancelled")

        let records = try await fixture.output.records()
        let startupStatuses = records.compactMap { record -> String? in
            guard record["method"]?.stringValue == "mcpServer/startupStatus/updated",
                  record["params"]?.objectValue?["name"]?.stringValue == "optional-server"
            else {
                return nil
            }
            return record["params"]?.objectValue?["status"]?.stringValue
        }
        XCTAssertEqual(startupStatuses, ["starting", "cancelled"])
        XCTAssertEqual(result(for: 3, in: records), [:])
        XCTAssertEqual(launcher.recorder(for: "optional").launchCount, 1)
        XCTAssertEqual(launcher.recorder(for: "optional").terminationCount, 1)

        await fixture.session.finishInput()
    }

    func testRequiredServerFailureRejectsResumeAndForkWithoutMutatingThreads() async throws {
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(probe: Self.toolProbe(serverName: "Fixture MCP", toolName: "ping"))
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.required-fixture]
            command = "fixture"
            required = true
            """,
            launcher: launcher
        )
        let threadID = try await startThread(in: fixture)
        try Data("""
        [mcp_servers.required-fixture]
        command = "missing"
        required = true
        """.utf8).write(to: fixture.home.appendingPathComponent("config.toml"))

        try await sendRequest(
            id: 3,
            method: "thread/resume",
            params: ["threadId": threadID, "model": "trustedrouter/fusion"],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "thread/fork",
            params: ["threadId": threadID],
            to: fixture.session
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 3, in: records), -32_603)
        XCTAssertEqual(errorCode(for: 4, in: records), -32_603)
        let threadFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.home.appendingPathComponent("threads", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(threadFiles.count, 1)
        let persistedID = try XCTUnwrap(UUID(uuidString: threadID))
        let persisted = try await fixture.session.repository.load(persistedID)
        XCTAssertEqual(persisted.thread.model, "trustedrouter/fast")

        await fixture.session.finishInput()
    }

    func testNormalTurnDiscoversAndExecutesMCPToolWithNativeProgressItem() async throws {
        let llm = AppServerMCPAgentLLM()
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(
                probe: Self.dashProbe,
                toolResult: MCPToolCallResult(
                    content: [.object(["type": .string("text"), "text": .string("searched swift")])],
                    structuredContent: .object(["matches": .number(1)]),
                    isError: false
                ),
                toolProgress: [
                    ToolExecutionProgress(completed: 1, total: 2),
                    ToolExecutionProgress(completed: 2, total: 2, message: "Indexing documentation")
                ]
            )
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "fixture"
            enabled_tools = ["search"]

            [mcp_servers.optional-broken]
            command = "missing"
            """,
            launcher: launcher,
            runnerFactory: { _ in AgentRunner(llm: llm) }
        )
        let threadID = try await startThread(in: fixture)

        try await startAndWaitTurn(
            id: 3,
            threadID: threadID,
            text: "Search the documentation for Swift",
            in: fixture
        )

        let recorded = try XCTUnwrap(launcher.recorder(for: "fixture").toolCalls.first)
        XCTAssertEqual(recorded.tool, "search")
        XCTAssertEqual(recorded.arguments, .object(["query": .string("swift")]))
        XCTAssertNil(recorded.metadata)
        let observedToolNames = await llm.observedMCPToolNames()
        XCTAssertEqual(observedToolNames, [["mcp__fixture__search"], ["mcp__fixture__search"]])

        let records = try await fixture.output.records()
        let completed = try XCTUnwrap(records.last { $0["method"]?.stringValue == "turn/completed" })
        let items = completed["params"]?.objectValue?["turn"]?.objectValue?["items"]?.arrayValue ?? []
        let mcpItem = try XCTUnwrap(items.first { $0.objectValue?["type"]?.stringValue == "mcpToolCall" })
            .objectValue
        XCTAssertEqual(mcpItem?["server"]?.stringValue, "fixture")
        XCTAssertEqual(mcpItem?["tool"]?.stringValue, "search")
        XCTAssertEqual(mcpItem?["status"]?.stringValue, "completed")
        XCTAssertEqual(mcpItem?["arguments"]?.objectValue?["query"]?.stringValue, "swift")
        XCTAssertEqual(
            mcpItem?["result"]?.objectValue?["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue,
            "searched swift"
        )

        let progress = records.filter { $0["method"]?.stringValue == "item/mcpToolCall/progress" }
        XCTAssertEqual(progress.count, 1, "Message-free MCP progress has no Codex wire representation")
        let progressParams = try XCTUnwrap(progress.first?["params"]?.objectValue)
        let itemID = try XCTUnwrap(progressParams["itemId"]?.stringValue)
        let turnID = try XCTUnwrap(progressParams["turnId"]?.stringValue)
        XCTAssertEqual(progressParams["threadId"]?.stringValue, threadID)
        XCTAssertEqual(progressParams["message"]?.stringValue, "Indexing documentation")

        let startedIndex = try XCTUnwrap(records.firstIndex { record in
            record["method"]?.stringValue == "item/started"
                && record["params"]?.objectValue?["turnId"]?.stringValue == turnID
                && record["params"]?.objectValue?["item"]?.objectValue?["id"]?.stringValue == itemID
        })
        let progressIndex = try XCTUnwrap(records.firstIndex { record in
            record["method"]?.stringValue == "item/mcpToolCall/progress"
                && record["params"]?.objectValue?["itemId"]?.stringValue == itemID
        })
        let completedIndex = try XCTUnwrap(records.firstIndex { record in
            record["method"]?.stringValue == "item/completed"
                && record["params"]?.objectValue?["turnId"]?.stringValue == turnID
                && record["params"]?.objectValue?["item"]?.objectValue?["id"]?.stringValue == itemID
        })
        XCTAssertLessThan(startedIndex, progressIndex)
        XCTAssertLessThan(progressIndex, completedIndex)

        await fixture.session.finishInput()
    }

    func testMCPProgressNotificationOptOutDoesNotSuppressExecutionOrCompletion() async throws {
        let llm = AppServerMCPAgentLLM()
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(
                probe: Self.dashProbe,
                toolResult: MCPToolCallResult(
                    content: [.object(["type": .string("text"), "text": .string("done")])]
                ),
                toolProgress: [
                    ToolExecutionProgress(completed: 1, total: 1, message: "Finishing search")
                ]
            )
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "fixture"
            enabled_tools = ["search"]
            """,
            launcher: launcher,
            notificationOptOuts: ["item/mcpToolCall/progress"],
            runnerFactory: { _ in AgentRunner(llm: llm) }
        )
        let threadID = try await startThread(in: fixture)

        try await startAndWaitTurn(
            id: 3,
            threadID: threadID,
            text: "Search the documentation",
            in: fixture
        )

        let records = try await fixture.output.records()
        XCTAssertFalse(records.contains { $0["method"]?.stringValue == "item/mcpToolCall/progress" })
        XCTAssertTrue(records.contains { record in
            record["method"]?.stringValue == "item/completed"
                && record["params"]?.objectValue?["item"]?.objectValue?["type"]?.stringValue
                    == "mcpToolCall"
        })
        XCTAssertEqual(launcher.recorder(for: "fixture").toolCalls.count, 1)

        await fixture.session.finishInput()
    }

    func testReloadAppliesReplacementMCPInventoryToNextTurn() async throws {
        let llm = AppServerMCPAgentLLM()
        let launcher = FakeMCPLauncher(specifications: [
            "first": .init(probe: Self.toolProbe(serverName: "First MCP", toolName: "ping")),
            "replacement": .init(
                probe: Self.toolProbe(serverName: "Replacement MCP", toolName: "lookup"),
                toolResult: MCPToolCallResult(
                    content: [.object(["type": .string("text"), "text": .string("replacement result")])]
                )
            )
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "first"
            """,
            launcher: launcher,
            runnerFactory: { _ in AgentRunner(llm: llm) }
        )
        let threadID = try await startThread(in: fixture)
        try await startAndWaitTurn(id: 3, threadID: threadID, text: "First turn", in: fixture)

        try Data("""
        [mcp_servers.fixture]
        command = "replacement"
        """.utf8).write(to: fixture.home.appendingPathComponent("config.toml"))
        try await sendRequest(
            id: 4,
            method: "config/mcpServer/reload",
            params: [:],
            to: fixture.session
        )
        try await startAndWaitTurn(id: 5, threadID: threadID, text: "Second turn", in: fixture)

        XCTAssertEqual(launcher.recorder(for: "first").toolCalls.map(\.tool), ["ping"])
        XCTAssertEqual(launcher.recorder(for: "first").terminationCount, 1)
        XCTAssertEqual(launcher.recorder(for: "replacement").toolCalls.map(\.tool), ["lookup"])
        let observedToolNames = await llm.observedMCPToolNames()
        XCTAssertEqual(observedToolNames, [
            ["mcp__fixture__ping"],
            ["mcp__fixture__ping"],
            ["mcp__fixture__lookup"],
            ["mcp__fixture__lookup"]
        ])

        await fixture.session.finishInput()
    }

    func testOAuthLoginRespondsBeforeCompletionAndForwardsOptions() async throws {
        let loginDriver = MCPLoginTestDriver()
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.remote]
            url = "https://mcp.example.com/api"
            oauth_client_id = "configured-client"
            scopes = ["configured:read"]
            oauth_resource = "https://resource.example.com"
            """,
            launcher: FakeMCPLauncher(specifications: [:]),
            mcpOAuthLoginStarter: loginDriver
        )

        try await sendRequest(
            id: 2,
            method: "mcpServer/oauth/login",
            params: [
                "name": "remote",
                "scopes": ["requested:read", "requested:write"],
                "timeoutSecs": 7
            ],
            to: fixture.session
        )
        var records = try await fixture.output.records()
        XCTAssertEqual(
            result(for: 2, in: records)?["authorizationUrl"]?.stringValue,
            MCPLoginTestDriver.authorizationURL.absoluteString
        )
        XCTAssertFalse(records.contains { $0["method"]?.stringValue == "mcpServer/oauthLogin/completed" })
        let invocation = try XCTUnwrap(loginDriver.recorder.invocations.first)
        XCTAssertEqual(invocation.name, "remote")
        XCTAssertEqual(invocation.requestedScopes, ["requested:read", "requested:write"])
        XCTAssertEqual(invocation.timeout, 7)

        await loginDriver.succeed()
        let completed = try await fixture.output.waitForNotification(
            method: "mcpServer/oauthLogin/completed"
        )
        XCTAssertEqual(completed["name"]?.stringValue, "remote")
        XCTAssertEqual(completed["threadId"], .null)
        XCTAssertEqual(completed["success"]?.boolValue, true)
        XCTAssertEqual(completed["error"], .null)

        records = try await fixture.output.records()
        let responseIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        let completionIndex = try XCTUnwrap(records.firstIndex {
            $0["method"]?.stringValue == "mcpServer/oauthLogin/completed"
        })
        XCTAssertLessThan(responseIndex, completionIndex)

        await fixture.session.finishInput()
    }

    func testOAuthFailureRedactsProviderBody() async throws {
        let loginDriver = MCPLoginTestDriver()
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.remote]
            url = "https://mcp.example.com/api"
            scopes = ["tools:read"]
            """,
            launcher: FakeMCPLauncher(specifications: [:]),
            mcpOAuthLoginStarter: loginDriver
        )
        try await sendRequest(
            id: 2,
            method: "mcpServer/oauth/login",
            params: ["name": "remote"],
            to: fixture.session
        )
        await loginDriver.fail(
            MCPOAuthError.tokenExchangeFailed(
                statusCode: 401,
                body: #"{"access_token":"must-not-leak"}"#
            )
        )

        let completed = try await fixture.output.waitForNotification(
            method: "mcpServer/oauthLogin/completed"
        )
        XCTAssertEqual(completed["success"]?.boolValue, false)
        XCTAssertEqual(completed["error"]?.stringValue, "MCP OAuth token exchange failed with HTTP 401.")
        let encodedRecords = String(describing: try await fixture.output.records())
        XCTAssertFalse(encodedRecords.contains("must-not-leak"))
        await fixture.session.finishInput()
    }

    func testOAuthClampsNonpositiveTimeoutToOneSecond() async throws {
        let loginDriver = MCPLoginTestDriver()
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.remote]
            url = "https://mcp.example.com/api"
            """,
            launcher: FakeMCPLauncher(specifications: [:]),
            mcpOAuthLoginStarter: loginDriver
        )

        try await sendRequest(
            id: 2,
            method: "mcpServer/oauth/login",
            params: ["name": "remote", "timeoutSecs": 0],
            to: fixture.session
        )

        XCTAssertEqual(loginDriver.recorder.invocations.first?.timeout, 1)
        await fixture.session.finishInput()
    }

    func testOAuthUsesThreadScopedConfigurationAndReportsThreadID() async throws {
        let loginDriver = MCPLoginTestDriver()
        let fixture = try await makeFixture(
            config: "",
            launcher: FakeMCPLauncher(specifications: [:]),
            mcpOAuthLoginStarter: loginDriver
        )
        let projectConfig = fixture.workspace.appendingPathComponent(".quillcode/config.toml")
        try FileManager.default.createDirectory(
            at: projectConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        [mcp_servers.project-remote]
        url = "https://project.example.com/mcp"
        scopes = ["project:read"]
        """.utf8).write(to: projectConfig)
        let threadID = try await startThread(in: fixture)

        try await sendRequest(
            id: 3,
            method: "mcpServer/oauth/login",
            params: ["name": "project-remote", "threadId": threadID],
            to: fixture.session
        )
        await loginDriver.succeed()
        let completed = try await fixture.output.waitForNotification(
            method: "mcpServer/oauthLogin/completed"
        )
        XCTAssertEqual(completed["threadId"]?.stringValue, threadID)
        XCTAssertEqual(loginDriver.recorder.invocations.first?.name, "project-remote")

        await fixture.session.finishInput()
    }

    func testOAuthRejectsInvalidTargetsAndCancelsPendingLoginOnDisconnect() async throws {
        let loginDriver = MCPLoginTestDriver()
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.local]
            command = "local"

            [mcp_servers.bearer]
            url = "https://bearer.example.com/mcp"
            bearer_token_env_var = "MCP_TOKEN"

            [mcp_servers.remote]
            url = "https://remote.example.com/mcp"
            scopes = ["tools:read"]
            """,
            launcher: FakeMCPLauncher(specifications: [
                "local": .init(probe: Self.namedProbe("Local MCP"))
            ]),
            environment: ["MCP_TOKEN": "configured-secret"],
            mcpOAuthLoginStarter: loginDriver
        )

        try await sendRequest(
            id: 2,
            method: "mcpServer/oauth/login",
            params: ["name": "missing"],
            to: fixture.session
        )
        try await sendRequest(
            id: 3,
            method: "mcpServer/oauth/login",
            params: ["name": "local"],
            to: fixture.session
        )
        try await sendRequest(
            id: 4,
            method: "mcpServer/oauth/login",
            params: ["name": "bearer"],
            to: fixture.session
        )
        try await sendRequest(
            id: 5,
            method: "mcpServer/oauth/login",
            params: ["name": "remote", "scopes": [""]],
            to: fixture.session
        )
        try await sendRequest(
            id: 6,
            method: "mcpServer/oauth/login",
            params: ["name": "remote"],
            to: fixture.session
        )
        try await sendRequest(
            id: 7,
            method: "mcpServer/oauth/login",
            params: ["name": "remote"],
            to: fixture.session
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 2, in: records), -32_600)
        XCTAssertTrue(errorMessage(for: 2, in: records)?.contains("No MCP server") == true)
        XCTAssertTrue(errorMessage(for: 3, in: records)?.contains("HTTP transport") == true)
        XCTAssertTrue(errorMessage(for: 4, in: records)?.contains("bearer authorization") == true)
        XCTAssertEqual(errorCode(for: 5, in: records), -32_602)
        XCTAssertTrue(errorMessage(for: 7, in: records)?.contains("already in progress") == true)

        await fixture.session.finishInput()
        try await Task.sleep(for: .milliseconds(30))
        let cancellationCount = await loginDriver.cancellationCount
        XCTAssertEqual(cancellationCount, 1)
        let finalRecords = try await fixture.output.records()
        XCTAssertFalse(finalRecords.contains {
            $0["method"]?.stringValue == "mcpServer/oauthLogin/completed"
        })
    }

    func testDirectToolCallRelaysStandardFormElicitationAndPreservesResponseMetadata() async throws {
        let schema: MCPJSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "nickname": .object([
                    "type": .string("string"),
                    "title": .string("Nickname")
                ])
            ]),
            "required": .array([.string("nickname")])
        ])
        let request = MCPClientElicitationRequest.form(
            message: "Choose a nickname",
            requestedSchema: schema,
            metadata: .object(["traceID": .string("trace-form")])
        )
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(
                probe: Self.dashProbe,
                toolResult: MCPToolCallResult(
                    content: [.object(["type": .string("text"), "text": .string("saved")])]
                ),
                elicitationRequest: request
            )
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "fixture"
            """,
            launcher: launcher
        )
        let threadID = try await startThread(in: fixture)

        let callData = try JSONSerialization.data(withJSONObject: [
            "id": 3,
            "method": "mcpServer/tool/call",
            "params": [
                "threadId": threadID,
                "server": "fixture",
                "tool": "search",
                "arguments": ["query": "swift"]
            ]
        ], options: [.sortedKeys])
        let callSession = fixture.session
        let call = Task { await callSession.receive(callData) }
        let outbound = try await fixture.output.waitForRequest(method: "mcpServer/elicitation/request")
        let requestID = try XCTUnwrap(outbound["id"]?.stringValue)
        let params = try XCTUnwrap(outbound["params"]?.objectValue)
        XCTAssertEqual(params["threadId"]?.stringValue, threadID)
        XCTAssertEqual(params["turnId"], .null)
        XCTAssertEqual(params["serverName"]?.stringValue, "fixture")
        XCTAssertEqual(params["mode"]?.stringValue, "form")
        XCTAssertEqual(params["message"]?.stringValue, "Choose a nickname")
        XCTAssertEqual(params["requestedSchema"], schema.cliJSONValue)
        XCTAssertEqual(params["_meta"]?.objectValue?["traceID"]?.stringValue, "trace-form")

        try await send([
            "id": requestID,
            "result": [
                "action": "accept",
                "content": ["nickname": "Quill"],
                "_meta": ["receipt": "accepted"]
            ]
        ], to: fixture.session)
        await call.value

        let recorder = launcher.recorder(for: "fixture")
        XCTAssertEqual(recorder.configuredCapabilities, [
            MCPClientCapabilities(
                supportsFormElicitation: true,
                supportsOpenAIFormElicitation: false
            )
        ])
        XCTAssertEqual(recorder.elicitations, [
            .init(
                request: request,
                response: .accept(
                    content: .object(["nickname": .string("Quill")]),
                    metadata: .object(["receipt": .string("accepted")])
                )
            )
        ])
        let records = try await fixture.output.records()
        let requestIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.stringValue == requestID })
        let resolvedIndex = try XCTUnwrap(records.firstIndex {
            $0["method"]?.stringValue == "serverRequest/resolved"
                && $0["params"]?.objectValue?["requestId"]?.stringValue == requestID
        })
        let resultIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 3 })
        XCTAssertLessThan(requestIndex, resolvedIndex)
        XCTAssertLessThan(resolvedIndex, resultIndex)

        await fixture.session.finishInput()
    }

    func testRichFormElicitationRequiresAndAdvertisesInitializeCapability() async throws {
        let request = MCPClientElicitationRequest.openAIForm(
            message: "Configure deployment",
            requestedSchema: .object([
                "type": .string("object"),
                "layout": .object(["columns": .number(2)])
            ]),
            metadata: nil
        )
        let enabledLauncher = FakeMCPLauncher(specifications: [
            "enabled": .init(probe: Self.dashProbe, elicitationRequest: request)
        ])
        let enabled = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "enabled"
            """,
            launcher: enabledLauncher,
            supportsOpenAIFormElicitation: true
        )
        let enabledThreadID = try await startThread(in: enabled)
        let enabledCallData = try JSONSerialization.data(withJSONObject: [
            "id": 3,
            "method": "mcpServer/tool/call",
            "params": [
                "threadId": enabledThreadID,
                "server": "fixture",
                "tool": "search"
            ]
        ], options: [.sortedKeys])
        let enabledSession = enabled.session
        let enabledCall = Task { await enabledSession.receive(enabledCallData) }
        let outbound = try await enabled.output.waitForRequest(method: "mcpServer/elicitation/request")
        let requestID = try XCTUnwrap(outbound["id"]?.stringValue)
        XCTAssertEqual(outbound["params"]?.objectValue?["mode"]?.stringValue, "openai/form")
        try await send([
            "id": requestID,
            "result": ["action": "decline", "_meta": ["reason": "not now"]]
        ], to: enabled.session)
        await enabledCall.value
        XCTAssertEqual(enabledLauncher.recorder(for: "enabled").configuredCapabilities, [
            MCPClientCapabilities(
                supportsFormElicitation: true,
                supportsOpenAIFormElicitation: true
            )
        ])
        XCTAssertEqual(enabledLauncher.recorder(for: "enabled").elicitations.first?.response, .decline(
            metadata: .object(["reason": .string("not now")])
        ))
        await enabled.session.finishInput()

        let disabledLauncher = FakeMCPLauncher(specifications: [
            "disabled": .init(probe: Self.dashProbe, elicitationRequest: request)
        ])
        let disabled = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "disabled"
            """,
            launcher: disabledLauncher
        )
        let disabledThreadID = try await startThread(in: disabled)
        try await sendRequest(
            id: 3,
            method: "mcpServer/tool/call",
            params: [
                "threadId": disabledThreadID,
                "server": "fixture",
                "tool": "search"
            ],
            to: disabled.session
        )
        XCTAssertEqual(disabledLauncher.recorder(for: "disabled").elicitations.first?.response, .cancel())
        let disabledRecords = try await disabled.output.records()
        XCTAssertFalse(disabledRecords.contains {
            $0["method"]?.stringValue == "mcpServer/elicitation/request"
        })
        await disabled.session.finishInput()
    }

    func testURLElicitationRelaysExactFieldsAndClientErrorDeclines() async throws {
        let request = MCPClientElicitationRequest.url(
            message: "Authorize access",
            url: "https://auth.example.com/consent",
            elicitationID: "consent-123",
            metadata: .object(["provider": .string("example")])
        )
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(probe: Self.dashProbe, elicitationRequest: request)
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "fixture"
            """,
            launcher: launcher
        )
        let threadID = try await startThread(in: fixture)
        let callData = try JSONSerialization.data(withJSONObject: [
            "id": 3,
            "method": "mcpServer/tool/call",
            "params": ["threadId": threadID, "server": "fixture", "tool": "search"]
        ], options: [.sortedKeys])
        let callSession = fixture.session
        let call = Task { await callSession.receive(callData) }
        let outbound = try await fixture.output.waitForRequest(method: "mcpServer/elicitation/request")
        let requestID = try XCTUnwrap(outbound["id"]?.stringValue)
        let params = try XCTUnwrap(outbound["params"]?.objectValue)
        XCTAssertEqual(params["mode"]?.stringValue, "url")
        XCTAssertEqual(params["url"]?.stringValue, "https://auth.example.com/consent")
        XCTAssertEqual(params["elicitationId"]?.stringValue, "consent-123")
        XCTAssertEqual(params["_meta"]?.objectValue?["provider"]?.stringValue, "example")
        try await send([
            "id": requestID,
            "error": ["code": -32_603, "message": "client dismissed form"]
        ], to: fixture.session)
        await call.value
        XCTAssertEqual(launcher.recorder(for: "fixture").elicitations.first?.response, .decline())
        await fixture.session.finishInput()
    }

    func testInterruptCancelsTurnElicitationBeforeTurnCompletion() async throws {
        let llm = AppServerMCPAgentLLM()
        let request = MCPClientElicitationRequest.form(
            message: "Choose a result",
            requestedSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ]),
            metadata: nil
        )
        let launcher = FakeMCPLauncher(specifications: [
            "fixture": .init(probe: Self.dashProbe, elicitationRequest: request)
        ])
        let fixture = try await makeFixture(
            config: """
            [mcp_servers.fixture]
            command = "fixture"
            enabled_tools = ["search"]
            """,
            launcher: launcher,
            runnerFactory: { _ in AgentRunner(llm: llm) }
        )
        let threadID = try await startThread(in: fixture)
        try await sendRequest(
            id: 3,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": "Search documentation"]]
            ],
            to: fixture.session
        )
        let outbound = try await fixture.output.waitForRequest(method: "mcpServer/elicitation/request")
        let requestID = try XCTUnwrap(outbound["id"]?.stringValue)
        let turnID = try XCTUnwrap(outbound["params"]?.objectValue?["turnId"]?.stringValue)
        try await sendRequest(
            id: 4,
            method: "turn/interrupt",
            params: ["threadId": threadID, "turnId": turnID],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()

        XCTAssertEqual(launcher.recorder(for: "fixture").elicitations.first?.response, .cancel())
        let records = try await fixture.output.records()
        let resolvedIndex = try XCTUnwrap(records.firstIndex {
            $0["method"]?.stringValue == "serverRequest/resolved"
                && $0["params"]?.objectValue?["requestId"]?.stringValue == requestID
        })
        let completedIndex = try XCTUnwrap(records.firstIndex {
            $0["method"]?.stringValue == "turn/completed"
                && $0["params"]?.objectValue?["turn"]?.objectValue?["id"]?.stringValue == turnID
        })
        XCTAssertLessThan(resolvedIndex, completedIndex)
        XCTAssertEqual(
            records[completedIndex]["params"]?.objectValue?["turn"]?.objectValue?["status"]?.stringValue,
            "interrupted"
        )
        await fixture.session.finishInput()
    }

    private func makeFixture(
        config: String,
        launcher: FakeMCPLauncher,
        environment: [String: String] = [:],
        mcpOAuthLoginStarter: any AppServerMCPOAuthLoginStarting = MCPLoginTestDriver(),
        notificationOptOuts: [String] = [],
        supportsOpenAIFormElicitation: Bool = false,
        runnerFactory: @escaping CLIAgentRunnerFactory = CLIRuntimeFactory.make
    ) async throws -> AppServerMCPFixture {
        let home = try temporaryDirectory(prefix: "app-server-mcp-home")
        let workspace = try temporaryDirectory(prefix: "app-server-mcp-workspace")
        try Data(config.utf8).write(to: home.appendingPathComponent("config.toml"))
        let output = AppServerMCPOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: environment,
            currentDirectory: workspace,
            runnerFactory: runnerFactory,
            mcpLauncher: launcher,
            mcpOAuthLoginStarter: mcpOAuthLoginStarter,
            sink: { line in await output.append(line) }
        )
        var initializeParams: [String: Any] = [
            "clientInfo": ["name": "MCPTests", "version": "1"]
        ]
        var capabilities: [String: Any] = [:]
        if !notificationOptOuts.isEmpty {
            capabilities["optOutNotificationMethods"] = notificationOptOuts
        }
        if supportsOpenAIFormElicitation {
            capabilities["mcpServerOpenaiFormElicitation"] = true
        }
        if !capabilities.isEmpty {
            initializeParams["capabilities"] = capabilities
        }
        try await sendRequest(
            id: 1,
            method: "initialize",
            params: initializeParams,
            to: session
        )
        try await sendNotification(method: "initialized", params: [:], to: session)
        return AppServerMCPFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace
        )
    }

    private func startThread(in fixture: AppServerMCPFixture) async throws -> String {
        try await sendRequest(
            id: 2,
            method: "thread/start",
            params: ["cwd": fixture.workspace.path, "model": "trustedrouter/fast"],
            to: fixture.session
        )
        let records = try await fixture.output.records()
        return try XCTUnwrap(result(for: 2, in: records)?["thread"]?.objectValue?["id"]?.stringValue)
    }

    private func startAndWaitTurn(
        id: Int,
        threadID: String,
        text: String,
        in fixture: AppServerMCPFixture
    ) async throws {
        try await sendRequest(
            id: id,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": text]]
            ],
            to: fixture.session
        )
        await fixture.session.waitForActiveTurns()
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
        await session.receive(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
    }

    private func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func errorCode(for id: Int, in records: [[String: CLIJSONValue]]) -> Double? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["code"]?.numberValue
    }

    private func errorMessage(for id: Int, in records: [[String: CLIJSONValue]]) -> String? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["message"]?.stringValue
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private static let dashProbe = MCPServerProbeResult(
        protocolVersion: "2025-03-26",
        serverName: "Dash MCP",
        serverVersion: "2.0.0",
        serverInfo: .object(["name": .string("Dash MCP"), "version": .string("2.0.0")]),
        tools: [
            .object([
                "name": .string("search"),
                "description": .string("Search documentation"),
                "annotations": .object(["readOnlyHint": .bool(true)])
            ]),
            .object(["name": .string("hidden")])
        ],
        resources: [
            .object(["name": .string("Guide"), "uri": .string("docs://guide")])
        ],
        resourceTemplates: [
            .object(["name": .string("File"), "uriTemplate": .string("file:///{path}")])
        ],
        toolNames: ["search", "hidden"],
        resourceNames: ["Guide"],
        resourceURIs: ["docs://guide"]
    )

    private static let underscoreProbe = namedProbe("Underscore MCP")

    private static func namedProbe(_ name: String) -> MCPServerProbeResult {
        MCPServerProbeResult(
            protocolVersion: "2025-03-26",
            serverName: name,
            serverInfo: .object(["name": .string(name)]),
            tools: [.object(["name": .string("ping")])],
            resources: [.object(["name": .string("Status"), "uri": .string("status://current")])],
            resourceTemplates: [.object(["name": .string("Record"), "uriTemplate": .string("record:///{id}")])],
            toolNames: ["ping"],
            resourceNames: ["Status"],
            resourceURIs: ["status://current"]
        )
    }

    private static func toolProbe(serverName: String, toolName: String) -> MCPServerProbeResult {
        MCPServerProbeResult(
            protocolVersion: "2025-03-26",
            serverName: serverName,
            tools: [
                .object([
                    "name": .string(toolName),
                    "inputSchema": .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ]),
                    "annotations": .object(["readOnlyHint": .bool(true)])
                ])
            ],
            toolNames: [toolName]
        )
    }
}

private actor AppServerMCPAgentLLM: LLMClient {
    private var observed: [[String]] = []

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        _ = userMessage
        let mcpTools = tools.filter { $0.host == .mcp }.map(\.name).sorted()
        observed.append(mcpTools)
        if thread.messages.last?.role == .tool {
            return .say("MCP tool completed.")
        }
        guard let tool = mcpTools.first else {
            throw MCPProbeError.responseError("No MCP tool was available to the test model.")
        }
        let arguments = tool.hasSuffix("search") ? #"{"query":"swift"}"# : "{}"
        return .tool(ToolCall(name: tool, argumentsJSON: arguments))
    }

    func observedMCPToolNames() -> [[String]] {
        observed
    }
}

private actor MCPLoginTestDriver: AppServerMCPOAuthLoginStarting {
    nonisolated static let authorizationURL = URL(string: "https://oauth.example.com/authorize")!
    nonisolated let recorder = MCPLoginInvocationRecorder()

    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var cancellationCount = 0

    nonisolated func start(
        configuration: AppServerMCPServerConfiguration,
        requestedScopes: [String]?,
        timeout: TimeInterval,
        secretStore: any MCPSecretStore
    ) throws -> AppServerMCPOAuthLogin {
        _ = secretStore
        recorder.record(
            .init(
                name: configuration.name,
                requestedScopes: requestedScopes,
                timeout: timeout
            )
        )
        return AppServerMCPOAuthLogin(
            authorizationURL: Self.authorizationURL,
            waitForCompletion: { try await self.wait() },
            cancel: { Task { await self.cancel() } }
        )
    }

    func succeed() {
        complete(.success(()))
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }

    private func wait() async throws {
        if let result {
            self.result = nil
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    private func cancel() {
        cancellationCount += 1
        complete(.failure(CancellationError()))
    }

    private func complete(_ result: Result<Void, Error>) {
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            self.result = result
        }
    }
}

private final class MCPLoginInvocationRecorder: @unchecked Sendable {
    struct Invocation: Sendable, Equatable {
        var name: String
        var requestedScopes: [String]?
        var timeout: TimeInterval
    }

    private let lock = NSLock()
    private var storedInvocations: [Invocation] = []

    var invocations: [Invocation] {
        lock.lock()
        defer { lock.unlock() }
        return storedInvocations
    }

    func record(_ invocation: Invocation) {
        lock.lock()
        storedInvocations.append(invocation)
        lock.unlock()
    }
}
