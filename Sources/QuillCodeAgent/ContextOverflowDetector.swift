import Foundation
import QuillCodeCore

/// Why a model call was judged a context overflow — kept so a compaction notice can say WHICH signal
/// tripped (an HTTP 413, a gateway `context_length_exceeded`, a provider message, or a proactive
/// token estimate) and a test can assert each signal is normalized to the same decision.
public enum ContextOverflowSignal: String, Sendable, Hashable {
    /// The gateway rejected the request payload with HTTP 413 (Payload Too Large) — for a chat
    /// completion this is the request being larger than the model/route will accept.
    case httpPayloadTooLarge = "http_413"
    /// The error body carried a machine code the gateway/provider uses for context overflow
    /// (`context_length_exceeded`, `type=context_overflow`, `context_window_exceeded`).
    case machineCode = "machine_code"
    /// The error body carried a human message pattern that unambiguously means the prompt exceeded
    /// the context window ("maximum context length", "prompt is too long", …).
    case providerMessage = "provider_message"
    /// No error yet — the assembled prompt's estimated token count crossed the proactive threshold,
    /// so we compact BEFORE the wall instead of after a failed round-trip.
    case tokenThreshold = "token_threshold"
}

/// The single, uniform detector for "this model call failed (or is about to) because the context
/// window overflowed". It normalizes the several dialects the gateway and providers speak — an HTTP
/// 413, a JSON `code`/`type` of `context_length_exceeded` / `context_overflow`, a provider prose
/// message, or a proactive token estimate — into ONE typed decision the run loop can act on by
/// compacting and resuming, rather than failing the run.
///
/// Deliberately conservative on the ambiguous signals so it never misfires on an unrelated error:
/// an HTTP 413 is treated as overflow (for a chat request there is no other meaning), but every OTHER
/// status code must be corroborated by a machine code or a context-specific message in the body — a
/// plain 400/429/500 is NOT an overflow. The `RetryClassifier` still owns transient-vs-terminal for
/// retry; this detector is composed alongside it (see `ContextOverflowDetector.classification`) and
/// takes priority for the codes it recognizes, without changing the classifier's behavior.
public enum ContextOverflowDetector {
    /// Recognizes the overflow signal in a thrown model-call error, or nil when the error is not a
    /// context overflow. Only inspects the router's HTTP error (status + body); every other error
    /// type — transport blips, cancellations, auth, parse errors — returns nil so this never steals
    /// an error the retry/terminal paths must handle.
    public static func signal(for error: any Error) -> ContextOverflowSignal? {
        guard let routerError = error as? TrustedRouterAgentError,
              case .streamingHTTPError(let statusCode, let body, _) = routerError
        else { return nil }
        return signal(statusCode: statusCode, body: body)
    }

    /// The overflow signal for a raw HTTP status + response body, factored out so tests can drive it
    /// without constructing the full error and so a future non-router client can reuse the same
    /// normalization.
    public static func signal(statusCode: Int, body: String) -> ContextOverflowSignal? {
        // A bounded, lowercased view of the body: bodies are gateway/provider-controlled and can be
        // arbitrarily large, so cap the scan window before lowercasing to keep detection O(1) on a
        // hostile megabyte body. Overflow markers always appear early in the JSON error object.
        let haystack = normalizedBody(body)

        if containsMachineCode(haystack) { return .machineCode }
        if containsProviderMessage(haystack) { return .providerMessage }
        // 413 is the payload-too-large status: for a chat-completions POST the only thing that is
        // "too large" is the prompt, so treat a bare 413 as overflow even when the body is empty or
        // opaque. Every OTHER status needs a corroborating marker above and is NOT overflow here.
        if statusCode == payloadTooLargeStatusCode { return .httpPayloadTooLarge }
        return nil
    }

    /// Whether an estimated prompt-token count has crossed the proactive compaction threshold. Kept
    /// separate from the error path so the run loop can compact BEFORE a failing round-trip. Returns
    /// `.tokenThreshold` at or above `limit`; nil below. A non-positive `limit` disables the check
    /// (never proactively compacts) rather than compacting on every turn.
    public static func proactiveSignal(estimatedTokens: Int, limit: Int) -> ContextOverflowSignal? {
        guard limit > 0, estimatedTokens >= limit else { return nil }
        return .tokenThreshold
    }

    /// Convenience over `signal(for:)` for a boolean check at a call site that does not need the
    /// specific signal.
    public static func isContextOverflow(_ error: any Error) -> Bool {
        signal(for: error) != nil
    }

    // MARK: - Signal recognition

    static let payloadTooLargeStatusCode = 413

    /// The scan window: overflow markers live in the error object at the top of the body; capping the
    /// slice bounds work on a huge/hostile body and avoids lowercasing megabytes. Chosen generously so
    /// a marker nested a few fields deep in a verbose gateway envelope is still seen.
    static let bodyScanCharacterLimit = 8_000

    /// Machine-readable codes the gateway and providers use for context overflow. Matched as
    /// substrings of the lowercased body so both `"code":"context_length_exceeded"` and
    /// `type=context_overflow` forms hit, regardless of JSON vs form-encoded envelope.
    static let machineCodes: [String] = [
        "context_length_exceeded",
        "context_overflow",
        "context_window_exceeded",
        "context_length_error",
    ]

    /// Human prose patterns that unambiguously mean the prompt exceeded the window. Deliberately
    /// specific: generic words like "token" or "length" alone are NOT here, so an unrelated 400 whose
    /// body merely mentions tokens does not misfire.
    static let providerMessagePatterns: [String] = [
        "maximum context length",
        "maximum context window",
        "context length of",
        "context window of",
        "prompt is too long",
        "prompt is too large",
        "input is too long",
        "too many tokens",
        "reduce the length of the messages",
        "exceeds the context",
        "exceed the context",
    ]

    private static func normalizedBody(_ body: String) -> String {
        // Prefix on the raw string is O(scan window) and safe on empty input; lowercasing the bounded
        // slice keeps the case-insensitive match cheap even for a very large body.
        String(body.prefix(bodyScanCharacterLimit)).lowercased()
    }

    private static func containsMachineCode(_ haystack: String) -> Bool {
        machineCodes.contains { haystack.contains($0) }
    }

    private static func containsProviderMessage(_ haystack: String) -> Bool {
        providerMessagePatterns.contains { haystack.contains($0) }
    }
}
