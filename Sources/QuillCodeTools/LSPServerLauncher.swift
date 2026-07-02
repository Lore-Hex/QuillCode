import Foundation

/// A launched language-server process: the transport to talk to it, plus a handle to observe/kill
/// the underlying process. `isRunning` lets the session manager detect a crash; `terminate` tears it
/// down on shutdown or restart.
public struct LSPLaunchedServer: Sendable {
    public var transport: LSPTransport
    public var process: any LSPProcessControlling

    public init(transport: LSPTransport, process: any LSPProcessControlling) {
        self.transport = transport
        self.process = process
    }
}

/// Observable/terminable handle to a server process. Behind a protocol so a test can supply a fake
/// process that pairs with an in-memory transport.
public protocol LSPProcessControlling: AnyObject, Sendable {
    var isRunning: Bool { get }
    func terminate()
}

/// Spawns a language server and returns a stdio transport wired to it. Behind a protocol so the
/// session manager can be tested with a launcher that hands back a scripted transport and a fake
/// process, never touching a real subprocess.
public protocol LSPServerLaunching: Sendable {
    func launch(executable: String, arguments: [String], workspaceRoot: URL) throws -> LSPLaunchedServer
}

/// Production launcher: `Foundation.Process` with stdin/stdout pipes wired to an `LSPStdioTransport`,
/// stderr drained so a chatty server cannot fill and block its pipe. Mirrors the MCP server launcher.
public struct DefaultLSPServerLauncher: LSPServerLaunching {
    public init() {}

    public func launch(executable: String, arguments: [String], workspaceRoot: URL) throws -> LSPLaunchedServer {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workspaceRoot

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let controller = LSPFoundationProcessController(process: process, standardError: standardError)
        do {
            try process.run()
        } catch {
            throw LSPError.serverUnavailable("failed to launch \(executable): \(error.localizedDescription)")
        }
        // Drain stderr in the background; a full stderr pipe would otherwise deadlock the server.
        standardError.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        let transport = LSPStdioTransport(
            input: standardInput.fileHandleForWriting,
            output: standardOutput.fileHandleForReading
        )
        return LSPLaunchedServer(transport: transport, process: controller)
    }
}

private final class LSPFoundationProcessController: LSPProcessControlling, @unchecked Sendable {
    private let process: Process
    private let standardError: Pipe

    init(process: Process, standardError: Pipe) {
        self.process = process
        self.standardError = standardError
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        standardError.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }
}
