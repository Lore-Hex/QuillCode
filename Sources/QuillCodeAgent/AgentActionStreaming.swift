import Foundation
import QuillCodeCore

public enum AgentTextStreamEvent: Sendable, Hashable {
    case text(String)
    case reasoning(String)
    case usage(ModelTokenUsage)
}

public enum AgentActionStreamCollector {
    /// A model action is one JSON object, not an artifact transport. Keep enough room for large
    /// patches while preventing an unbounded or malformed provider stream from exhausting the app.
    public static let maximumActionUTF8Bytes = 16 * 1_024 * 1_024

    public static func collectText(from stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var text = ""
        var receivedBytes = 0
        for try await chunk in stream {
            try Task.checkCancellation()
            receivedBytes = try checkedByteCount(
                current: receivedBytes,
                adding: chunk.utf8.count,
                maximum: maximumActionUTF8Bytes
            )
            text.append(chunk)
        }
        return text
    }

    public static func collect(
        from stream: AsyncThrowingStream<String, Error>,
        emptyError: @autoclosure () -> any Error
    ) async throws -> AgentAction {
        let text = try await collectText(from: stream)
        return try parseAction(from: text, emptyError: emptyError())
    }

    public static func collect(
        from stream: AsyncThrowingStream<String, Error>,
        emptyError: @autoclosure () -> any Error,
        onVisibleAssistantText: ((String) async -> Void)?
    ) async throws -> AgentAction {
        try await collect(
            from: stream.asAgentTextEvents(),
            emptyError: emptyError(),
            onVisibleAssistantText: onVisibleAssistantText,
            onUsage: nil
        )
    }

    public static func collect(
        from stream: AsyncThrowingStream<AgentTextStreamEvent, Error>,
        emptyError: @autoclosure () -> any Error,
        onVisibleAssistantText: ((String) async -> Void)?,
        onUsage: ((ModelTokenUsage) async -> Void)?,
        onReasoning: ((String) async -> Void)? = nil
    ) async throws -> AgentAction {
        try await collect(
            from: stream,
            emptyError: emptyError(),
            onVisibleAssistantText: onVisibleAssistantText,
            onUsage: onUsage,
            onReasoning: onReasoning,
            maximumActionUTF8Bytes: maximumActionUTF8Bytes,
            previewIntervalNanoseconds: AgentStreamingProgressCadence.minimumIntervalNanoseconds,
            nowNanoseconds: { DispatchTime.now().uptimeNanoseconds }
        )
    }

    /// Internal deterministic seam for limit/cadence coverage. Production callers use the public
    /// overload above so every provider shares one response budget and one presentation cadence.
    static func collect(
        from stream: AsyncThrowingStream<AgentTextStreamEvent, Error>,
        emptyError: @autoclosure () -> any Error,
        onVisibleAssistantText: ((String) async -> Void)?,
        onUsage: ((ModelTokenUsage) async -> Void)?,
        onReasoning: ((String) async -> Void)?,
        maximumActionUTF8Bytes: Int,
        previewIntervalNanoseconds: UInt64,
        nowNanoseconds: @escaping () -> UInt64
    ) async throws -> AgentAction {
        precondition(maximumActionUTF8Bytes > 0)
        var rawActionText = ""
        var receivedBytes = 0
        var preview = AgentVisibleAssistantPreviewCadence(
            minimumIntervalNanoseconds: previewIntervalNanoseconds
        )
        var lastReasoningText = ""

        do {
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .text(let chunk):
                    receivedBytes = try checkedByteCount(
                        current: receivedBytes,
                        adding: chunk.utf8.count,
                        maximum: maximumActionUTF8Bytes
                    )
                    rawActionText.append(chunk)
                    if let visibleText = preview.nextPreview(
                        from: rawActionText,
                        nowNanoseconds: nowNanoseconds()
                    ) {
                        await onVisibleAssistantText?(visibleText)
                    }
                case .reasoning(let fragment):
                    // Preserve boundary whitespace: several providers emit reasoning one token at a
                    // time, and trimming here would join words in the accumulated presentation.
                    guard !fragment.isEmpty, fragment != lastReasoningText else {
                        continue
                    }
                    lastReasoningText = fragment
                    await onReasoning?(fragment)
                case .usage(let usage):
                    await onUsage?(usage)
                }
            }
        } catch {
            if let visibleText = preview.finalPreview(from: rawActionText) {
                await onVisibleAssistantText?(visibleText)
            }
            throw error
        }

        if let visibleText = preview.finalPreview(from: rawActionText) {
            await onVisibleAssistantText?(visibleText)
        }
        return try parseAction(from: rawActionText, emptyError: emptyError())
    }

    private static func checkedByteCount(
        current: Int,
        adding additional: Int,
        maximum: Int
    ) throws -> Int {
        guard additional <= maximum - current else {
            throw AgentError.streamingActionTooLarge(maximumBytes: maximum)
        }
        return current + additional
    }

    static func parseAction(from text: String, emptyError: @autoclosure () -> any Error) throws -> AgentAction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw emptyError()
        }
        return try AgentActionJSONParser.parse(trimmed)
    }
}

extension AsyncThrowingStream where Element == String, Failure == Error {
    func asAgentTextEvents() -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        AsyncThrowingStream<AgentTextStreamEvent, Error> { continuation in
            let task = Task {
                do {
                    for try await chunk in self {
                        continuation.yield(.text(chunk))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public enum AgentActionStreamPreview {
    public static func visibleAssistantText(from rawActionText: String) -> String? {
        guard streamedActionType(from: rawActionText) == "say" else {
            return nil
        }
        return visibleAssistantTextForKnownSayAction(from: rawActionText)
    }

    static func streamedActionType(from rawActionText: String) -> String? {
        partialJSONStringValue(for: "type", in: rawActionText)
    }

    static func visibleAssistantTextForKnownSayAction(from rawActionText: String) -> String? {
        partialJSONStringValue(for: "text", in: rawActionText)
    }

    private static func partialJSONStringValue(for key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\"\(key)\""),
              let colonIndex = text[keyRange.upperBound...].firstIndex(of: ":")
        else {
            return nil
        }

        var index = text.index(after: colonIndex)
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "\"" else {
            return nil
        }

        index = text.index(after: index)
        var value = ""
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                return value
            }
            if character == "\\" {
                let decoded = decodeEscape(in: text, after: index)
                value.append(decoded.character)
                index = decoded.nextIndex
            } else {
                value.append(character)
                index = text.index(after: index)
            }
        }
        return value
    }

    private static func decodeEscape(
        in text: String,
        after slashIndex: String.Index
    ) -> (character: Character, nextIndex: String.Index) {
        let escapeIndex = text.index(after: slashIndex)
        guard escapeIndex < text.endIndex else {
            return ("\\", escapeIndex)
        }

        let nextIndex = text.index(after: escapeIndex)
        switch text[escapeIndex] {
        case "\"":
            return ("\"", nextIndex)
        case "\\":
            return ("\\", nextIndex)
        case "/":
            return ("/", nextIndex)
        case "b":
            return ("\u{08}", nextIndex)
        case "f":
            return ("\u{0C}", nextIndex)
        case "n":
            return ("\n", nextIndex)
        case "r":
            return ("\r", nextIndex)
        case "t":
            return ("\t", nextIndex)
        case "u":
            return decodeUnicodeEscape(in: text, after: escapeIndex)
        default:
            return (text[escapeIndex], nextIndex)
        }
    }

    private static func decodeUnicodeEscape(
        in text: String,
        after unicodeMarkerIndex: String.Index
    ) -> (character: Character, nextIndex: String.Index) {
        var index = text.index(after: unicodeMarkerIndex)
        var scalarText = ""
        for _ in 0..<4 {
            guard index < text.endIndex else {
                return ("u", index)
            }
            scalarText.append(text[index])
            index = text.index(after: index)
        }
        guard let value = UInt32(scalarText, radix: 16),
              let scalar = UnicodeScalar(value)
        else {
            return ("u", index)
        }
        return (Character(scalar), index)
    }
}
