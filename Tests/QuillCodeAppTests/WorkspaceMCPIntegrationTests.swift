import Foundation
import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceMCPIntegrationTests: XCTestCase {
    func testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses() throws {
        let setup = try makeConfiguredMCPProject(includeResourcesAndPrompts: true)
        setup.model.toggleExtensions()

        XCTAssertEqual(setup.model.surface().extensions.items.first?.statusLabel, "Stopped")
        XCTAssertTrue(setup.model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: setup.root))

        var surface = setup.model.surface()
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
        XCTAssertTrue(setup.model.selectedThread?.events.contains {
            $0.summary == "MCP server Filesystem MCP ready (2 tools: read_file, write_file; 2 resources; 1 prompt)"
        } == true)

        setup.model.cancelActiveWork()
        surface = setup.model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Stopped")
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, false)

        XCTAssertTrue(setup.model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: setup.root))
        XCTAssertTrue(setup.model.runWorkspaceCommand("mcp-stop:mcp_server:filesystem", workspaceRoot: setup.root))
        surface = setup.model.surface()
        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Stopped")
        XCTAssertEqual(surface.extensions.items.first?.startCommandID, "mcp-start:mcp_server:filesystem")
        XCTAssertTrue(setup.model.selectedThread?.events.contains { $0.summary == "MCP server Filesystem MCP stopped" } == true)
    }

    func testReadyMCPServerCanBeCalledFromAgentTurn() async throws {
        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","toolName":"read_file","arguments":{"path":"README.md"}}
            """
        )
        let setup = try makeConfiguredMCPProject(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            callText: "hello from MCP"
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: setup.root))
        setup.model.setDraft("run MCP read_file on README")
        await setup.model.submitComposer(workspaceRoot: setup.root)

        XCTAssertEqual(Array(setup.model.selectedThread?.events.map(\.kind).suffix(5) ?? []), [
            .message,
            .toolQueued,
            .toolRunning,
            .toolCompleted,
            .message
        ])
        XCTAssertEqual(setup.model.selectedThread?.messages.last?.content, "Output:\nhello from MCP")
    }

    func testReadyMCPToolDescriptionIncludesSchemasForLLM() async throws {
        let recorder = ToolDefinitionRecorder()
        let setup = try makeConfiguredMCPProject(
            runner: AgentRunner(llm: RecordingLLMClient(recorder: recorder))
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: setup.root))
        setup.model.setDraft("use the MCP filesystem tool")
        await setup.model.submitComposer(workspaceRoot: setup.root)

        let mcpCall = try XCTUnwrap(recorder.tools.first { $0.name == ToolDefinition.mcpCall.name })
        XCTAssertTrue(mcpCall.description.contains("read_file [required: path:string; Read a file]"))
        XCTAssertTrue(mcpCall.description.contains("write_file [required: content:string, path:string; optional: overwrite:boolean]"))
    }

    func testReadyMCPResourceCanBeReadFromAgentTurn() async throws {
        let call = ToolCall(
            name: ToolDefinition.mcpReadResource.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","resourceName":"README"}
            """
        )
        let setup = try makeConfiguredMCPProject(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            includeResourcesAndPrompts: true,
            resourceText: "# MCP README"
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: setup.root))
        setup.model.setDraft("read the README MCP resource")
        await setup.model.submitComposer(workspaceRoot: setup.root)

        XCTAssertEqual(setup.model.selectedThread?.events.suffix(2).first?.kind, .toolCompleted)
        XCTAssertEqual(setup.model.currentToolCards.last?.title, ToolDefinition.mcpReadResource.name)
        XCTAssertEqual(
            setup.model.selectedThread?.messages.last?.content,
            "MCP resource contents:\n# MCP README"
        )
    }

    func testReadyMCPPromptCanBeLoadedFromAgentTurn() async throws {
        let call = ToolCall(
            name: ToolDefinition.mcpGetPrompt.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","promptName":"summarize_project"}
            """
        )
        let setup = try makeConfiguredMCPProject(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            includeResourcesAndPrompts: true,
            promptText: "Summarize this workspace."
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: setup.root))
        setup.model.setDraft("load the MCP summarize prompt")
        await setup.model.submitComposer(workspaceRoot: setup.root)

        XCTAssertEqual(setup.model.selectedThread?.events.suffix(2).first?.kind, .toolCompleted)
        XCTAssertEqual(setup.model.currentToolCards.last?.title, ToolDefinition.mcpGetPrompt.name)
        XCTAssertTrue(setup.model.selectedThread?.messages.last?.content.contains("MCP prompt:\nPrompt: summarize_project") == true)
        XCTAssertTrue(setup.model.selectedThread?.messages.last?.content.contains("user: Summarize this workspace.") == true)
    }

    func testMCPToolCallRejectsUnadvertisedTools() async throws {
        let call = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: """
            {"serverID":"mcp_server:filesystem","toolName":"delete_everything","arguments":{}}
            """
        )
        let setup = try makeConfiguredMCPProject(
            runner: AgentRunner(llm: FixedToolLLMClient(call: call)),
            callText: "should not run"
        )

        XCTAssertTrue(setup.model.runWorkspaceCommand("mcp-start:mcp_server:filesystem", workspaceRoot: setup.root))
        setup.model.setDraft("run MCP delete_everything")
        await setup.model.submitComposer(workspaceRoot: setup.root)

        XCTAssertEqual(setup.model.selectedThread?.events.suffix(2).first?.kind, .toolFailed)
        XCTAssertEqual(
            setup.model.selectedThread?.messages.last?.content,
            "Command failed:\nMCP tool delete_everything was not advertised by mcp_server:filesystem."
        )
    }

    private func makeConfiguredMCPProject(
        runner: AgentRunner = AgentRunner(),
        callText: String? = nil,
        includeResourcesAndPrompts: Bool = false,
        resourceText: String? = nil,
        promptText: String? = nil
    ) throws -> (root: URL, model: QuillCodeWorkspaceModel) {
        let root = try makeQuillCodeTestDirectory()
        try writeMCPManifest(
            in: root,
            callText: callText,
            includeResourcesAndPrompts: includeResourcesAndPrompts,
            resourceText: resourceText,
            promptText: promptText
        )

        let model = QuillCodeWorkspaceModel(runner: runner)
        let projectID = model.addProject(path: root, name: "MCP Project")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)
        return (root, model)
    }

    private func writeMCPManifest(
        in root: URL,
        callText: String? = nil,
        includeResourcesAndPrompts: Bool = false,
        resourceText: String? = nil,
        promptText: String? = nil
    ) throws {
        let mcpDirectory = root.appendingPathComponent(".quillcode/mcp")
        try FileManager.default.createDirectory(at: mcpDirectory, withIntermediateDirectories: true)
        let server = try writeFixtureMCPServer(
            in: root,
            callText: callText,
            includeResourcesAndPrompts: includeResourcesAndPrompts,
            resourceText: resourceText,
            promptText: promptText
        )
        try #"{"id":"filesystem","name":"Filesystem MCP","command":""#
            .appending(server.path)
            .appending(#""}"#)
            .write(
                to: mcpDirectory.appendingPathComponent("filesystem.json"),
                atomically: true,
                encoding: .utf8
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
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}

private struct FixedToolLLMClient: LLMClient {
    var call: ToolCall

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        .tool(call)
    }
}

private final class ToolDefinitionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedTools: [ToolDefinition] = []

    var tools: [ToolDefinition] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTools
    }

    func record(_ tools: [ToolDefinition]) {
        lock.lock()
        recordedTools = tools
        lock.unlock()
    }
}

private struct RecordingLLMClient: LLMClient {
    var recorder: ToolDefinitionRecorder

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        recorder.record(tools)
        return .say("Recorded tool definitions.")
    }
}
