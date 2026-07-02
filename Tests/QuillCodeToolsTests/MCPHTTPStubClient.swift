import Foundation
@testable import QuillCodeTools

/// A deterministic in-memory `MCPHTTPClient` for tests. Matches requests by (method, path) or by
/// a caller-provided predicate and returns canned buffered responses or scripted SSE streams. No
/// real network. Records every request for assertions.
final class MCPHTTPStubClient: MCPHTTPClient, @unchecked Sendable {
    struct Recorded: Sendable {
        var url: URL
        var method: String
        var headers: [String: String]
        var body: Data?
    }

    /// A handler returns either a buffered response or a streaming one.
    enum Reply {
        case response(MCPHTTPResponse)
        case stream(MCPHTTPStubStream)
    }

    private let lock = NSLock()
    private var performHandler: (@Sendable (MCPHTTPRequest) throws -> MCPHTTPResponse)?
    private var streamHandler: (@Sendable (MCPHTTPRequest) throws -> MCPHTTPStream)?
    private var recorded: [Recorded] = []

    var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func onPerform(_ handler: @escaping @Sendable (MCPHTTPRequest) throws -> MCPHTTPResponse) {
        lock.lock(); performHandler = handler; lock.unlock()
    }

    func onStream(_ handler: @escaping @Sendable (MCPHTTPRequest) throws -> MCPHTTPStream) {
        lock.lock(); streamHandler = handler; lock.unlock()
    }

    func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        record(request)
        lock.lock(); let handler = performHandler; lock.unlock()
        guard let handler else {
            throw MCPHTTPClientError.transport("no perform handler registered")
        }
        return try handler(request)
    }

    func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream {
        record(request)
        lock.lock(); let handler = streamHandler; lock.unlock()
        guard let handler else {
            throw MCPHTTPClientError.transport("no stream handler registered")
        }
        return try handler(request)
    }

    private func record(_ request: MCPHTTPRequest) {
        lock.lock()
        recorded.append(Recorded(
            url: request.url,
            method: request.method,
            headers: request.headers,
            body: request.body
        ))
        lock.unlock()
    }
}

/// A scripted `MCPHTTPStream`: fixed status/headers and a queue of body chunks delivered in order.
/// A final `nil` chunk signals clean end-of-stream. Throwing chunks simulate transport errors.
final class MCPHTTPStubStream: MCPHTTPStream, @unchecked Sendable {
    let statusCode: Int
    let headerFields: [String: String]

    private let lock = NSLock()
    private var chunks: [Result<Data?, MCPHTTPClientError>]
    private(set) var cancelled = false

    init(statusCode: Int, headerFields: [String: String], chunks: [Result<Data?, MCPHTTPClientError>]) {
        self.statusCode = statusCode
        self.headerFields = headerFields.reduce(into: [:]) { $0[$1.key.lowercased()] = $1.value }
        self.chunks = chunks
    }

    /// Convenience: a JSON buffered-style stream (single chunk, application/json).
    static func json(_ object: [String: Any], statusCode: Int = 200, sessionID: String? = nil) -> MCPHTTPStubStream {
        var headers = ["content-type": "application/json"]
        if let sessionID { headers["mcp-session-id"] = sessionID }
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return MCPHTTPStubStream(
            statusCode: statusCode,
            headerFields: headers,
            chunks: [.success(data), .success(nil)]
        )
    }

    /// Convenience: an SSE stream carrying the given raw event-stream text as one or more chunks.
    static func sse(_ chunks: [String], statusCode: Int = 200, sessionID: String? = nil) -> MCPHTTPStubStream {
        var headers = ["content-type": "text/event-stream"]
        if let sessionID { headers["mcp-session-id"] = sessionID }
        var results: [Result<Data?, MCPHTTPClientError>] = chunks.map { .success(Data($0.utf8)) }
        results.append(.success(nil))
        return MCPHTTPStubStream(statusCode: statusCode, headerFields: headers, chunks: results)
    }

    func readChunk(timeout: TimeInterval) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard !chunks.isEmpty else { return nil }
        let next = chunks.removeFirst()
        switch next {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        }
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// A live SSE stream whose frames are pushed after creation (e.g. by a POST handler), modelling a
/// real HTTP+SSE server's single long-lived stream. `readChunk` blocks up to its timeout for the
/// next pushed frame; `finish()` ends the stream.
final class MCPHTTPLiveStubStream: MCPHTTPStream, @unchecked Sendable {
    let statusCode: Int
    let headerFields: [String: String]

    private let condition = NSCondition()
    private var pending: [Data] = []
    private var done = false

    init(statusCode: Int = 200) {
        self.statusCode = statusCode
        self.headerFields = ["content-type": "text/event-stream"]
    }

    func pushEvent(name: String, data: String) {
        condition.lock()
        pending.append(Data("event: \(name)\ndata: \(data)\n\n".utf8))
        condition.signal()
        condition.unlock()
    }

    func finish() {
        condition.lock(); done = true; condition.broadcast(); condition.unlock()
    }

    func readChunk(timeout: TimeInterval) throws -> Data? {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        condition.lock(); defer { condition.unlock() }
        while pending.isEmpty && !done {
            if Date() >= deadline { throw MCPHTTPClientError.timedOut }
            _ = condition.wait(until: deadline)
        }
        if !pending.isEmpty { return pending.removeFirst() }
        return nil
    }

    func cancel() {
        finish()
    }
}
