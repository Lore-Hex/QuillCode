import Foundation
import QuillCodeCore
import TrustedRouter
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum TrustedRouterStreamingEventDecoder {
    static func eventStream(
        from bytes: TrustedRouterByteStream
    ) -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        let chunks = iterSseEvents(bytes: bytes, type: UsageChatCompletionChunk.self)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in chunks {
                        yieldEvents(from: chunk, to: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    #if !os(Linux)
    /// Decodes URLSession bytes directly so a reasoning-budget cancellation can tear down the
    /// network task. The SDK's byte-stream adapter is intentionally not used here: its unbounded
    /// producer can drain a multi-megabyte response before downstream budget guards are scheduled.
    static func eventStream<Bytes>(
        from bytes: Bytes,
        onTermination: @escaping @Sendable () -> Void
    ) -> AsyncThrowingStream<AgentTextStreamEvent, Error>
    where Bytes: AsyncSequence & Sendable, Bytes.Element == UInt8 {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(1)) { continuation in
            let producer = Task {
                do {
                    var frame = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        frame.append(byte)
                        guard isFrameBoundary(frame) else { continue }
                        if let chunk = decodeFrame(frame) {
                            for event in events(from: chunk) {
                                try await yieldWithBackpressure(event, to: continuation)
                            }
                        }
                        frame.removeAll(keepingCapacity: true)
                    }
                    if !frame.isEmpty, let chunk = decodeFrame(frame) {
                        for event in events(from: chunk) {
                            try await yieldWithBackpressure(event, to: continuation)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                producer.cancel()
                onTermination()
            }
        }
    }

    private static func yieldWithBackpressure(
        _ event: AgentTextStreamEvent,
        to continuation: AsyncThrowingStream<AgentTextStreamEvent, Error>.Continuation
    ) async throws {
        while true {
            try Task.checkCancellation()
            switch continuation.yield(event) {
            case .enqueued:
                return
            case .dropped:
                await Task.yield()
            case .terminated:
                throw CancellationError()
            @unknown default:
                throw CancellationError()
            }
        }
    }

    private static func isFrameBoundary(_ data: Data) -> Bool {
        (data.count >= 2 && data.suffix(2) == Data([10, 10]))
            || (data.count >= 4 && data.suffix(4) == Data([13, 10, 13, 10]))
    }

    private static func decodeFrame(_ data: Data) -> UsageChatCompletionChunk? {
        guard let frame = String(data: data, encoding: .utf8) else { return nil }
        let payload = frame.components(separatedBy: .newlines).compactMap { line -> String? in
            guard line.hasPrefix("data:") else { return nil }
            return line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty, payload != "[DONE]", let encoded = payload.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(UsageChatCompletionChunk.self, from: encoded)
    }
    #endif

    private static func yieldEvents(
        from chunk: UsageChatCompletionChunk,
        to continuation: AsyncThrowingStream<AgentTextStreamEvent, Error>.Continuation
    ) {
        for event in events(from: chunk) {
            continuation.yield(event)
        }
    }

    private static func events(from chunk: UsageChatCompletionChunk) -> [AgentTextStreamEvent] {
        var events: [AgentTextStreamEvent] = []
        if let reasoning = chunk.choices.first?.delta?.reasoning, !reasoning.isEmpty {
            events.append(.reasoning(reasoning))
        }
        if let content = chunk.choices.first?.delta?.content, !content.isEmpty {
            events.append(.text(content))
        }
        if let usage = chunk.usage {
            events.append(.usage(usage))
        }
        return events
    }
}

private struct UsageChatCompletionChunk: Decodable {
    var choices: [Choice]
    var usage: ModelTokenUsage?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        self.usage = try container.decodeIfPresent(ModelTokenUsage.self, forKey: .usage)
    }

    private enum CodingKeys: String, CodingKey {
        case choices
        case usage
    }

    struct Choice: Decodable {
        var delta: Delta?

        struct Delta: Decodable {
            var content: String?
            var reasoning: String?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.content = try container.decodeIfPresent(String.self, forKey: .content)
                self.reasoning = try Self.firstNonEmptyString(in: container, keys: [
                    .reasoningContent,
                    .reasoning,
                    .reasoningSummary
                ])
            }

            private enum CodingKeys: String, CodingKey {
                case content
                case reasoning
                case reasoningContent = "reasoning_content"
                case reasoningSummary = "reasoning_summary"
            }

            private static func firstNonEmptyString(
                in container: KeyedDecodingContainer<CodingKeys>,
                keys: [CodingKeys]
            ) throws -> String? {
                for key in keys {
                    guard let value = try container.decodeIfPresent(String.self, forKey: key),
                          value.contains(where: { !$0.isWhitespace })
                    else {
                        continue
                    }
                    return value
                }
                return nil
            }
        }
    }
}
