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

    public init(maxAttempts: Int = 4, base: Duration = .milliseconds(500), cap: Duration = .seconds(20)) {
        self.maxAttempts = maxAttempts
        self.base = base
        self.cap = cap
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
}

extension Duration {
    /// The duration as a Double count of seconds (for arithmetic that Duration does not support directly).
    var inSeconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
