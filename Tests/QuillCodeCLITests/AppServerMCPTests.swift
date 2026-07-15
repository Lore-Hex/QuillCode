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
        await fixture.session.finishInput()
        XCTAssertEqual(launcher.recorder(for: "fixture").terminationCount, 2)

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 3, in: records), [:])
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
        let threadFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.home.appendingPathComponent("threads", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(threadFiles.isEmpty)

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
                )
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

    func testOAuthLoginReportsExplicitUnsupportedFlow() async throws {
        let fixture = try await makeFixture(config: "", launcher: FakeMCPLauncher(specifications: [:]))

        try await sendRequest(
            id: 2,
            method: "mcpServer/oauth/login",
            params: ["name": "remote"],
            to: fixture.session
        )
        let records = try await fixture.output.records()
        XCTAssertEqual(errorCode(for: 2, in: records), -32_600)
        XCTAssertEqual(
            errorMessage(for: 2, in: records),
            "MCP OAuth login is not available through QuillCode app-server yet; use the QuillCode desktop sign-in flow."
        )

        await fixture.session.finishInput()
    }

    private func makeFixture(
        config: String,
        launcher: FakeMCPLauncher,
        runnerFactory: @escaping CLIAgentRunnerFactory = CLIRuntimeFactory.make
    ) async throws -> AppServerMCPFixture {
        let home = try temporaryDirectory(prefix: "app-server-mcp-home")
        let workspace = try temporaryDirectory(prefix: "app-server-mcp-workspace")
        try Data(config.utf8).write(to: home.appendingPathComponent("config.toml"))
        let output = AppServerMCPOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: runnerFactory,
            mcpLauncher: launcher,
            sink: { line in await output.append(line) }
        )
        try await sendRequest(
            id: 1,
            method: "initialize",
            params: ["clientInfo": ["name": "MCPTests", "version": "1"]],
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
