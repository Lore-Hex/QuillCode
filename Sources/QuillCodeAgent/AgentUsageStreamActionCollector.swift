import Foundation
import QuillCodeCore

extension AgentRunner {
    static func collectStreamingAction(
        from stream: AsyncThrowingStream<AgentTextStreamEvent, Error>,
        thread: inout ChatThread,
        onProgress: AgentRunProgressHandler?
    ) async throws -> AgentAction {
        var draftThread = thread
        var latestUsage: ModelTokenUsage?
        var reasoning = AgentReasoningStreamAccumulator()
        var sawReasoning = false

        do {
            let action = try await AgentActionStreamCollector.collect(
                from: stream,
                emptyError: AgentError.emptyStreamingResponse,
                onVisibleAssistantText: { visibleText in
                    publishAssistantDraft(visibleText, in: &draftThread)
                    let publish = onProgress
                    await publish?(draftThread)
                },
                onUsage: { usage in
                    latestUsage = usage
                },
                onReasoning: { fragment in
                    sawReasoning = true
                    guard let summary = reasoning.append(fragment) else { return }
                    publishReasoningSummary(summary, in: &draftThread)
                    await onProgress?(draftThread)
                }
            )

            thread = draftThread
            if let latestUsage {
                thread.events.append(ModelTokenUsageEvent.event(usage: latestUsage, modelID: thread.model))
                thread.updatedAt = Date()
                await onProgress?(thread)
            }
            return action
        } catch {
            // Failed completions still cost tokens and may have published visible reasoning. Commit
            // both to the durable thread before classifying the failure so the spend fuse and UI
            // never lose accounting for corrective attempts.
            thread = draftThread
            if let latestUsage {
                thread.events.append(ModelTokenUsageEvent.event(usage: latestUsage, modelID: thread.model))
                thread.updatedAt = Date()
                await onProgress?(thread)
            }
            if sawReasoning,
               let agentError = error as? AgentError,
               case .emptyStreamingResponse = agentError {
                throw AgentReasoningOnlyResponseError()
            }
            throw error
        }
    }
}

/// TrustedRouter providers stream reasoning as either deltas or growing snapshots. Keep a bounded
/// tail for presentation instead of copying every token into a new durable thread event.
struct AgentReasoningStreamAccumulator {
    static let maximumCharacters = 2_048

    private(set) var text = ""
    private var lastPublishedText = ""

    mutating func append(_ fragment: String) -> String? {
        guard !fragment.isEmpty else { return nil }

        if fragment.count > Self.maximumCharacters {
            text = String(fragment.suffix(Self.maximumCharacters))
        } else if !text.isEmpty, fragment.hasPrefix(text), fragment.count > text.count {
            text = fragment
        } else {
            text.append(fragment)
        }
        if text.count > Self.maximumCharacters {
            text = String(text.suffix(Self.maximumCharacters))
        }

        let presentation = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !presentation.isEmpty, presentation != lastPublishedText else { return nil }
        lastPublishedText = presentation
        return presentation
    }
}
