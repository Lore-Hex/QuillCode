import Foundation

/// Full-jitter exponential backoff for retrying a transient model-call failure. The delay grows
/// exponentially with the attempt (so we do not hammer a struggling gateway) but is fully jittered
/// (so many clients backing off at once do not resynchronize into a thundering herd) and capped.
///
/// The jitter is INJECTED (a 0…1 value) rather than drawn internally, so the delay is a pure function
/// and every backoff test is deterministic.
public struct RetryBackoffPolicy: Sendable, Hashable {
    /// Total attempts including the first — 4 means one initial try plus up to three retries.
    public var maxAttempts: Int
    /// The base delay that the exponential grows from.
    public var base: Duration
    /// The ceiling; the exponential is clamped here before jitter.
    public var cap: Duration
    /// The absolute ceiling on a server-requested `Retry-After`. We are polite and honor the gateway's
    /// ask even above our own exponential `cap`, but never longer than this — a bogus or hostile header
    /// (`Retry-After: 999999`) must not stall an unattended run indefinitely.
    public var retryAfterCeiling: Duration

    public init(
        maxAttempts: Int = 4,
        base: Duration = .milliseconds(500),
        cap: Duration = .seconds(20),
        retryAfterCeiling: Duration = .seconds(60)
    ) {
        self.maxAttempts = maxAttempts
        self.base = base
        self.cap = cap
        self.retryAfterCeiling = retryAfterCeiling
    }

    /// The delay before the retry following a given 0-based attempt index, given an injected jitter in
    /// 0…1. Full-jitter: `random(0, min(cap, base * 2^attempt))`, with `jitter` standing in for the
    /// random fraction.
    public func delay(forAttempt attempt: Int, jitter: Double) -> Duration {
        let clampedJitter = min(1, max(0, jitter))
        let exponent = pow(2.0, Double(max(0, attempt)))
        let uncapped = base.inSeconds * exponent
        let ceiling = min(cap.inSeconds, uncapped)
        return .seconds(max(0, ceiling * clampedJitter))
    }

    /// The retry delay honoring a server-requested `retryAfter` (Retry-After / rate-limit reset). We
    /// take the larger of the server's ask (clamped to `retryAfterCeiling`) and our own jittered
    /// backoff: never less polite than the gateway asked, never less than our own backoff, never longer
    /// than the ceiling. `retryAfter == nil` (or non-positive) falls straight through to the backoff.
    public func delay(forAttempt attempt: Int, jitter: Double, retryAfter: Duration?) -> Duration {
        let backoff = delay(forAttempt: attempt, jitter: jitter)
        guard let retryAfter, retryAfter > .zero else { return backoff }
        let honored = min(retryAfter, retryAfterCeiling)
        return max(honored, backoff)
    }
}

extension Duration {
    /// The duration as a Double count of seconds (for arithmetic that Duration does not support directly).
    var inSeconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
