import Foundation
import QuillCodeCore

/// Whether the request builder may add Anthropic prompt-cache breakpoints (`cache_control`)
/// to the outgoing chat messages.
public enum TrustedRouterPromptCachingPolicy: Sendable, Equatable {
    /// Add breakpoints when the target model's provider family is known to accept them
    /// (Anthropic models routed through TrustedRouter). Every other route sends the exact
    /// request it sent before this feature existed.
    case automatic
    /// Never add breakpoints.
    case disabled
}

/// Places Anthropic prompt-cache breakpoints on an OpenAI-format `messages` array.
///
/// A `cache_control` marker inside an array-shaped content block is Anthropic's request to turn
/// the request prefix up to that block into a 5-minute ephemeral cache entry, so re-sent
/// prefixes bill at the cached-read rate (~10% of input) instead of full price — the dominant
/// recurring cost of the unattended agent loop.
///
/// GATEWAY STATE (live-verified 2026-07-01, api.trustedrouter.com): the deployed gateway
/// forwards `cache_control` verbatim on the Anthropic-native `/v1/messages` path
/// (`cache_creation_input_tokens` then `cache_read_input_tokens` observed on identical calls)
/// but currently DROPS it on the OpenAI-format `/chat/completions` path that QuillCode uses (a
/// six-marker request returned 200 there while `/v1/messages` returned Anthropic's own
/// four-marker 400). So today these breakpoints are a safe no-op on the chat path; they become
/// the intended win once the gateway forwards them on that path (tracked as a gateway follow-up).
///
/// Three constraints shape the placement rules:
/// - Prefix stability. A breakpoint only pays off when the bytes BEFORE it repeat unchanged on
///   the next request; otherwise every call is a cache WRITE (billed at 1.25x) with no read — a
///   net cost INCREASE. `TrustedRouterPromptBuilder` sends a sliding history window, so once it
///   saturates the post-system prefix diverges each turn. Annotation is gated on
///   `historyPrefixStable`; when false the request is sent unannotated (durable long-loop
///   caching needs the builder to pin the window edges — see the gateway/builder follow-up).
/// - System messages are never annotated: the gateway concatenates SYSTEM content with `str()`
///   into Anthropic's top-level `system` string, so array-shaped system content would be
///   corrupted into a Python repr. A breakpoint on a later message already caches the system
///   prefix, so this costs nothing.
/// - Non-Anthropic upstreams receive the `messages` array verbatim, and strict providers can
///   reject unknown fields inside content parts. Annotation is gated to model IDs whose provider
///   family is Anthropic; every other route's request bytes are unchanged.
public enum TrustedRouterPromptCaching {
    /// Anthropic's default ephemeral cache entry (5-minute TTL).
    static let ephemeralCacheControl = ["type": "ephemeral"]

    static let anthropicProviderFamily = "anthropic"

    /// True when `modelID` routes to a provider family that understands `cache_control`
    /// (Anthropic). Router-native meta-models (`trustedrouter/fast`, `tr/synth`, …) and other
    /// provider families return false so their requests stay byte-identical.
    public static func supportsCacheBreakpoints(modelID: String) -> Bool {
        TrustedRouterDefaults.provider(fromModelID: modelID)
            .caseInsensitiveCompare(anthropicProviderFamily) == .orderedSame
    }

    /// The messages to send for `modelID` under `policy`: either the input untouched, or the
    /// input with cache breakpoints placed per `breakpointIndexes`.
    ///
    /// `historyPrefixStable` must be true for annotation to occur: it asserts the caller has
    /// proven the request's post-system prefix repeats byte-for-byte on the next turn (the
    /// sliding history window has not dropped its oldest message). When false, the request is
    /// returned untouched — a moving prefix would make every breakpoint a cache write with no
    /// possible read, i.e. a net cost increase in exactly the long-loop regime this targets.
    public static func annotatedMessages(
        _ messages: [[String: Any]],
        modelID: String,
        policy: TrustedRouterPromptCachingPolicy,
        historyPrefixStable: Bool
    ) -> [[String: Any]] {
        guard policy == .automatic,
              historyPrefixStable,
              supportsCacheBreakpoints(modelID: modelID)
        else {
            return messages
        }
        return annotated(messages)
    }

    static func annotated(_ messages: [[String: Any]]) -> [[String: Any]] {
        var annotated = messages
        for index in breakpointIndexes(messages) {
            guard let text = annotatableText(of: messages[index]) else { continue }
            var message = messages[index]
            message["content"] = [
                [
                    "type": "text",
                    "text": text,
                    "cache_control": ephemeralCacheControl
                ] as [String: Any]
            ]
            annotated[index] = message
        }
        return annotated
    }

    /// Deterministic breakpoint positions, newest-prefix-first semantics:
    ///
    /// 1. The LATEST user message. Its breakpoint caches everything before it — system prompt,
    ///    tool definitions, and history — and stays on the same element for every model call
    ///    within the turn's tool loop, so intra-turn calls re-read one stable cache entry.
    /// 2. The FINAL message, when the request continues past the latest user message (tool
    ///    feedback is appended as assistant messages). Each loop iteration then extends the
    ///    cache over the previous iteration's tool output instead of re-reading it at full
    ///    price. Prior turns' breakpoints remain valid cache entries on Anthropic's side, so
    ///    moving this marker forward never invalidates the cached prefix behind it.
    ///
    /// System messages are never candidates (see the type comment: the gateway would corrupt
    /// array-shaped system content). At most two breakpoints are placed, well under Anthropic's
    /// four-breakpoint limit.
    static func breakpointIndexes(_ messages: [[String: Any]]) -> [Int] {
        var indexes: [Int] = []
        if let lastUser = messages.lastIndex(where: { role(of: $0) == "user" }) {
            indexes.append(lastUser)
        }
        if let last = messages.indices.last,
           role(of: messages[last]) == "assistant",
           indexes.last != last {
            indexes.append(last)
        }
        return indexes
    }

    /// The message's content when it is a plain non-empty string — the only shape this
    /// annotator rewrites. Array or missing content is left untouched (never re-wrapped), and
    /// whitespace-only text is skipped because Anthropic rejects blank text blocks.
    private static func annotatableText(of message: [String: Any]) -> String? {
        guard let content = message["content"] as? String,
              content.contains(where: { !$0.isWhitespace })
        else {
            return nil
        }
        return content
    }

    private static func role(of message: [String: Any]) -> String? {
        message["role"] as? String
    }
}
