import Foundation
import QuillCodeCore
import QuillCodeTools

protocol WorkspaceMCPSession: Sendable {
    func probe(timeout: TimeInterval) throws -> MCPServerProbeResult
    func callTool(toolName: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult
    func readResource(uri: String, timeout: TimeInterval) throws -> ToolResult
    func getPrompt(name: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult
}

extension MCPStdioProber: WorkspaceMCPSession {}

extension WorkspaceMCPSession {
    func callTool(toolName: String, argumentsJSON: String) throws -> ToolResult {
        try callTool(toolName: toolName, argumentsJSON: argumentsJSON, timeout: 10.0)
    }

    func readResource(uri: String) throws -> ToolResult {
        try readResource(uri: uri, timeout: 10.0)
    }

    func getPrompt(name: String, argumentsJSON: String) throws -> ToolResult {
        try getPrompt(name: name, argumentsJSON: argumentsJSON, timeout: 10.0)
    }
}

protocol WorkspaceMCPProcessControlling: AnyObject, Sendable {
    var isRunning: Bool { get }
    func terminate()
    func clearReadabilityHandlers()
    func startDrainingStandardError()
}

struct WorkspaceMCPLaunchRequest: Sendable, Hashable {
    var serverID: String
    var command: String
    var arguments: [String]
    var workspaceRoot: URL

    static func make(
        manifest: ProjectExtensionManifest,
        workspaceRoot: URL
    ) throws -> WorkspaceMCPLaunchRequest {
        guard manifest.isEnabled else {
            throw WorkspaceMCPLaunchRequestError.disabled(name: manifest.name)
        }
        guard let command = manifest.launchExecutable,
              !command.isEmpty
        else {
            throw WorkspaceMCPLaunchRequestError.missingCommand(name: manifest.name)
        }
        return WorkspaceMCPLaunchRequest(
            serverID: manifest.id,
            command: command,
            arguments: manifest.launchArguments ?? [],
            workspaceRoot: workspaceRoot
        )
    }
}

enum WorkspaceMCPLaunchRequestError: Error, LocalizedError, Equatable {
    case disabled(name: String)
    case missingCommand(name: String)

    var errorDescription: String? {
        switch self {
        case .disabled(let name):
            return "\(name) is disabled."
        case .missingCommand(let name):
            return "\(name) does not define a launch command."
        }
    }
}

struct WorkspaceMCPLaunchedServer: Sendable {
    var process: any WorkspaceMCPProcessControlling
    var session: any WorkspaceMCPSession
}

protocol WorkspaceMCPServerLaunching: Sendable {
    func launch(
        request: WorkspaceMCPLaunchRequest,
        onTermination: @escaping @MainActor @Sendable (_ id: String, _ terminationStatus: Int32) -> Void
    ) throws -> WorkspaceMCPLaunchedServer
}

struct WorkspaceMCPProcessLaunchConfiguration: Sendable, Hashable {
    var executableURL: URL
    var arguments: [String]

    static func resolve(
        command: String,
        arguments: [String],
        workspaceRoot: URL
    ) -> WorkspaceMCPProcessLaunchConfiguration {
        if command.contains("/") {
            let commandURL = command.hasPrefix("/")
                ? URL(fileURLWithPath: command)
                : workspaceRoot.appendingPathComponent(command)
            return WorkspaceMCPProcessLaunchConfiguration(
                executableURL: commandURL,
                arguments: arguments
            )
        }

        return WorkspaceMCPProcessLaunchConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [command] + arguments
        )
    }
}

struct DefaultWorkspaceMCPServerLauncher: WorkspaceMCPServerLaunching {
    func launch(
        request: WorkspaceMCPLaunchRequest,
        onTermination: @escaping @MainActor @Sendable (_ id: String, _ terminationStatus: Int32) -> Void
    ) throws -> WorkspaceMCPLaunchedServer {
        let process = Process()
        process.currentDirectoryURL = request.workspaceRoot

        let launch = WorkspaceMCPProcessLaunchConfiguration.resolve(
            command: request.command,
            arguments: request.arguments,
            workspaceRoot: request.workspaceRoot
        )
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let controller = WorkspaceMCPFoundationProcessController(
            process: process,
            standardInput: standardInput,
            standardOutput: standardOutput,
            standardError: standardError
        )

        process.terminationHandler = { process in
            controller.clearReadabilityHandlers()
            Task { @MainActor in
                onTermination(request.serverID, process.terminationStatus)
            }
        }

        try process.run()

        let session = MCPStdioProber(
            standardInput: standardInput.fileHandleForWriting,
            standardOutput: standardOutput.fileHandleForReading
        )
        return WorkspaceMCPLaunchedServer(process: controller, session: session)
    }
}

private final class WorkspaceMCPFoundationProcessController: WorkspaceMCPProcessControlling, @unchecked Sendable {
    private let process: Process
    private let standardInput: Pipe
    private let standardOutput: Pipe
    private let standardError: Pipe

    init(
        process: Process,
        standardInput: Pipe,
        standardOutput: Pipe,
        standardError: Pipe
    ) {
        self.process = process
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        process.terminate()
    }

    func clearReadabilityHandlers() {
        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
    }

    func startDrainingStandardError() {
        standardError.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
    }
}
