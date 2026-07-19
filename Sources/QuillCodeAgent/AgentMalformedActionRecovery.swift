import Foundation
import QuillCodeCore

/// A model stream died AFTER it was successfully obtained — a transport reset mid-response.
///
/// The obtain-time retry decorator (`RetryingLLMClient`) deliberately does not retry mid-stream
/// failures at the transport layer (a blind transport retry could double-emit streamed content).
/// Re-requesting the whole action IS safe at the action-resolver layer — no tool has executed for
/// this action yet, so a fresh request is a pure resample. The streaming runners wrap qualifying
/// errors in this marker so the resolver can distinguish "stream interrupted, re-request" from
/// obtain-time errors that already exhausted their retry budget (which arrive unwrapped and stay
/// fatal). A struct on purpose: appending cases to an existing error enum risks the incremental-build
/// discriminant hazard, and no persistence ever sees this type.
struct AgentStreamInterruptedError: Error, CustomStringConvertible {
    let underlying: any Error

    var description: String {
        "Model stream was interrupted mid-response: \(self.underlying)"
    }
}

/// Builds the bounded corrective re-prompt used when the model returns text that cannot be parsed
/// into a QuillCode action envelope (garbage/mojibake tokens, malformed JSON). One invalid response
/// must not kill an unattended run: a fresh request is a new sample, and an explicit correction
/// steers a confused model back to the schema. Mirrors `AgentPromisedWorkGuard.correctionPrompt`.
enum AgentMalformedActionGuard {
    /// Cap the malformed text echoed back to the model, mirroring the compaction bound — garbage can
    /// be arbitrarily long and repeating megabytes of it would burn context for nothing.
    static let malformedTextEchoLimit = 2048

    static func correctionPrompt(malformedText: String, userMessage: String) -> String {
        """
        Your previous response was not a valid QuillCode action JSON object.

        Original user request:
        \(userMessage)

        Invalid response (may be truncated):
        \(String(malformedText.prefix(malformedTextEchoLimit)))

        Return exactly one QuillCode action JSON object now and no other text: either
        {"type":"tool","name":"...","arguments":{...}} with complete arguments, or
        {"type":"say","text":"..."} with your answer. Do not wrap it in markdown.
        """
    }
}
