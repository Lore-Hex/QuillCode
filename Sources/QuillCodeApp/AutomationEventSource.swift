import Foundation
import QuillCodeCore

// URLSession and request/response types live in FoundationNetworking on Linux.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A source of external events a `monitor` automation can watch, so a monitor
/// can fire when something actually changes instead of only on a schedule.
///
/// Adapters are deterministic and side-effect free for a given `since`, so the
/// automation engine can poll them on its tick and compare against the
/// automation's `lastRunAt` to decide whether to fire.
public protocol AutomationEventSource: Sendable {
    /// Returns a short human-readable description of the event when one has
    /// occurred after `since` (or ever, when `since` is `nil`), otherwise `nil`.
    func pendingEvent(since: Date?) -> String?
}

public typealias FileModificationDateProvider = @Sendable (URL) -> Date?
public typealias URLLastModifiedDateProvider = @Sendable (URL) -> Date?
public typealias URLFeedLatestDateProvider = @Sendable (URL) -> Date?

/// Fires when a watched file appears or is modified after the last check.
public struct FileChangeEventSource: AutomationEventSource {
    public var path: URL
    private let modificationDate: FileModificationDateProvider

    public init(
        path: URL,
        modificationDate: @escaping FileModificationDateProvider = Self.defaultModificationDate
    ) {
        self.path = path
        self.modificationDate = modificationDate
    }

    public func pendingEvent(since: Date?) -> String? {
        guard let modified = modificationDate(path) else {
            return nil
        }
        if let since, modified <= since {
            return nil
        }
        return "\(path.lastPathComponent) changed"
    }

    @usableFromInline
    static func defaultModificationDate(for path: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path.path)
        return attributes?[.modificationDate] as? Date
    }
}

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
        guard let modified = lastModifiedDate(url) else {
            return nil
        }
        if let since, modified <= since {
            return nil
        }
        return "\(url.absoluteString) Last-Modified changed"
    }

    @usableFromInline
    static func defaultLastModifiedDate(for url: URL) -> Date? {
        let delegate = HeaderOnlyDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8

        let task = session.dataTask(with: request)
        task.resume()
        let deadline = DispatchTime.now() + 10
        guard delegate.completionSemaphore.wait(timeout: deadline) == .success else {
            task.cancel()
            return nil
        }
        return delegate.lastModifiedDate()
    }

    private final class HeaderOnlyDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let completionSemaphore = DispatchSemaphore(value: 0)

        private let lock = NSLock()
        private var response: HTTPURLResponse?

        func lastModifiedDate() -> Date? {
            lock.lock()
            defer { lock.unlock() }
            guard let response, (200..<400).contains(response.statusCode) else {
                return nil
            }
            return response.value(forHTTPHeaderField: "Last-Modified").flatMap(Self.httpDate)
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

        private static func httpDate(_ value: String) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            return formatter.date(from: value)
        }
    }
}

/// Fires when a bounded RSS or Atom feed contains a published/updated timestamp
/// newer than the monitor's last run. Feeds without parseable item timestamps
/// stay quiet rather than repeatedly firing on reachability alone.
public struct URLFeedUpdateEventSource: AutomationEventSource {
    public var url: URL
    private let latestDate: URLFeedLatestDateProvider

    public init(
        url: URL,
        latestDate: @escaping URLFeedLatestDateProvider = Self.defaultLatestDate
    ) {
        self.url = url
        self.latestDate = latestDate
    }

    public func pendingEvent(since: Date?) -> String? {
        guard let latest = latestDate(url) else {
            return nil
        }
        if let since, latest <= since {
            return nil
        }
        return "\(url.absoluteString) feed updated"
    }

    @usableFromInline
    static func defaultLatestDate(for url: URL) -> Date? {
        guard let data = BoundedHTTPFetcher.fetch(url: url, method: "GET", byteLimit: 512 * 1024),
              let xml = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
        else {
            return nil
        }
        return defaultLatestDate(in: xml)
    }

    static func defaultLatestDate(in xml: String) -> Date? {
        FeedTimestampParser.latestDate(in: xml)
    }
}

enum AutomationEventSourceResolver {
    static func eventSource(
        for definition: QuillAutomationEventSource,
        project: ProjectRef?
    ) -> (any AutomationEventSource)? {
        switch definition.kind {
        case .fileChange:
            guard let url = fileChangeURL(for: definition.path, project: project) else {
                return nil
            }
            return FileChangeEventSource(path: url)
        case .urlLastModified:
            guard let url = httpURL(for: definition.path) else {
                return nil
            }
            return URLLastModifiedEventSource(url: url)
        case .urlFeedUpdate:
            guard let url = httpURL(for: definition.path) else {
                return nil
            }
            return URLFeedUpdateEventSource(url: url)
        }
    }

    static func fileChangeURL(for path: String, project: ProjectRef?) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        guard let project, !project.isRemote else { return nil }
        let root = URL(fileURLWithPath: project.path).standardizedFileURL
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard isContained(candidate, inside: root) else { return nil }
        return candidate
    }

    static func urlLastModifiedURL(for rawURL: String) -> URL? {
        httpURL(for: rawURL)
    }

    static func urlFeedUpdateURL(for rawURL: String) -> URL? {
        httpURL(for: rawURL)
    }

    private static func httpURL(for rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    private static func isContained(_ candidate: URL, inside root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        if candidatePath == rootPath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        return candidatePath.hasPrefix(prefix)
    }
}

private enum BoundedHTTPFetcher {
    static func fetch(url: URL, method: String, byteLimit: Int) -> Data? {
        let delegate = Delegate(byteLimit: byteLimit)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8

        let task = session.dataTask(with: request)
        task.resume()
        let deadline = DispatchTime.now() + 10
        guard delegate.completionSemaphore.wait(timeout: deadline) == .success else {
            task.cancel()
            return nil
        }
        return delegate.result()
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let completionSemaphore = DispatchSemaphore(value: 0)

        private let byteLimit: Int
        private let lock = NSLock()
        private var response: HTTPURLResponse?
        private var body = Data()
        private var exceededLimit = false

        init(byteLimit: Int) {
            self.byteLimit = byteLimit
        }

        func result() -> Data? {
            lock.lock()
            defer { lock.unlock() }
            guard let response,
                  (200..<400).contains(response.statusCode),
                  !exceededLimit
            else {
                return nil
            }
            return body
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
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            defer { lock.unlock() }
            guard !exceededLimit else { return }
            if body.count + data.count > byteLimit {
                exceededLimit = true
                dataTask.cancel()
                return
            }
            body.append(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            completionSemaphore.signal()
        }
    }
}

private enum FeedTimestampParser {
    static func latestDate(in xml: String) -> Date? {
        timestampValues(in: xml)
            .compactMap(parseDate)
            .max()
    }

    private static func timestampValues(in xml: String) -> [String] {
        let pattern = #"<(?:[A-Za-z0-9_]+:)?(updated|published|pubDate|lastBuildDate)\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?\1>"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return expression.matches(in: xml, range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let valueRange = Range(match.range(at: 2), in: xml)
            else {
                return nil
            }
            return xml[valueRange]
                .replacingOccurrences(of: #"<!\[CDATA\[(.*?)\]\]>"#, with: "$1", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        return rfc822Formats.lazy.compactMap { format in
            rfc822Formatter(format: format).date(from: value)
        }.first
    }

    private static let rfc822Formats: [String] = [
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "EEE, d MMM yyyy HH:mm:ss zzz",
        "dd MMM yyyy HH:mm:ss zzz",
        "EEE, dd MMM yyyy HH:mm zzz",
        "EEE, dd MMM yyyy HH:mm:ss Z"
    ]

    private static func rfc822Formatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
