import Foundation
import QuillCodeCore
import QuillCodeTools

/// Adapts the remote `MCPHTTPProber` to the `WorkspaceMCPSession` protocol so remote MCP servers
/// expose tools/resources/prompts exactly like stdio ones. Marshals the prober's typed errors
/// into the same `MCPProbeError`/`ToolResult` surface the runtime already understands.
struct WorkspaceMCPRemoteSession: WorkspaceMCPSession {
    let prober: MCPHTTPProber

    func probe(timeout: TimeInterval) throws -> MCPServerProbeResult {
        try prober.probe(timeout: timeout)
    }

    func callTool(toolName: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult {
        try prober.callTool(toolName: toolName, argumentsJSON: argumentsJSON, timeout: timeout)
    }

    func readResource(uri: String, timeout: TimeInterval) throws -> ToolResult {
        try prober.readResource(uri: uri, timeout: timeout)
    }

    func getPrompt(name: String, argumentsJSON: String, timeout: TimeInterval) throws -> ToolResult {
        try prober.getPrompt(name: name, argumentsJSON: argumentsJSON, timeout: timeout)
    }
}

/// A "process" that owns no OS process — a remote MCP connection is a network session, not a
/// child process. Reports itself as running until torn down so the runtime's lifecycle
/// bookkeeping (which was written for stdio child processes) treats a remote server uniformly.
final class WorkspaceMCPRemoteConnectionController: WorkspaceMCPProcessControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var running = true

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    func terminate() {
        lock.lock()
        running = false
        lock.unlock()
    }

    // No stdio pipes to manage for a remote connection.
    func clearReadabilityHandlers() {}
    func startDrainingStandardError() {}
}
