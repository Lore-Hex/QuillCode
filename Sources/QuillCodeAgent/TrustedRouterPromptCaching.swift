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
/// TrustedRouter's Anthropic adapter forwards user/assistant message `content` verbatim into
/// the Anthropic Messages payload, so a `cache_control` marker inside an array-shaped content
/// block reaches api.anthropic.com and turns the entire request prefix — system prompt, tool
/// definitions (serialized into the system prompt), and conversation history up to the marked
/// block — into a 5-minute cache entry. Re-sent prefixes then bill at the cached-read rate
/// (~10% of the input price) instead of full price, which is the dominant recurring cost of
/// the unattended agent loop.
///
/// Two hard constraints shape the placement rules:
/// - The gateway concatenates SYSTEM message content with `str()` into Anthropic's top-level
///   `system` string. Array-shaped system content would therefore be corrupted into a Python
///   repr, so system messages are never annotated. This costs nothing: a breakpoint on a later
///   message already caches the system prefix.
/// - Non-Anthropic upstreams receive the `messages` array verbatim, and strict providers can
///   reject unknown fields inside content parts. Annotation is therefore gated to model IDs
///   whose provider family is Anthropic; every other route's request bytes are unchanged.
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
    public static func annotatedMessages(
        _ messages: [[String: Any]],
        modelID: String,
        policy: TrustedRouterPromptCachingPolicy
    ) -> [[String: Any]] {
        guard policy == .automatic, supportsCacheBreakpoints(modelID: modelID) else {
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
