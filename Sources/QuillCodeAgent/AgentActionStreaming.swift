import Foundation
import QuillCodeCore

public enum AgentTextStreamEvent: Sendable, Hashable {
    case text(String)
    case reasoning(String)
    case usage(ModelTokenUsage)
}

public enum AgentActionStreamCollector {
    public static func collectText(from stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var text = ""
        for try await chunk in stream {
            try Task.checkCancellation()
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
        var rawActionText = ""
        var lastVisibleText = ""
        var lastReasoningText = ""
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .text(let chunk):
                rawActionText.append(chunk)
                guard let visibleText = AgentActionStreamPreview.visibleAssistantText(from: rawActionText),
                      !visibleText.isEmpty,
                      !AgentPromisedWorkGuard.shouldSuppressStreamingPreview(for: visibleText),
                      visibleText != lastVisibleText
                else {
                    continue
                }
                lastVisibleText = visibleText
                await onVisibleAssistantText?(visibleText)
            case .reasoning(let summary):
                let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != lastReasoningText else {
                    continue
                }
                lastReasoningText = trimmed
                await onReasoning?(trimmed)
            case .usage(let usage):
                await onUsage?(usage)
            }
        }

        return try parseAction(from: rawActionText, emptyError: emptyError())
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
        guard partialJSONStringValue(for: "type", in: rawActionText) == "say" else {
            return nil
        }
        return partialJSONStringValue(for: "text", in: rawActionText)
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
