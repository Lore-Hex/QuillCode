import Foundation
import QuillCodeCore

/// A cheap, total estimate of how many tokens a thread's assembled prompt costs, so the run loop can
/// compact PROACTIVELY before a failed round-trip. Deliberately provider-agnostic and approximate —
/// it is a threshold trip-wire, not a billing figure — using the well-worn ~4-characters-per-token
/// heuristic over the visible content plus a fixed per-message envelope overhead (role tag, JSON
/// framing) so a thread of many tiny messages is not wildly under-counted.
///
/// TOTALITY is the point: it must never trap or overflow on adversarial input — an empty thread, a
/// single multi-megabyte tool result, or millions of messages. Character counts accumulate as `Int`
/// with saturating math and a hard ceiling, so a hostile thread yields a large finite estimate (which
/// simply trips the threshold) rather than crashing the run.
public enum ContextTokenEstimator {
    /// Average characters per token for English-ish text/code. Conservative-low so the estimate skews
    /// slightly HIGH (compact a little early) rather than late (hit the real wall).
    static let charactersPerToken = 4
    /// Per-message fixed overhead in tokens (role, delimiters, JSON envelope) charged on top of the
    /// content estimate.
    static let perMessageOverheadTokens = 4
    /// The ceiling on the returned estimate. Far above any real context window, so the value stays a
    /// finite `Int` no matter how large the thread; anything at or beyond it has already blown every
    /// threshold, so the exact number past here is irrelevant.
    static let maxEstimatedTokens = 1_000_000_000

    /// Estimated prompt tokens for the whole thread's messages. Empty thread → 0.
    public static func estimatedTokens(for thread: ChatThread) -> Int {
        estimatedTokens(for: thread.messages)
    }

    public static func estimatedTokens(for messages: [ChatMessage]) -> Int {
        var total = 0
        for message in messages {
            total = addSaturating(total, tokens(forContentCount: message.content.count))
            total = addSaturating(total, perMessageOverheadTokens)
            if total >= maxEstimatedTokens { return maxEstimatedTokens }
        }
        return min(total, maxEstimatedTokens)
    }

    /// Estimated tokens for a single string's content (no per-message overhead). Used by the compactor
    /// to size the summary and the last-resort truncation.
    public static func estimatedTokens(forText text: String) -> Int {
        min(tokens(forContentCount: text.count), maxEstimatedTokens)
    }

    private static func tokens(forContentCount characterCount: Int) -> Int {
        // `characterCount` is a non-negative `String.count`; integer-divide by the per-token width,
        // rounding UP so a short non-empty message still costs at least one token.
        guard characterCount > 0 else { return 0 }
        let width = max(1, charactersPerToken)
        // (n + width - 1) / width can overflow only near Int.max, which String.count never reaches on
        // any real platform; guard anyway so this is provably total.
        let numerator = addSaturating(characterCount, width - 1)
        return numerator / width
    }

    /// Integer addition that clamps at `Int.max` instead of trapping on overflow — so accumulating
    /// character counts across a pathologically large thread yields a finite ceiling, never a crash.
    private static func addSaturating(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
        return overflowed ? Int.max : sum
    }
}
