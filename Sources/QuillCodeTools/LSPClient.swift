import Foundation

/// A synchronous JSON-RPC 2.0 client for a single language-server process, speaking over an injected
/// `LSPTransport`. Modeled on `MCPStdioProber`: one `NSLock` serializes every exchange, request ids
/// increment monotonically, and responses are correlated by id with a wall-clock deadline so a
/// silent server times out instead of hanging the agent.
///
/// The client is deliberately *blocking* — the tool router that drives it is itself synchronous, and
/// LSP exchanges (definition, diagnostics) are short. Read loops always honor a deadline and treat
/// EOF as a terminal `serverClosed` error, so there is no path that spins forever.
///
/// Notifications the server pushes unsolicited (chiefly `textDocument/publishDiagnostics`) are
/// drained off the same stream while waiting for a response and stashed per-URI, so a later
/// `diagnostics(for:)` call reads the latest set without another round trip.
public final class LSPClient: @unchecked Sendable {
    private let transport: LSPTransport
    private let lock = NSLock()

    private var buffer = Data()
    private var nextID = 1
    private var initialized = false
    private var latestDiagnostics: [String: [LSPDiagnostic]] = [:]
    /// Set once a codec/decode error is hit on the read stream: the framing is desynced and the corrupt
    /// bytes cannot be safely resynced, so the whole client is dead. The session manager checks this
    /// (via `isHealthy`) and relaunches, rather than reusing a permanently-wedged client.
    private var poisoned = false
    /// Capabilities the server advertised at initialize, so we can skip requests it does not support
    /// (e.g. formatting) instead of paying a round trip for a guaranteed "method not found".
    private(set) var serverCapabilities: [String: Any] = [:]

    public init(transport: LSPTransport) {
        self.transport = transport
    }

    /// Whether the client's read stream is still in sync. Once a malformed frame corrupts the framing
    /// this is `false` forever — the caller must drop and relaunch the session.
    public var isHealthy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !poisoned
    }

    // MARK: Handshake

    /// Performs the `initialize` / `initialized` handshake, advertising the workspace root and the
    /// capabilities we actually use. Safe to call once; a second call is a no-op.
    @discardableResult
    public func initialize(workspaceRoot: URL, timeout: TimeInterval = 10.0) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard !initialized else { return serverCapabilities }

        let deadline = Date().addingTimeInterval(timeout)
        let id = nextRequestID()
        let rootURI = LSPURI.from(path: workspaceRoot.standardizedFileURL.path)
        try writeRequest(id: id, method: "initialize", params: [
            "processId": Int(ProcessInfo.processInfo.processIdentifier),
            "rootUri": rootURI,
            "workspaceFolders": [["uri": rootURI, "name": workspaceRoot.lastPathComponent]],
            "capabilities": clientCapabilities(),
            "clientInfo": ["name": "QuillCode", "version": "0.1.0"]
        ])
        let response = try awaitResponse(id: id, deadline: deadline)
        let result = try resultObject(from: response)
        serverCapabilities = (result["capabilities"] as? [String: Any]) ?? [:]
        try writeNotification(method: "initialized", params: [:])
        initialized = true
        return serverCapabilities
    }

    /// Whether the server advertised `documentFormattingProvider`.
    public var supportsFormatting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return capabilityIsTrue(serverCapabilities["documentFormattingProvider"])
    }

    // MARK: Document lifecycle

    /// Announces a document to the server. `didOpen` must precede any request that references it, and
    /// resends on every write keep the server's view of the file current (`didChange` requires the
    /// server to track incremental state; a fresh `didOpen` with the full text is simpler and equally
    /// correct for our request/response usage).
    public func didOpen(path: String, text: String, languageID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeNotification(method: "textDocument/didOpen", params: [
            "textDocument": [
                "uri": LSPURI.from(path: path),
                "languageId": languageID,
                "version": 1,
                "text": text
            ]
        ])
    }

    /// Notifies the server the document was saved. Some servers only recompute diagnostics on save.
    public func didSave(path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeNotification(method: "textDocument/didSave", params: [
            "textDocument": ["uri": LSPURI.from(path: path)]
        ])
    }

    // MARK: Requests

    /// `textDocument/definition`.
    public func definition(path: String, line: Int, character: Int, timeout: TimeInterval = 5.0) throws -> [LSPLocation] {
        let result = try request(
            method: "textDocument/definition",
            params: positionParams(path: path, line: line, character: character),
            timeout: timeout
        )
        return LSPLocation.parseList(result)
    }

    /// `textDocument/references`.
    public func references(path: String, line: Int, character: Int, includeDeclaration: Bool = true, timeout: TimeInterval = 5.0) throws -> [LSPLocation] {
        var params = positionParams(path: path, line: line, character: character)
        params["context"] = ["includeDeclaration": includeDeclaration]
        let result = try request(method: "textDocument/references", params: params, timeout: timeout)
        return LSPLocation.parseList(result)
    }

    /// `textDocument/hover`, flattened to plain text.
    public func hover(path: String, line: Int, character: Int, timeout: TimeInterval = 5.0) throws -> String? {
        let result = try request(
            method: "textDocument/hover",
            params: positionParams(path: path, line: line, character: character),
            timeout: timeout
        )
        return LSPHoverText.extract(from: result)
    }

    /// `textDocument/documentSymbol` — the symbols defined in one file.
    public func documentSymbols(path: String, timeout: TimeInterval = 5.0) throws -> [LSPSymbol] {
        let result = try request(
            method: "textDocument/documentSymbol",
            params: ["textDocument": ["uri": LSPURI.from(path: path)]],
            timeout: timeout
        )
        return LSPSymbolParser.documentSymbols(from: result, uri: LSPURI.from(path: path))
    }

    /// `workspace/symbol` — project-wide symbol search by name.
    public func workspaceSymbols(query: String, timeout: TimeInterval = 5.0) throws -> [LSPSymbol] {
        let result = try request(method: "workspace/symbol", params: ["query": query], timeout: timeout)
        return LSPSymbolParser.workspaceSymbols(from: result)
    }

    /// `textDocument/formatting`. Returns the ordered text edits the server would apply, or an empty
    /// array when the file is already formatted. `nil` capability check is the caller's job via
    /// `supportsFormatting`.
    public func formatting(path: String, tabSize: Int = 4, insertSpaces: Bool = true, timeout: TimeInterval = 5.0) throws -> [LSPTextEdit] {
        let result = try request(method: "textDocument/formatting", params: [
            "textDocument": ["uri": LSPURI.from(path: path)],
            "options": ["tabSize": tabSize, "insertSpaces": insertSpaces]
        ], timeout: timeout)
        return LSPTextEdit.parseList(result)
    }

    /// The most recent diagnostics the server published for a file, draining any pending
    /// notifications up to `waitFor` first so freshly-computed diagnostics after a save are captured.
    ///
    /// To keep the after-write latency low, once the edited file receives a *fresh* publish (one that
    /// arrived during this wait) we drain only a short additional grace window for project-wide
    /// diagnostics that typically follow, rather than always blocking the full `waitFor`.
    public func diagnostics(for path: String, waitFor: TimeInterval = 1.5) -> [LSPDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        let uri = Self.canonicalKey(forPath: path)
        let deadline = Date().addingTimeInterval(waitFor)
        // A `nil` here means "no publish yet"; a value that changes marks a fresh publish for the file.
        let baseline = latestDiagnostics[uri]
        var graceDeadline: Date?
        // Pump the stream for pending publishDiagnostics without blocking on a response id.
        while Date() < deadline {
            do {
                guard try pumpOnce(deadline: deadline) else { break }
            } catch {
                break // stream error: return whatever we have; never propagate into a write result
            }
            // Once the edited file gets a fresh publish, allow a brief grace window for follow-on
            // (cross-file) diagnostics, then stop early instead of waiting out the full deadline.
            if graceDeadline == nil, freshlyPublished(uri, baseline: baseline) {
                graceDeadline = min(deadline, Date().addingTimeInterval(0.3))
            }
            if let graceDeadline, Date() >= graceDeadline { break }
        }
        return latestDiagnostics[uri] ?? []
    }

    /// All diagnostics currently known, keyed by absolute file path. Used by diagnostics-after-write
    /// to report *project-wide* breakage, not just the edited file.
    public func allDiagnostics() -> [String: [LSPDiagnostic]] {
        lock.lock()
        defer { lock.unlock() }
        // Keys are already canonical filesystem paths (see handleServerMessage).
        return latestDiagnostics
    }

    /// Attempts a clean `shutdown`/`exit` handshake, then closes the transport so the child receives
    /// EOF on stdin and its pipe fds are released. Best-effort — a crashed server just gets its process
    /// killed by the session manager, and `closeTransport()` still frees our fds.
    public func shutdown(timeout: TimeInterval = 2.0) {
        lock.lock()
        defer { lock.unlock() }
        if initialized {
            let id = nextRequestID()
            try? writeRequest(id: id, method: "shutdown", params: [:])
            _ = try? awaitResponse(id: id, deadline: Date().addingTimeInterval(timeout))
            try? writeNotification(method: "exit", params: [:])
            initialized = false
        }
        transport.close()
    }

    /// Closes the transport without the handshake — for a session being torn down because its process
    /// already died (a clean shutdown would just time out). Releases our stdin/stdout fds.
    public func closeTransport() {
        lock.lock()
        defer { lock.unlock() }
        initialized = false
        transport.close()
    }

    // MARK: Core request/response

    private func request(method: String, params: [String: Any], timeout: TimeInterval) throws -> Any? {
        lock.lock()
        defer { lock.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        let id = nextRequestID()
        try writeRequest(id: id, method: method, params: params)
        let response = try awaitResponse(id: id, deadline: deadline)
        return try resultValue(from: response)
    }

    /// Reads framed messages until the response for `id` arrives or the deadline passes. Server-push
    /// notifications seen along the way are handled (diagnostics stashed) and skipped. EOF is a
    /// terminal error; a timeout with no matching response is `LSPError.timeout`.
    private func awaitResponse(id: Int, deadline: Date) throws -> [String: Any] {
        while Date() < deadline {
            if let message = try nextBufferedMessage() {
                // A JSON-RPC RESPONSE has an `id` and no `method`. A server->client REQUEST also carries
                // an `id` (from a SEPARATE id space that can numerically collide with ours), so match on
                // "has our id AND is not a request" — otherwise a `workspace/configuration` request with
                // id == ours would be mistaken for our response and yield an empty/garbage result.
                if message["method"] == nil, let responseID = LSPJSON.int(message["id"]), responseID == id {
                    return message
                }
                handleServerMessage(message)
                continue
            }
            guard try fillBuffer(deadline: deadline) else {
                throw LSPError.serverClosed("server closed the connection before responding to \(id)")
            }
        }
        throw LSPError.timeout("no response to request \(id) within the deadline")
    }

    /// One non-blocking step of the read pump: parse a buffered message if present, else try to read
    /// more. Returns `false` on EOF so a draining loop can stop. Used by `diagnostics(for:)`.
    private func pumpOnce(deadline: Date) throws -> Bool {
        if let message = try nextBufferedMessage() {
            handleServerMessage(message)
            return true
        }
        return try fillBuffer(deadline: deadline)
    }

    private func nextBufferedMessage() throws -> [String: Any]? {
        do {
            guard let data = try LSPMessageCodec.nextMessage(from: &buffer) else { return nil }
            return try LSPMessageCodec.decode(data)
        } catch {
            // A codec/decode failure means the framing is out of sync — the corrupt bytes are still at
            // the front of the buffer and every future read would re-hit them, permanently wedging the
            // session. Per LSPMessageCodec's contract, treat the stream as corrupt: mark this client
            // poisoned so the session manager evicts + relaunches it, and stop parsing.
            poisoned = true
            throw error
        }
    }

    /// Reads more bytes into the buffer, honoring the deadline. Returns `false` on EOF, `true`
    /// otherwise (including an empty read on timeout, so the caller re-checks its own deadline).
    private func fillBuffer(deadline: Date) throws -> Bool {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return true }
        guard let data = try transport.receive(timeout: min(remaining, 0.25)) else {
            return false // EOF
        }
        if !data.isEmpty { buffer.append(data) }
        return true
    }

    /// Dispatches an inbound server-originated message. We only act on `publishDiagnostics`; other
    /// server requests (e.g. `workspace/configuration`) are ignored — sourcekit-lsp tolerates a
    /// client that does not answer optional server->client requests within our short-lived exchanges.
    private func handleServerMessage(_ message: [String: Any]) {
        guard message["method"] as? String == "textDocument/publishDiagnostics",
              let params = message["params"] as? [String: Any],
              let uri = params["uri"] as? String
        else { return }
        let raw = (params["diagnostics"] as? [[String: Any]]) ?? []
        // Key by a canonical filesystem path, not the raw URI: a server may percent-encode or
        // symlink-resolve URIs differently than we construct them (e.g. /private/var vs /var on macOS),
        // and keying on the raw string would make `diagnostics(for:)` miss its own file.
        latestDiagnostics[Self.canonicalKey(forURI: uri)] = raw.compactMap { LSPDiagnostic.parse($0) }
    }

    /// Canonical, symlink-resolved key for a `file://` URI (or the raw URI if it is not a file URL),
    /// used so a diagnostics store keyed by the server's URI and a lookup keyed by our path agree.
    private static func canonicalKey(forURI uri: String) -> String {
        guard let path = LSPURI.path(from: uri) else { return uri }
        return canonicalKey(forPath: path)
    }

    /// Canonical, symlink-resolved key for a filesystem path.
    private static func canonicalKey(forPath path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func writeRequest(id: Int, method: String, params: [String: Any]) throws {
        try transport.send(try LSPMessageCodec.encode([
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ]))
    }

    private func writeNotification(method: String, params: [String: Any]) throws {
        try transport.send(try LSPMessageCodec.encode([
            "jsonrpc": "2.0", "method": method, "params": params
        ]))
    }

    private func resultObject(from response: [String: Any]) throws -> [String: Any] {
        (try resultValue(from: response) as? [String: Any]) ?? [:]
    }

    private func resultValue(from response: [String: Any]) throws -> Any? {
        if let error = response["error"] as? [String: Any] {
            throw LSPError.serverError(
                code: LSPJSON.int(error["code"]) ?? -1,
                message: (error["message"] as? String) ?? "unknown server error"
            )
        }
        return response["result"]
    }

    private func nextRequestID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    /// Whether `uri` has received a publish that differs from the `baseline` captured at the start of
    /// a diagnostics wait — i.e. the server just recomputed diagnostics for the edited file.
    private func freshlyPublished(_ uri: String, baseline: [LSPDiagnostic]?) -> Bool {
        guard let current = latestDiagnostics[uri] else { return false }
        return current != baseline
    }

    private func positionParams(path: String, line: Int, character: Int) -> [String: Any] {
        [
            "textDocument": ["uri": LSPURI.from(path: path)],
            "position": LSPPosition(line: line, character: character).wire
        ]
    }

    private func capabilityIsTrue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        // Servers may advertise a provider as an options object rather than a bare `true`.
        return value is [String: Any]
    }

    private func clientCapabilities() -> [String: Any] {
        [
            "textDocument": [
                "publishDiagnostics": ["relatedInformation": false],
                "definition": ["linkSupport": true],
                "references": [:],
                "hover": ["contentFormat": ["plaintext", "markdown"]],
                "documentSymbol": ["hierarchicalDocumentSymbolSupport": true],
                "formatting": [:]
            ],
            "workspace": ["symbol": [:]]
        ]
    }
}
