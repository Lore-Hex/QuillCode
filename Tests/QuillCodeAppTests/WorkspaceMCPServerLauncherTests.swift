import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceMCPServerLauncherTests: XCTestCase {
    func testLaunchRequestValidatesManifestAndCopiesLaunchFields() throws {
        let root = URL(fileURLWithPath: "/tmp/quill-workspace")
        let manifest = mcpManifest(
            launchExecutable: "mcp-server",
            launchArguments: ["--root", "."]
        )

        let request = try WorkspaceMCPLaunchRequest.make(
            manifest: manifest,
            workspaceRoot: root
        )

        XCTAssertEqual(request.serverID, "mcp_server:filesystem")
        XCTAssertEqual(request.command, "mcp-server")
        XCTAssertEqual(request.arguments, ["--root", "."])
        XCTAssertEqual(request.workspaceRoot, root)
    }

    func testLaunchRequestRejectsDisabledOrMissingCommandManifests() {
        let root = URL(fileURLWithPath: "/tmp/quill-workspace")

        XCTAssertThrowsError(try WorkspaceMCPLaunchRequest.make(
            manifest: mcpManifest(isEnabled: false, launchExecutable: "mcp-server"),
            workspaceRoot: root
        )) { error in
            XCTAssertEqual(error as? WorkspaceMCPLaunchRequestError, .disabled(name: "Filesystem MCP"))
            XCTAssertEqual(error.localizedDescription, "Filesystem MCP is disabled.")
        }

        XCTAssertThrowsError(try WorkspaceMCPLaunchRequest.make(
            manifest: mcpManifest(launchExecutable: nil),
            workspaceRoot: root
        )) { error in
            XCTAssertEqual(error as? WorkspaceMCPLaunchRequestError, .missingCommand(name: "Filesystem MCP"))
            XCTAssertEqual(error.localizedDescription, "Filesystem MCP does not define a launch command.")
        }
    }

    func testProcessLaunchConfigurationResolvesPathAndPathLookupCommands() {
        let root = URL(fileURLWithPath: "/tmp/quill-workspace")

        let absolute = WorkspaceMCPProcessLaunchConfiguration.resolve(
            command: "/opt/quill/mcp",
            arguments: ["--json"],
            workspaceRoot: root
        )
        let relative = WorkspaceMCPProcessLaunchConfiguration.resolve(
            command: "bin/mcp",
            arguments: ["--root", "."],
            workspaceRoot: root
        )
        let pathLookup = WorkspaceMCPProcessLaunchConfiguration.resolve(
            command: "quill-mcp",
            arguments: ["--root", "."],
            workspaceRoot: root
        )

        XCTAssertEqual(absolute.executableURL.path, "/opt/quill/mcp")
        XCTAssertEqual(absolute.arguments, ["--json"])
        XCTAssertEqual(relative.executableURL.path, "/tmp/quill-workspace/bin/mcp")
        XCTAssertEqual(relative.arguments, ["--root", "."])
        XCTAssertEqual(pathLookup.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(pathLookup.arguments, ["quill-mcp", "--root", "."])
    }

    func testExecutionOverrideUsesSessionProtocolWithDefaultTimeouts() async throws {
        let session = FakeWorkspaceMCPSession()
        let executionOverride = try XCTUnwrap(WorkspaceMCPRuntime.executionOverride(
            sessions: ["fs": session],
            summaries: ["fs": MCPServerProbeSummary(toolNames: ["read_file"])]
        ))

        let maybeResult = await executionOverride(
            ToolCall(
                name: ToolDefinition.mcpCall.name,
                argumentsJSON: """
                {
                  "serverID": "fs",
                  "toolName": "read_file",
                  "arguments": { "path": "README.md" }
                }
                """
            ),
            URL(fileURLWithPath: "/tmp/quill-workspace")
        )
        let result = try XCTUnwrap(maybeResult)

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.stdout, "called read_file")
        XCTAssertEqual(session.lastToolArgumentsJSON, #"{"path":"README.md"}"#)
        XCTAssertEqual(session.lastToolTimeout, 10.0)
    }

    private func mcpManifest(
        isEnabled: Bool = true,
        launchExecutable: String?,
        launchArguments: [String]? = nil
    ) -> ProjectExtensionManifest {
        ProjectExtensionManifest(
            id: "mcp_server:filesystem",
            kind: .mcpServer,
            name: "Filesystem MCP",
            relativePath: ".quillcode/mcp/filesystem.json",
            isEnabled: isEnabled,
            transport: .stdio,
            launchExecutable: launchExecutable,
            launchCommand: launchExecutable,
            launchArguments: launchArguments
        )
    }
}

private final class FakeWorkspaceMCPSession: WorkspaceMCPSession, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedToolArgumentsJSON: String?
    private var recordedToolTimeout: TimeInterval?

    var lastToolArgumentsJSON: String? {
        lock.locked { recordedToolArgumentsJSON }
    }

    var lastToolTimeout: TimeInterval? {
        lock.locked { recordedToolTimeout }
    }

    func probe(timeout: TimeInterval) throws -> MCPServerProbeResult {
        MCPServerProbeResult(toolNames: ["read_file"])
    }

    func callTool(
        toolName: String,
        argumentsJSON: String,
        timeout: TimeInterval
    ) throws -> ToolResult {
        lock.locked {
            recordedToolArgumentsJSON = argumentsJSON
            recordedToolTimeout = timeout
        }
        return ToolResult(ok: true, stdout: "called \(toolName)")
    }

    func readResource(uri: String, timeout: TimeInterval) throws -> ToolResult {
        ToolResult(ok: true, stdout: uri)
    }

    func getPrompt(name: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult {
        ToolResult(ok: true, stdout: name)
    }
}

private extension NSLock {
    func locked<T>(_ work: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try work()
    }
}
