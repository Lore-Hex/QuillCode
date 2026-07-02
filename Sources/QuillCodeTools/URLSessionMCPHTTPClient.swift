import Foundation

// URLSession and its request/response/delegate types live in FoundationNetworking on Linux
// (swift-corelibs-foundation), not Foundation — the same split the TrustedRouter clients guard.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `URLSession`-backed `MCPHTTPClient`. `perform` fully buffers a bounded response; `openStream`
/// returns a live chunk stream for `text/event-stream` bodies. Both are blocking by design — the
/// MCP runtime invokes sessions synchronously (like the stdio prober), so these bridge async
/// URLSession callbacks to a bounded semaphore/queue wait.
///
/// Redirects are refused at the delegate so a remote MCP endpoint cannot be silently redirected
/// to another host; the caller sees the 3xx status. Bodies are capped mid-stream.
public struct URLSessionMCPHTTPClient: MCPHTTPClient {
    public init() {}

    public func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        let delegate = BufferingDelegate(maxBodyBytes: max(0, request.maxResponseBytes))
        let session = Self.makeSession(timeout: request.timeout, delegate: delegate)
        defer { session.invalidateAndCancel() }

        let task = session.dataTask(with: Self.urlRequest(from: request))
        task.resume()

        let deadline = DispatchTime.now() + request.timeout + 10
        guard delegate.completion.wait(timeout: deadline) == .success else {
            task.cancel()
            throw MCPHTTPClientError.timedOut
        }
        return try delegate.makeResponse()
    }

    public func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream {
        let delegate = StreamingDelegate()
        let session = Self.makeSession(timeout: request.timeout, delegate: delegate)
        let task = session.dataTask(with: Self.urlRequest(from: request))
        delegate.attach(session: session, task: task)
        task.resume()

        // Block until headers arrive (or the request fails), bounded by the timeout.
        let deadline = DispatchTime.now() + request.timeout + 10
        switch delegate.headers.wait(timeout: deadline) {
        case .success:
            break
        case .timedOut:
            delegate.cancel()
            throw MCPHTTPClientError.timedOut
        }
        if let error = delegate.startupError {
            delegate.cancel()
            throw error
        }
        guard delegate.hasHTTPResponse else {
            delegate.cancel()
            throw MCPHTTPClientError.notHTTP
        }
        return delegate
    }

    private static func makeSession(timeout: TimeInterval, delegate: URLSessionDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = max(1, timeout)
        // The resource timeout must accommodate long-lived SSE streams, so give it headroom.
        configuration.timeoutIntervalForResource = max(60, timeout * 4)
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private static func urlRequest(from request: MCPHTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = max(1, request.timeout)
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
    }

    static func normalizedHeaderFields(_ response: HTTPURLResponse) -> [String: String] {
        var fields: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { continue }
            let key = name.lowercased()
            fields[key] = fields[key].map { "\($0), \(value)" } ?? value
        }
        return fields
    }
}

// MARK: - Buffering delegate (perform)

private final class BufferingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let completion = DispatchSemaphore(value: 0)

    private let maxBodyBytes: Int
    private let lock = NSLock()
    private var response: HTTPURLResponse?
    private var body = Data()
    private var exceeded = false
    private var transportError: Error?

    init(maxBodyBytes: Int) {
        self.maxBodyBytes = maxBodyBytes
    }

    func makeResponse() throws -> MCPHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        guard let response else {
            if let transportError {
                throw Self.classify(transportError)
            }
            throw MCPHTTPClientError.notHTTP
        }
        if let transportError, !exceeded {
            throw Self.classify(transportError)
        }
        return MCPHTTPResponse(
            statusCode: response.statusCode,
            headerFields: URLSessionMCPHTTPClient.normalizedHeaderFields(response),
            body: body,
            bodyExceededMaxBytes: exceeded
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        self.response = response as? HTTPURLResponse
        let declared = response.expectedContentLength
        if declared != NSURLSessionTransferSizeUnknown, declared > Int64(maxBodyBytes) {
            exceeded = true
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let remaining = maxBodyBytes - body.count
        if data.count <= remaining {
            body.append(data)
            lock.unlock()
            return
        }
        if remaining > 0 {
            body.append(data.prefix(remaining))
        }
        exceeded = true
        lock.unlock()
        dataTask.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        transportError = error
        lock.unlock()
        completion.signal()
    }

    static func classify(_ error: Error) -> MCPHTTPClientError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return .timedOut
        }
        return .transport(error.localizedDescription)
    }
}

// MARK: - Streaming delegate (openStream)

/// Delivers body bytes incrementally to `readChunk`. Data received before a `readChunk` call is
/// queued (bounded); `readChunk` blocks up to its timeout for the next chunk. Thread-safe via a
/// lock + condition; `@unchecked Sendable` is sound because every field is lock-guarded.
private final class StreamingDelegate: NSObject, MCPHTTPStream, URLSessionDataDelegate, @unchecked Sendable {
    let headers = DispatchSemaphore(value: 0)

    private let lock = NSCondition()
    private var session: URLSession?
    private var task: URLSessionTask?
    private var queued = Data()
    private var finished = false
    private var cancelled = false
    private var _statusCode: Int?
    private var _headerFields: [String: String] = [:]
    private(set) var startupError: MCPHTTPClientError?

    /// Cap on bytes buffered ahead of the reader, to bound memory if the caller reads slowly.
    private let maxBuffered = 16 * 1024 * 1024

    func attach(session: URLSession, task: URLSessionTask) {
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
    }

    var statusCode: Int {
        lock.lock(); defer { lock.unlock() }
        return _statusCode ?? 0
    }

    var hasHTTPResponse: Bool {
        lock.lock(); defer { lock.unlock() }
        return _statusCode != nil
    }

    var headerFields: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return _headerFields
    }

    func readChunk(timeout: TimeInterval) throws -> Data? {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        lock.lock()
        defer { lock.unlock() }
        while true {
            if !queued.isEmpty {
                let chunk = queued
                queued.removeAll(keepingCapacity: true)
                return chunk
            }
            if let startupError { throw startupError }
            if finished { return nil }
            if cancelled { return nil }
            if Date() >= deadline {
                throw MCPHTTPClientError.timedOut
            }
            _ = lock.wait(until: deadline)
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        let session = self.session
        self.task = nil
        self.session = nil
        lock.broadcast()
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        if let http = response as? HTTPURLResponse {
            _statusCode = http.statusCode
            _headerFields = URLSessionMCPHTTPClient.normalizedHeaderFields(http)
        } else {
            startupError = .notHTTP
        }
        lock.broadcast()
        lock.unlock()
        headers.signal()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if queued.count + data.count > maxBuffered {
            startupError = .responseTooLarge
            finished = true
            lock.broadcast()
            lock.unlock()
            dataTask.cancel()
            return
        }
        queued.append(data)
        lock.broadcast()
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if let error {
            let classified = BufferingDelegate.classify(error)
            // A cancellation we asked for is a clean end, not an error.
            let nsError = error as NSError
            if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                if _statusCode == nil { startupError = classified }
            }
        }
        finished = true
        lock.broadcast()
        lock.unlock()
        headers.signal() // unblock openStream if we failed before receiving a response
    }
}
