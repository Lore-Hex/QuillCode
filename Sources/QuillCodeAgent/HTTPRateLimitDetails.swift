import Foundation

/// The server's rate-limit guidance, normalized from HTTP response headers into one shape the retry
/// backoff can consume regardless of provider dialect: `Retry-After` (delta-seconds or HTTP-date),
/// OpenAI/gateway-style `x-ratelimit-remaining-*` / `x-ratelimit-reset-*`, and Anthropic-style
/// `anthropic-ratelimit-*-remaining` / `-reset` (RFC3339 date). Parsed once at the HTTP layer and
/// carried on the thrown error, so the retry loop can wait as long as the gateway actually asked
/// instead of guessing exponentially.
public struct HTTPRateLimitDetails: Sendable, Hashable {
    /// How long the server asked us to wait, from `Retry-After`.
    public var retryAfter: Duration?
    /// The smallest remaining quota across all rate-limit buckets (0 means some quota is exhausted).
    public var remaining: Int?
    /// Time until the quota replenishes: the LATEST reset among buckets whose remaining is 0
    /// (retrying before every exhausted bucket has reset would still 429), or the soonest advertised
    /// reset when no bucket is known-exhausted (informational only).
    public var resetAfter: Duration?

    public init(retryAfter: Duration? = nil, remaining: Int? = nil, resetAfter: Duration? = nil) {
        self.retryAfter = retryAfter
        self.remaining = remaining
        self.resetAfter = resetAfter
    }

    /// The wait the server authoritatively mandated: an explicit `Retry-After`, else the reset time
    /// when the remaining quota is exhausted. `nil` means the headers carry no mandate and the
    /// caller should fall back to its own (exponential) delay.
    public var mandatedDelay: Duration? {
        if let retryAfter { return retryAfter }
        if remaining == 0, let resetAfter { return resetAfter }
        return nil
    }

    /// Parses the recognized rate-limit headers (case-insensitively) out of a response header map.
    /// Returns nil when no recognized header parses, so "no guidance" stays cheap to represent.
    /// `now` is injected so the absolute-date header forms are deterministic in tests.
    public static func parse(headers: [String: String], now: Date = Date()) -> HTTPRateLimitDetails? {
        var retryAfter: Duration?
        // remaining/reset are tracked PER BUCKET (requests, tokens, …) so an exhausted bucket can be
        // matched to its own reset time rather than an unrelated bucket's.
        var remainingByBucket: [String: Int] = [:]
        var resetByBucket: [String: Double] = [:]

        for (name, rawValue) in headers {
            let key = name.lowercased()
            let value = rawValue.trimmingCharacters(in: .whitespaces)
            if key == "retry-after" {
                if let seconds = parseRetryAfter(value, now: now) { retryAfter = .seconds(seconds) }
            } else if let bucket = bucket(of: key, afterPrefix: "x-ratelimit-remaining") {
                if let count = Int(value) { remainingByBucket["x/\(bucket)"] = count }
            } else if let bucket = bucket(of: key, afterPrefix: "x-ratelimit-reset") {
                if let seconds = parseReset(value, now: now) { resetByBucket["x/\(bucket)"] = seconds }
            } else if let bucket = anthropicBucket(of: key, beforeSuffix: "-remaining") {
                if let count = Int(value) { remainingByBucket["anthropic/\(bucket)"] = count }
            } else if let bucket = anthropicBucket(of: key, beforeSuffix: "-reset") {
                if let seconds = parseReset(value, now: now) { resetByBucket["anthropic/\(bucket)"] = seconds }
            }
        }

        let remaining = remainingByBucket.values.min()
        let exhaustedBuckets = remainingByBucket.filter { $0.value == 0 }.keys
        let resetSeconds: Double?
        if exhaustedBuckets.isEmpty {
            // No bucket is known-exhausted: the soonest advertised reset, informational only
            // (`mandatedDelay` ignores it because remaining != 0).
            resetSeconds = resetByBucket.values.min()
        } else {
            // Only an exhausted bucket's OWN reset is mandate-eligible — a healthy bucket's reset
            // must not stall the retry. When no exhausted bucket advertised a usable reset, leave
            // resetAfter nil so the backoff falls back to plain exponential.
            resetSeconds = exhaustedBuckets.compactMap { resetByBucket[$0] }.max()
        }

        let details = HTTPRateLimitDetails(
            retryAfter: retryAfter,
            remaining: remaining,
            resetAfter: resetSeconds.map { .seconds($0) }
        )
        return details == HTTPRateLimitDetails() ? nil : details
    }

    // MARK: - Header-name recognition

    /// `x-ratelimit-remaining-tokens` (prefix `x-ratelimit-remaining`) -> "tokens"; the bare
    /// `x-ratelimit-remaining` -> "". Nil when the key is not this header family.
    private static func bucket(of key: String, afterPrefix prefix: String) -> String? {
        guard key.hasPrefix(prefix) else { return nil }
        let rest = key.dropFirst(prefix.count)
        if rest.isEmpty { return "" }
        guard rest.hasPrefix("-") else { return nil }
        return String(rest.dropFirst())
    }

    /// `anthropic-ratelimit-input-tokens-remaining` (suffix `-remaining`) -> "input-tokens".
    private static func anthropicBucket(of key: String, beforeSuffix suffix: String) -> String? {
        let prefix = "anthropic-ratelimit-"
        guard key.hasPrefix(prefix), key.hasSuffix(suffix),
              key.count > prefix.count + suffix.count
        else { return nil }
        return String(key.dropFirst(prefix.count).dropLast(suffix.count))
    }

    // MARK: - Value parsing (all normalized to bounded, non-negative delta seconds from `now`)

    /// The ceiling on any parsed wait: no server legitimately mandates more than a year; anything
    /// beyond is a buggy or hostile header and is clamped here.
    private static let maxDelaySeconds: Double = 86_400 * 366

    /// Bounds a parsed wait before it may reach `Duration`. These values are SERVER-CONTROLLED, and
    /// `Duration.seconds(Double)` traps UNCATCHABLY on non-finite input and on finite magnitudes
    /// past ~1.7e20 (Int128 attoseconds overflow) — while `Double("…")` happily parses "inf", "nan",
    /// and hex floats like "0x1p200". Every seconds value MUST pass through here: non-finite parses
    /// are rejected, finite ones clamped into 0...maxDelaySeconds.
    private static func boundedDelaySeconds(_ seconds: Double) -> Double? {
        guard seconds.isFinite else { return nil }
        return min(max(0, seconds), maxDelaySeconds)
    }

    /// `Retry-After` arrives as delta-seconds ("120") or an HTTP-date
    /// ("Wed, 21 Oct 2015 07:28:00 GMT"). A date already in the past normalizes to 0.
    private static func parseRetryAfter(_ value: String, now: Date) -> Double? {
        if let seconds = Double(value) { return boundedDelaySeconds(seconds) }
        if let date = httpDate(value) { return boundedDelaySeconds(date.timeIntervalSince(now)) }
        return nil
    }

    /// A reset header arrives as an RFC3339 date (Anthropic), a delta ("30", "30s", "250ms"), or a
    /// unix epoch in seconds/milliseconds (OpenRouter's `X-RateLimit-Reset` is epoch millis) — the
    /// numeric forms disambiguated by magnitude (an epoch is over 1e9; no one asks a client to wait
    /// 30+ years).
    private static func parseReset(_ value: String, now: Date) -> Double? {
        if let date = rfc3339Date(value) ?? httpDate(value) {
            return boundedDelaySeconds(date.timeIntervalSince(now))
        }
        if value.hasSuffix("ms"), let millis = Double(value.dropLast(2)) {
            return boundedDelaySeconds(millis / 1000)
        }
        if value.hasSuffix("s"), let seconds = Double(value.dropLast()) {
            return boundedDelaySeconds(seconds)
        }
        guard let number = Double(value) else { return nil }
        if number >= 1e12 { return boundedDelaySeconds(number / 1000 - now.timeIntervalSince1970) } // epoch millis
        if number >= 1e9 { return boundedDelaySeconds(number - now.timeIntervalSince1970) } // epoch seconds
        return boundedDelaySeconds(number) // delta seconds
    }

    private static func rfc3339Date(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    private static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
