import Foundation

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
        guard let latest = latestDate(url),
              since.map({ latest > $0 }) ?? true
        else {
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

enum FeedTimestampParser {
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
