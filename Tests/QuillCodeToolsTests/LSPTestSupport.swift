import Foundation
@testable import QuillCodeTools

/// A deterministic in-memory `LSPTransport` for tests: the test writes framed JSON-RPC bytes the
/// "server" will emit, and the client reads them through `receive`. `send` captures every outbound
/// frame so a test can assert on the requests the client made. No process, no pipes, no real
/// language server — the whole client runs in-process and deterministically.
final class ScriptedLSPTransport: LSPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var inbound = Data()
    private var closed = false
    private(set) var sentMessages: [[String: Any]] = []

    /// Queues one server->client message (encoded with Content-Length framing).
    func enqueue(_ object: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? LSPMessageCodec.encode(object) {
            inbound.append(data)
        }
    }

    /// Queues a JSON-RPC response for a request id.
    func enqueueResponse(id: Int, result: Any) {
        enqueue(["jsonrpc": "2.0", "id": id, "result": result])
    }

    /// Queues a JSON-RPC error response for a request id.
    func enqueueError(id: Int, code: Int, message: String) {
        enqueue(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    /// Queues a `publishDiagnostics` notification.
    func enqueueDiagnostics(uri: String, diagnostics: [[String: Any]]) {
        enqueue([
            "jsonrpc": "2.0",
            "method": "textDocument/publishDiagnostics",
            "params": ["uri": uri, "diagnostics": diagnostics]
        ])
    }

    /// Appends raw bytes directly (for framing/partial-frame tests).
    func enqueueRaw(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        inbound.append(data)
    }

    /// Simulates the server exiting: `receive` returns `nil` (EOF) once the buffer is drained.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        closed = true
    }

    func send(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        var buffer = data
        while let message = try? LSPMessageCodec.nextMessage(from: &buffer),
              let object = try? LSPMessageCodec.decode(message) {
            sentMessages.append(object)
        }
    }

    func receive(timeout: TimeInterval) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if !inbound.isEmpty {
            let chunk = inbound
            inbound.removeAll()
            return chunk
        }
        if closed { return nil } // EOF after draining
        return Data() // no data yet — a plain timeout
    }
}

/// A canned server behavior that auto-responds to requests the way a real server would, so a test
/// can drive an `LSPClient` end to end without hand-queuing every response. It inspects each sent
/// request and enqueues a matching response on the transport.
final class StubLanguageServer: LSPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var inbound = Data()
    private var closed = false
    private(set) var transportClosed = false

    /// Result to return for `initialize` (the `capabilities` object lives inside).
    var initializeResult: [String: Any] = ["capabilities": ["documentFormattingProvider": true]]
    /// Result for `textDocument/definition`, `references`, etc., keyed by method.
    var resultsByMethod: [String: Any] = [:]
    /// Diagnostics to publish for a URI right after `didSave` for it.
    var diagnosticsOnSave: [String: [[String: Any]]] = [:]

    func send(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        var buffer = data
        while let message = try? LSPMessageCodec.nextMessage(from: &buffer),
              let object = try? LSPMessageCodec.decode(message) {
            handle(object)
        }
    }

    func receive(timeout: TimeInterval) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if !inbound.isEmpty {
            let chunk = inbound
            inbound.removeAll()
            return chunk
        }
        if closed { return nil }
        return Data()
    }

    func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true
        transportClosed = true
    }

    private func handle(_ object: [String: Any]) {
        let method = object["method"] as? String
        if let id = LSPJSON.int(object["id"]), let method {
            let result: Any
            if method == "initialize" {
                result = initializeResult
            } else {
                result = resultsByMethod[method] ?? NSNull()
            }
            enqueue(["jsonrpc": "2.0", "id": id, "result": result])
        }
        // On save, publish the canned diagnostics for the saved URI.
        if method == "textDocument/didSave",
           let params = object["params"] as? [String: Any],
           let doc = params["textDocument"] as? [String: Any],
           let uri = doc["uri"] as? String,
           let diagnostics = diagnosticsOnSave[uri] {
            enqueue([
                "jsonrpc": "2.0",
                "method": "textDocument/publishDiagnostics",
                "params": ["uri": uri, "diagnostics": diagnostics]
            ])
        }
    }

    private func enqueue(_ object: [String: Any]) {
        if let data = try? LSPMessageCodec.encode(object) {
            inbound.append(data)
        }
    }
}

/// A launcher that hands back a pre-built transport + a fake process, so `LSPSessionManager` can be
/// tested without spawning anything. The `isRunning` flag is mutable so a test can simulate a crash.
final class StubLSPServerLauncher: LSPServerLaunching, @unchecked Sendable {
    final class FakeProcess: LSPProcessControlling, @unchecked Sendable {
        var running: Bool
        private(set) var terminated = false
        init(running: Bool = true) { self.running = running }
        var isRunning: Bool { running }
        func terminate() { terminated = true; running = false }
    }

    private let makeTransport: @Sendable () -> LSPTransport
    /// Set to a non-nil error to make the next launch throw (simulating a failed spawn).
    var launchError: LSPError?
    private(set) var launchCount = 0
    private(set) var lastProcess: FakeProcess?

    init(makeTransport: @escaping @Sendable () -> LSPTransport) {
        self.makeTransport = makeTransport
    }

    func launch(executable: String, arguments: [String], workspaceRoot: URL) throws -> LSPLaunchedServer {
        launchCount += 1
        if let launchError { throw launchError }
        let process = FakeProcess()
        lastProcess = process
        return LSPLaunchedServer(transport: makeTransport(), process: process)
    }
}

/// A command locator that reports a fixed availability, for testing the missing-server path.
struct StubCommandLocator: LSPCommandLocating {
    let resolvedPath: String?
    func locate(command: String) -> String? { resolvedPath }
}
