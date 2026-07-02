import Foundation

// URLSession and its request/response/delegate types live in FoundationNetworking on Linux
// (swift-corelibs-foundation), not Foundation — the same split the TrustedRouter clients guard.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLSession-backed `WebFetchHTTPClient`. Blocking by design — it is called from
/// `ToolRouter.execute`, which is synchronous (the same way `ShellToolExecutor` blocks while
/// a process runs). Redirects are refused at the delegate so every 3xx surfaces to the
/// executor for SSRF re-gating, and the body is cancelled mid-stream the moment it exceeds
/// the byte cap.
public struct URLSessionWebFetchHTTPClient: WebFetchHTTPClient {
    public init() {}

    public func perform(_ request: WebFetchHTTPRequest) throws -> WebFetchHTTPResponse {
        let delegate = TransactionDelegate(maxBodyBytes: max(0, request.maxBodyBytes))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeout
        configuration.timeoutIntervalForResource = request.timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = request.timeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let task = session.dataTask(with: urlRequest)
        task.resume()

        // The semaphore wait is BOUNDED: even if URLSession never calls back (which its
        // resource timeout should prevent), the tool returns a timeout error instead of
        // hanging the agent loop forever.
        let grace: TimeInterval = 10
        let deadline = DispatchTime.now() + request.timeout + grace
        guard delegate.completionSemaphore.wait(timeout: deadline) == .success else {
            task.cancel()
            throw WebFetchHTTPClientError.timedOut
        }
        return try delegate.makeResponse()
    }

    /// Collects one transaction's response, enforcing the streaming byte cap and refusing
    /// redirects. `@unchecked Sendable` is sound: all mutable state is guarded by `lock`,
    /// and the caller only reads after `completionSemaphore` is signalled.
    private final class TransactionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let completionSemaphore = DispatchSemaphore(value: 0)

        private let maxBodyBytes: Int
        private let lock = NSLock()
        private var response: HTTPURLResponse?
        private var body = Data()
        private var exceededMaxBytes = false
        private var transportError: Error?

        init(maxBodyBytes: Int) {
            self.maxBodyBytes = maxBodyBytes
        }

        func makeResponse() throws -> WebFetchHTTPResponse {
            lock.lock()
            defer { lock.unlock() }
            guard let response else {
                if let transportError {
                    if isTimeout(transportError) {
                        throw WebFetchHTTPClientError.timedOut
                    }
                    throw WebFetchHTTPClientError.transport(transportError.localizedDescription)
                }
                throw WebFetchHTTPClientError.notHTTP
            }
            // A transport error AFTER the cap was hit is the cancellation we asked for; the
            // partial body is the intended result. Any other mid-body error is a real failure.
            if let transportError, !exceededMaxBytes {
                if isTimeout(transportError) {
                    throw WebFetchHTTPClientError.timedOut
                }
                throw WebFetchHTTPClientError.transport(transportError.localizedDescription)
            }
            return WebFetchHTTPResponse(
                statusCode: response.statusCode,
                headerFields: Self.normalizedHeaderFields(response),
                body: body,
                bodyExceededMaxBytes: exceededMaxBytes
            )
        }

        // Refuse every redirect: returning nil delivers the 3xx response itself, letting the
        // executor re-run the host gate on the Location target before any new connection.
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
            // Trust but verify: a huge declared Content-Length is refused before reading the
            // body. Comparison stays in Int64 — no conversion of server data into Int.
            let declared = response.expectedContentLength
            if declared != NSURLSessionTransferSizeUnknown, declared > Int64(maxBodyBytes) {
                exceededMaxBytes = true
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
            exceededMaxBytes = true
            lock.unlock()
            dataTask.cancel()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock()
            transportError = error
            lock.unlock()
            completionSemaphore.signal()
        }

        private func isTimeout(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
        }

        private static func normalizedHeaderFields(_ response: HTTPURLResponse) -> [String: String] {
            var fields: [String: String] = [:]
            for (name, value) in response.allHeaderFields {
                guard let name = name as? String, let value = value as? String else {
                    continue
                }
                let key = name.lowercased()
                fields[key] = fields[key].map { "\($0), \(value)" } ?? value
            }
            return fields
        }
    }
}
