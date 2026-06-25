import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceMCPIntegrationTests: XCTestCase {
    func testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses() throws {
        let root = try makeQuillCodeTestDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root, includeResourcesAndPrompts: true)
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)
        model.toggleExtensions()

        XCTAssertEqual(model.surface().extensions.items.first?.statusLabel, "Stopped")
        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))

        var surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Ready")
        XCTAssertEqual(surface.extensions.items.first?.serverLabel, "Fixture MCP 1.0.0")
        XCTAssertEqual(surface.extensions.items.first?.protocolLabel, "MCP 2024-11-05")
        XCTAssertEqual(surface.extensions.items.first?.toolCountLabel, "2 tools")
        XCTAssertEqual(surface.extensions.items.first?.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(surface.extensions.items.first?.toolDescriptors.map(\.schemaSummary), [
            "required: path:string",
            "required: content:string, path:string; optional: overwrite:boolean"
        ])
        XCTAssertEqual(surface.extensions.items.first?.resourceCountLabel, "2 resources")
        XCTAssertEqual(surface.extensions.items.first?.resourceNames, ["README", "Project config"])
        XCTAssertEqual(surface.extensions.items.first?.promptCountLabel, "1 prompt")
        XCTAssertEqual(surface.extensions.items.first?.promptNames, ["summarize_project"])
        XCTAssertEqual(surface.extensions.items.first?.stopCommandID, "mcp-stop:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "disconnect-all" }?.isEnabled, true)
        XCTAssertTrue(model.selectedThread?.events.contains {
            $0.summary == "MCP server Filesystem MCP ready (2 tools: read_file, write_file; 2 resources; 1 prompt)"
        } == true)

        XCTAssertTrue(model.runWorkspaceCommand("disconnect-all", workspaceRoot: root))
        surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Stopped")
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "disconnect-all" }?.isEnabled, false)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        XCTAssertTrue(model.runWorkspaceCommand("mcp-stop:mcp_server:filesystem", workspaceRoot: root))
        surface = model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Stopped")
        XCTAssertEqual(surface.extensions.items.first?.startCommandID, "mcp-start:mcp_server:filesystem")
        XCTAssertTrue(model.selectedThread?.events.contains { $0.summary == "MCP server Filesystem MCP stopped" } == true)
    }

    func testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    transport: .stdio,
                    launchExecutable: "quill-mcp",
                    launchCommand: "quill-mcp --root .",
                    launchArguments: ["--root", "."]
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(
                isVisible: true,
                mcpServerStatuses: ["mcp_server:filesystem": .ready],
                mcpServerProbeSummaries: [
                    "mcp_server:filesystem": MCPServerProbeSummary(
                        protocolVersion: "2024-11-05",
                        serverName: "Fixture MCP",
                        serverVersion: "1.0.0",
                        toolDescriptors: [
                            MCPToolDescriptor(
                                name: "read_file",
                                description: "Read a file",
                                requiredArguments: ["path"],
                                schemaSummary: "required: path:string"
                            ),
                            MCPToolDescriptor(
                                name: "write_file",
                                requiredArguments: ["content", "path"],
                                optionalArguments: ["overwrite"],
                                schemaSummary: "required: content:string, path:string; optional: overwrite:boolean"
                            )
                        ],
                        resourceNames: ["README", "Project config"],
                        promptNames: ["summarize_project"]
                    )
                ]
            )
        )

        let surface = model.surface()

        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Ready")
        XCTAssertEqual(surface.extensions.items.first?.serverLabel, "Fixture MCP 1.0.0")
        XCTAssertEqual(surface.extensions.items.first?.protocolLabel, "MCP 2024-11-05")
        XCTAssertEqual(surface.extensions.items.first?.toolCountLabel, "2 tools")
        XCTAssertEqual(surface.extensions.items.first?.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(surface.extensions.items.first?.toolDescriptors.map(\.schemaSummary), [
            "required: path:string",
            "required: content:string, path:string; optional: overwrite:boolean"
        ])
        XCTAssertEqual(surface.extensions.items.first?.resourceCountLabel, "2 resources")
        XCTAssertEqual(surface.extensions.items.first?.resourceNames, ["README", "Project config"])
        XCTAssertEqual(surface.extensions.items.first?.promptCountLabel, "1 prompt")
        XCTAssertEqual(surface.extensions.items.first?.promptNames, ["summarize_project"])
        XCTAssertNil(surface.extensions.items.first?.startCommandID)
        XCTAssertEqual(surface.extensions.items.first?.stopCommandID, "mcp-stop:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-start:mcp_server:filesystem" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-stop:mcp_server:filesystem" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, true)
    }

    func testReadyMCPServerCanBeCalledFromAgentTurn() async throws {
        let root = try makeQuillCodeTestDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root, callText: "hello from MCP")
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","toolName":"read_file","arguments":{"path":"README.md"}}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: MCPFixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("run MCP read_file on README")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(Array(model.selectedThread?.events.map(\.kind).suffix(5) ?? []), [
            .message,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .message
        ])
        XCTAssertEqual(model.selectedThread?.messages.last?.content, "Output:\nhello from MCP")
    }

    func testReadyMCPToolDescriptionIncludesSchemasForLLM() async throws {
        let root = try makeQuillCodeTestDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root)
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let recorder = MCPToolDefinitionRecorder()
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: MCPRecordingLLMClient(recorder: recorder)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("use the MCP filesystem tool")
        await model.submitComposer(workspaceRoot: root)

        let mcpCall = try XCTUnwrap(recorder.tools.first { $0.name == ToolDefinition.mcpCall.name })
        XCTAssertTrue(mcpCall.description.contains("read_file [required: path:string; Read a file]"))
        XCTAssertTrue(mcpCall.description.contains("write_file [required: content:string, path:string; optional: overwrite:boolean]"))
    }

    func testReadyMCPResourceCanBeReadFromAgentTurn() async throws {
        let root = try makeQuillCodeTestDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(
            in: root,
            includeResourcesAndPrompts: true,
            resourceText: "# MCP README"
        )
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpReadResource.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","resourceName":"README"}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: MCPFixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("read the README MCP resource")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.selectedThread?.events.suffix(2).first?.kind, .toolCompleted)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.mcpReadResource.name)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "MCP resource contents:\n# MCP README"
        )
    }

    func testReadyMCPPromptCanBeLoadedFromAgentTurn() async throws {
        let root = try makeQuillCodeTestDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(
            in: root,
            includeResourcesAndPrompts: true,
            promptText: "Summarize this workspace."
        )
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpGetPrompt.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","promptName":"summarize_project"}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: MCPFixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("load the MCP summarize prompt")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.selectedThread?.events.suffix(2).first?.kind, .toolCompleted)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.mcpGetPrompt.name)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("MCP prompt:\nPrompt: summarize_project") == true)
        XCTAssertTrue(model.selectedThread?.messages.last?.content.contains("user: Summarize this workspace.") == true)
    }

    func testMCPToolCallRejectsUnadvertisedTools() async throws {
        let root = try makeQuillCodeTestDirectory()
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(in: root, callText: "should not run")
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
            )

        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","toolName":"delete_everything","arguments":{}}
            """
        )
        let model = QuillCodeWorkspaceModel(runner: AgentRunner(llm: MCPFixedToolLLMClient(call: call)))
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        XCTAssertTrue(model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: root))
        model.setDraft("run MCP delete_everything")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertEqual(model.selectedThread?.events.suffix(2).first?.kind, .toolFailed)
        XCTAssertEqual(
            model.selectedThread?.messages.last?.content,
            "Command failed:\nMCP tool delete_everything was not advertised by mcp_server:filesystem."
        )
    }

    private func writeFixtureMCPServer(
        in root: URL,
        callText: String? = nil,
        includeResourcesAndPrompts: Bool = false,
        resourceText: String? = nil,
        promptText: String? = nil
    ) throws -> URL {
        let script = root.appendingPathComponent("fixture-mcp.sh")
        let capabilities = includeResourcesAndPrompts
            ? #""capabilities":{"tools":{},"resources":{},"prompts":{}}"#
            : #""capabilities":{"tools":{}}"#
        let resourceAndPromptResponses = includeResourcesAndPrompts
            ? """
        emit '{"jsonrpc":"2.0","id":3,"result":{"resources":[{"name":"README","uri":"file:///workspace/README.md"},{"name":"Project config","uri":"file:///workspace/.quillcode/config.toml"}]}}'
        emit '{"jsonrpc":"2.0","id":4,"result":{"prompts":[{"name":"summarize_project"}]}}'
        """
            : ""
        let callResponseID = includeResourcesAndPrompts ? 5 : 3
        let callResponse: String
        if let resourceText {
            callResponse = """
            emit '{"jsonrpc":"2.0","id":\(callResponseID),"result":{"contents":[{"uri":"file:///workspace/README.md","mimeType":"text/markdown","text":"\(resourceText)"}]}}'
            """
        } else if let promptText {
            callResponse = """
            emit '{"jsonrpc":"2.0","id":\(callResponseID),"result":{"description":"Summarize the project.","messages":[{"role":"user","content":{"type":"text","text":"\(promptText)"}}]}}'
            """
        } else if let callText {
            callResponse = """
            emit '{"jsonrpc":"2.0","id":\(callResponseID),"result":{"content":[{"type":"text","text":"\(callText)"}],"isError":false}}'
            """
        } else {
            callResponse = ""
        }
        let content = """
        #!/bin/sh
        emit() {
          body="$1"
          length=$(printf "%s" "$body" | wc -c | tr -d ' ')
          printf "Content-Length: %s\\r\\n\\r\\n%s" "$length" "$body"
        }
        emit '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"Fixture MCP","version":"1.0.0"},\(capabilities)}}'
        emit '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"read_file","description":"Read a file","inputSchema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}},{"name":"write_file","inputSchema":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"},"overwrite":{"type":"boolean"}},"required":["path","content"]}}]}}'
        \(resourceAndPromptResponses)
        \(callResponse)
        sleep 60
        """
        try content.write(to: script, atomically: true, encoding: String.Encoding.utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}

private struct MCPFixedToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}

private final class MCPToolDefinitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedTools: [ToolDefinition] = []

    var tools: [ToolDefinition] {
        lock.withLock { recordedTools }
    }

    func record(_ tools: [ToolDefinition]) {
        lock.withLock {
            recordedTools = tools
        }
    }
}

private struct MCPRecordingLLMClient: LLMClient {
    var recorder: MCPToolDefinitionRecorder

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        recorder.record(tools)
        return .say("done")
    }
}
