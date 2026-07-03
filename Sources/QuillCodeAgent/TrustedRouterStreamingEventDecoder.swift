import Foundation
import QuillCodeCore
import TrustedRouter

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

    private static func yieldEvents(
        from chunk: UsageChatCompletionChunk,
        to continuation: AsyncThrowingStream<AgentTextStreamEvent, Error>.Continuation
    ) {
        if let reasoning = chunk.choices.first?.delta?.reasoning, !reasoning.isEmpty {
            continuation.yield(.reasoning(reasoning))
        }
        if let content = chunk.choices.first?.delta?.content, !content.isEmpty {
            continuation.yield(.text(content))
        }
        if let usage = chunk.usage {
            continuation.yield(.usage(usage))
        }
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
