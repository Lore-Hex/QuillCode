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
    static let truncatedFileWriteContentLimit = 6_000

    static func isTruncatedFileWriteAction(_ text: String) -> Bool {
        let structuralPrefix = String(text.prefix(4_096)).filter { !$0.isWhitespace }
        let namesFileWrite = structuralPrefix.contains(#""name":"host.file.write""#)
            || structuralPrefix.contains(#""type":"host.file.write""#)
            || structuralPrefix.contains(#""type":"file.write""#)
        guard structuralPrefix.hasPrefix("{"),
              namesFileWrite,
              structuralPrefix.contains(#""path":"#),
              let contentKey = text.range(of: #""content""#) else {
            return false
        }

        var index = contentKey.upperBound
        skipWhitespace(in: text, from: &index)
        guard index < text.endIndex, text[index] == ":" else { return false }
        index = text.index(after: index)
        skipWhitespace(in: text, from: &index)
        guard index < text.endIndex, text[index] == "\"" else { return false }
        index = text.index(after: index)

        var isEscaped = false
        while index < text.endIndex {
            let character = text[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                return false
            }
            index = text.index(after: index)
        }
        return true
    }

    static func correctiveAssistantEcho(for malformedText: String) -> String {
        if isTruncatedFileWriteAction(malformedText) {
            return "[Truncated host.file.write action omitted; no tool was executed.]"
        }
        return String(malformedText.prefix(malformedTextEchoLimit))
    }

    static func correctionPrompt(malformedText: String, userMessage: String) -> String {
        if isTruncatedFileWriteAction(malformedText) {
            return """
            Your previous host.file.write action was truncated inside its content string, so no tool \
            was executed.

            Original user request:
            \(userMessage)

            Reissue exactly one complete canonical action now and no other text:
            {"type":"tool","name":"host.file.write","arguments":{"path":"...","content":"..."}}
            Reuse the requested output path. Preserve the requested sections and source-grounded \
            facts, but make the file content concise and no more than \
            \(truncatedFileWriteContentLimit) characters so the entire action, including its closing \
            JSON, completes in one response. Escape newlines and quotes as valid JSON. Do not wrap it \
            in markdown.
            """
        }
        return """
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

    private static func skipWhitespace(in text: String, from index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
    }

    static func emptyToolArgumentsCorrectionPrompt(toolName: String, userMessage: String) -> String {
        """
        Your previous response selected \(toolName) but omitted its required arguments.

        Original user request:
        \(userMessage)

        Return exactly one QuillCode action JSON object now and no other text. If \(toolName) is \
        still the intended next action, emit it with every required argument populated from the \
        request and prior tool results. Otherwise emit the correct next tool action with complete \
        arguments, or {"type":"say","text":"<what blocked you>"}. Do not wrap it in markdown.
        """
    }
}
