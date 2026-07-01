import Foundation

/// The rate-limit signal a gateway returns alongside a 429/503 — normalized into "how long the server
/// is asking us to wait before retrying". We prefer `Retry-After` (the RFC 7231 standard, authoritative
/// signal; integer/decimal seconds OR an HTTP-date) and fall back to the common `x-ratelimit-*` /
/// `anthropic-ratelimit-*` reset headers so a gateway that only speaks those is still honored.
///
/// Parsing is a pure function with `now` INJECTED, so an HTTP-date / absolute-reset header resolves
/// deterministically under test. The value is never negative (a reset time already in the past means
/// "retry now", i.e. zero) so it can be combined with our jittered backoff without underflow.
public struct HttpRateLimitDetails: Sendable, Hashable {
    /// How long the server asked us to wait before retrying, if it said anything. Never negative.
    public var retryAfter: Duration?

    public init(retryAfter: Duration? = nil) {
        self.retryAfter = retryAfter
    }

    /// True when the server gave no usable rate-limit hint.
    public var isEmpty: Bool { retryAfter == nil }

    // The reset headers are a best-effort fallback (in a fixed order, unified/most-specific first) used
    // only when `Retry-After` is absent. Unlike `Retry-After`, these may carry an ABSOLUTE reset time.
    private static let resetKeys = [
        "anthropic-ratelimit-unified-reset",
        "x-ratelimit-reset",
        "x-ratelimit-reset-requests",
        "x-ratelimit-reset-tokens",
        "anthropic-ratelimit-requests-reset",
        "anthropic-ratelimit-tokens-reset",
        "ratelimit-reset",
    ]

    /// Parse a header dictionary (case-insensitive keys) into a rate-limit signal.
    public static func parse(headers: [String: String], now: Date) -> HttpRateLimitDetails {
        var lower: [String: String] = [:]
        for (key, value) in headers { lower[key.lowercased()] = value }
        // `Retry-After` (RFC 7231) is authoritative and is ALWAYS delay-seconds or an HTTP-date — never
        // an absolute unix epoch — so the epoch heuristic must not apply to it (a large delay-seconds
        // value must not be misread as a past timestamp and collapsed to zero).
        if let raw = lower["retry-after"], let delay = parseDelay(raw, now: now, allowEpochHeuristic: false) {
            return HttpRateLimitDetails(retryAfter: delay)
        }
        for key in resetKeys {
            if let raw = lower[key], let delay = parseDelay(raw, now: now, allowEpochHeuristic: true) {
                return HttpRateLimitDetails(retryAfter: delay)
            }
        }
        return HttpRateLimitDetails()
    }

    /// Thin adapter over a real `HTTPURLResponse` (the pure `parse(headers:now:)` is the tested core).
    public static func parse(response: HTTPURLResponse, now: Date) -> HttpRateLimitDetails {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return parse(headers: headers, now: now)
    }

    // MARK: - Value parsing

    /// Liberal parse of a single header value into a non-negative delay. Accepts, in order: a bare
    /// number (delta-seconds; or, when `allowEpochHeuristic` is set, an absolute unix-epoch timestamp
    /// when it is implausibly large for a delta), a Go-style duration (`6m0s`, `500ms`, `1.5s`), an
    /// HTTP-date, or an ISO-8601 timestamp. A non-finite / unparseable value returns nil so the caller
    /// falls back to normal backoff — critically, `Double("inf")` parses to +inf, which would trap
    /// `Duration.seconds`, so we must reject it here.
    static func parseDelay(_ raw: String, now: Date, allowEpochHeuristic: Bool) -> Duration? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        if let number = Double(value) {
            guard number.isFinite else { return nil }   // reject inf / -inf / nan / magnitude overflow
            // A plain number is normally delta-seconds. Some reset headers send an ABSOLUTE unix-epoch
            // instead; a value far too large to be a sane delay is almost certainly that, so treat it as
            // an absolute time and subtract now. (Never applied to `Retry-After` — see parse().)
            if allowEpochHeuristic, number > 1_000_000_000 {
                return clampNonNegative(number - now.timeIntervalSince1970)
            }
            return clampNonNegative(number)
        }
        if let seconds = parseGoDuration(value) {
            return clampNonNegative(seconds)
        }
        if let date = httpDate(value) ?? iso8601(value) {
            return clampNonNegative(date.timeIntervalSince(now))
        }
        return nil
    }

    private static func clampNonNegative(_ seconds: Double) -> Duration {
        // Guard non-finite here too (a far-future date delta): Duration.seconds traps on inf.
        guard seconds.isFinite else { return .zero }
        return .seconds(max(0, seconds))
    }

    /// Parse a Go-style duration string (`1h`, `6m0s`, `500ms`, `1.5s`, `100µs`) into seconds. The whole
    /// string must be consumed and contain at least one unit, else `nil`.
    static func parseGoDuration(_ string: String) -> Double? {
        // Longest-unit-first so `ms` wins over `m` and `µs`/`us`/`ns` win over `s`.
        let units: [(suffix: String, factor: Double)] = [
            ("ns", 1e-9), ("us", 1e-6), ("µs", 1e-6), ("ms", 1e-3),
            ("s", 1), ("m", 60), ("h", 3600),
        ]
        var index = string.startIndex
        var total = 0.0
        var sawUnit = false
        while index < string.endIndex {
            var numberEnd = index
            while numberEnd < string.endIndex, string[numberEnd].isNumber || string[numberEnd] == "." {
                numberEnd = string.index(after: numberEnd)
            }
            guard numberEnd > index, let number = Double(string[index..<numberEnd]) else { return nil }
            let rest = string[numberEnd...]
            guard let unit = units.first(where: { rest.hasPrefix($0.suffix) }) else { return nil }
            total += number * unit.factor
            sawUnit = true
            index = string.index(numberEnd, offsetBy: unit.suffix.count)
        }
        return sawUnit ? total : nil
    }

    private static func httpDate(_ string: String) -> Date? {
        // Fresh formatter per call: DateFormatter is not reliably safe to share for concurrent parsing,
        // and a 429 is rare enough that the allocation cost is irrelevant.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: string)
    }

    private static func iso8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
