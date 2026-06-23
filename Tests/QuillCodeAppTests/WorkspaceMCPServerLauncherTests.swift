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

    func testExecutionOverrideUsesSessionProtocolWithBoundedTimeouts() async throws {
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

    func testRuntimeUsesInjectedLauncherAndMarksReadyAfterProbe() {
        let process = FakeWorkspaceMCPProcess()
        let session = FakeWorkspaceMCPSession(
            probeResult: MCPServerProbeResult(
                serverName: "Fixture MCP",
                toolNames: ["read_file"]
            )
        )
        let launcher = FakeWorkspaceMCPServerLauncher(process: process, session: session)
        let runtime = WorkspaceMCPRuntime(launcher: launcher)
        var extensions = ExtensionsState()

        let result = runtime.startServer(
            manifest: mcpManifest(launchExecutable: "quill-mcp", launchArguments: ["--root", "."]),
            workspaceRoot: URL(fileURLWithPath: "/tmp/quill-workspace"),
            extensions: &extensions,
            onTermination: { _, _ in }
        )

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.notice, "MCP server Filesystem MCP ready (1 tool: read_file)")
        XCTAssertEqual(extensions.mcpServerStatuses["mcp_server:filesystem"], .ready)
        XCTAssertEqual(extensions.mcpServerProbeSummaries["mcp_server:filesystem"]?.serverName, "Fixture MCP")
        XCTAssertEqual(launcher.lastRequest?.command, "quill-mcp")
        XCTAssertEqual(launcher.lastRequest?.arguments, ["--root", "."])
        XCTAssertTrue(process.didStartDrainingStandardError)
        XCTAssertFalse(process.didTerminate)
    }

    func testRuntimeReportsInjectedLauncherFailure() {
        let launcher = FakeWorkspaceMCPServerLauncher(error: FakeMCPError.launchFailed)
        let runtime = WorkspaceMCPRuntime(launcher: launcher)
        var extensions = ExtensionsState()

        let result = runtime.startServer(
            manifest: mcpManifest(launchExecutable: "quill-mcp"),
            workspaceRoot: URL(fileURLWithPath: "/tmp/quill-workspace"),
            extensions: &extensions,
            onTermination: { _, _ in }
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.errorMessage, "Could not start Filesystem MCP: launcher failed")
        XCTAssertEqual(result.notice, "MCP server Filesystem MCP failed to start")
        XCTAssertEqual(result.agentStatus, "Failed")
        XCTAssertEqual(extensions.mcpServerStatuses["mcp_server:filesystem"], .failed)
    }

    func testRuntimeTerminatesInjectedProcessWhenProbeFails() {
        let process = FakeWorkspaceMCPProcess()
        let session = FakeWorkspaceMCPSession(probeError: FakeMCPError.probeFailed)
        let launcher = FakeWorkspaceMCPServerLauncher(process: process, session: session)
        let runtime = WorkspaceMCPRuntime(launcher: launcher)
        var extensions = ExtensionsState()

        let result = runtime.startServer(
            manifest: mcpManifest(launchExecutable: "quill-mcp"),
            workspaceRoot: URL(fileURLWithPath: "/tmp/quill-workspace"),
            extensions: &extensions,
            onTermination: { _, _ in }
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.errorMessage, "Could not verify Filesystem MCP: probe failed")
        XCTAssertEqual(result.notice, "MCP server Filesystem MCP probe failed: probe failed")
        XCTAssertEqual(result.agentStatus, "Failed")
        XCTAssertEqual(extensions.mcpServerStatuses["mcp_server:filesystem"], .failed)
        XCTAssertEqual(
            extensions.mcpServerProbeSummaries["mcp_server:filesystem"]?.errorMessage,
            "probe failed"
        )
        XCTAssertTrue(process.didClearReadabilityHandlers)
        XCTAssertTrue(process.didTerminate)
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
    private let probeResult: MCPServerProbeResult
    private let probeError: Error?
    private var recordedToolArgumentsJSON: String?
    private var recordedToolTimeout: TimeInterval?

    init(
        probeResult: MCPServerProbeResult = MCPServerProbeResult(toolNames: ["read_file"]),
        probeError: Error? = nil
    ) {
        self.probeResult = probeResult
        self.probeError = probeError
    }

    var lastToolArgumentsJSON: String? {
        lock.locked { recordedToolArgumentsJSON }
    }

    var lastToolTimeout: TimeInterval? {
        lock.locked { recordedToolTimeout }
    }

    func probe(timeout: TimeInterval) throws -> MCPServerProbeResult {
        if let probeError {
            throw probeError
        }
        return probeResult
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

private final class FakeWorkspaceMCPProcess: WorkspaceMCPProcessControlling, @unchecked Sendable {
    private(set) var didTerminate = false
    private(set) var didClearReadabilityHandlers = false
    private(set) var didStartDrainingStandardError = false

    var isRunning: Bool {
        !didTerminate
    }

    func terminate() {
        didTerminate = true
    }

    func clearReadabilityHandlers() {
        didClearReadabilityHandlers = true
    }

    func startDrainingStandardError() {
        didStartDrainingStandardError = true
    }
}

private final class FakeWorkspaceMCPServerLauncher: WorkspaceMCPServerLaunching, @unchecked Sendable {
    private let process: FakeWorkspaceMCPProcess?
    private let session: FakeWorkspaceMCPSession?
    private let error: Error?
    private(set) var lastRequest: WorkspaceMCPLaunchRequest?

    init(process: FakeWorkspaceMCPProcess, session: FakeWorkspaceMCPSession) {
        self.process = process
        self.session = session
        self.error = nil
    }

    init(error: Error) {
        self.process = nil
        self.session = nil
        self.error = error
    }

    func launch(
        request: WorkspaceMCPLaunchRequest,
        onTermination: @escaping @MainActor @Sendable (_ id: String, _ terminationStatus: Int32) -> Void
    ) throws -> WorkspaceMCPLaunchedServer {
        lastRequest = request
        if let error {
            throw error
        }
        guard let process, let session else {
            throw FakeMCPError.launchFailed
        }
        return WorkspaceMCPLaunchedServer(
            process: process,
            session: session
        )
    }
}

private enum FakeMCPError: Error, LocalizedError {
    case launchFailed
    case probeFailed

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            return "launcher failed"
        case .probeFailed:
            return "probe failed"
        }
    }
}

private extension NSLock {
    func locked<T>(_ work: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try work()
    }
}
