import Foundation

// URLSession and request/response types live in FoundationNetworking on Linux.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fires when an HTTP(S) resource reports a Last-Modified timestamp newer than
/// the monitor's last run. Sources without that header stay quiet so a monitor
/// does not repeatedly fire just because the URL is reachable.
public struct URLLastModifiedEventSource: AutomationEventSource {
    public var url: URL
    private let lastModifiedDate: URLLastModifiedDateProvider

    public init(
        url: URL,
        lastModifiedDate: @escaping URLLastModifiedDateProvider = Self.defaultLastModifiedDate
    ) {
        self.url = url
        self.lastModifiedDate = lastModifiedDate
    }

    public func pendingEvent(since: Date?) -> String? {
        guard let modified = lastModifiedDate(url),
              since.map({ modified > $0 }) ?? true
        else {
            return nil
        }
        return "\(url.absoluteString) Last-Modified changed"
    }

    @usableFromInline
    static func defaultLastModifiedDate(for url: URL) -> Date? {
        HTTPHeaderDateFetcher.lastModifiedDate(for: url)
    }
}

private enum HTTPHeaderDateFetcher {
    static func lastModifiedDate(for url: URL) -> Date? {
        let delegate = HeaderOnlyDelegate()
        let session = AutomationHTTPURLSessionFactory.session(delegate: delegate)
        defer { session.invalidateAndCancel() }

        let task = session.dataTask(with: request(for: url))
        task.resume()
        guard delegate.waitForCompletion() else {
            task.cancel()
            return nil
        }
        return delegate.lastModifiedDate()
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = AutomationHTTPURLSessionFactory.timeout
        return request
    }

    private final class HeaderOnlyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let completionSemaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var response: HTTPURLResponse?

        func waitForCompletion() -> Bool {
            completionSemaphore.wait(timeout: AutomationHTTPURLSessionFactory.deadline) == .success
        }

        func lastModifiedDate() -> Date? {
            lock.lock()
            defer { lock.unlock() }
            guard let response, (200..<400).contains(response.statusCode) else {
                return nil
            }
            return response.value(forHTTPHeaderField: "Last-Modified").flatMap(HTTPDateParser.parse)
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
            lock.unlock()
            completionHandler(.cancel)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            completionSemaphore.signal()
        }
    }
}

enum HTTPDateParser {
    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}
