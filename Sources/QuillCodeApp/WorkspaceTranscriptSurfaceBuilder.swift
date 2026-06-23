import Foundation
import QuillCodeCore

struct WorkspaceTranscriptSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread

    func messageSurfaces() -> [MessageSurface] {
        let feedbackByMessageID = Self.messageFeedbackByMessageID(for: thread)
        return thread.messages
            .filter { $0.role != .tool }
            .map { message in
                MessageSurface(message: message, feedback: feedbackByMessageID[message.id])
            }
    }

    func toolCards() -> [ToolCardState] {
        var cards: [ToolCardState] = []
        var activeToolCardIndex: Int?

        func updateActiveToolCard(status: ToolCardStatus, subtitle: String, outputJSON: String? = nil) {
            guard let index = activeToolCardIndex else {
                return
            }
            Self.updateCard(&cards, at: index, status: status, subtitle: subtitle, outputJSON: outputJSON)
            if status.isTerminal {
                activeToolCardIndex = nil
            }
        }

        for event in thread.events {
            switch event.kind {
            case .toolQueued:
                let call = Self.decode(ToolCall.self, event.payloadJSON)
                cards.append(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: call?.name ?? "Tool",
                    subtitle: "Queued",
                    status: .queued,
                    inputJSON: call?.argumentsJSON ?? event.payloadJSON
                ))
                activeToolCardIndex = cards.count - 1
            case .toolRunning:
                updateActiveToolCard(status: .running, subtitle: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    subtitle: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                cards.append(Self.safetyReviewCard(for: event))
            case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice:
                continue
            }
        }

        return cards
    }

    func timelineItems() -> [TranscriptTimelineItemSurface] {
        guard !thread.events.isEmpty else {
            return messageSurfaces().map(TranscriptTimelineItemSurface.message)
                + toolCards().map(TranscriptTimelineItemSurface.toolCard)
        }

        let feedbackByMessageID = Self.messageFeedbackByMessageID(for: thread)
        var consumedMessageIDs = Set<UUID>()
        var items: [TranscriptTimelineItemSurface] = []
        var activeToolItemIndex: Int?

        func appendMessage(matching summary: String) {
            guard let message = thread.messages.first(where: {
                !consumedMessageIDs.contains($0.id) && $0.content == summary
            }) else {
                return
            }
            consumedMessageIDs.insert(message.id)
            items.append(.message(MessageSurface(message: message, feedback: feedbackByMessageID[message.id])))
        }

        func appendToolCard(_ card: ToolCardState) {
            items.append(.toolCard(card))
            activeToolItemIndex = items.count - 1
        }

        func updateActiveToolCard(status: ToolCardStatus, subtitle: String, outputJSON: String? = nil) {
            guard let index = activeToolItemIndex,
                  var card = items[index].toolCard
            else {
                appendToolCard(ToolCardState(
                    id: "orphan-\(UUID().uuidString)",
                    title: "Tool",
                    subtitle: subtitle,
                    status: status,
                    outputJSON: outputJSON,
                    artifacts: outputJSON.map(Self.artifacts(from:)) ?? []
                ))
                return
            }
            Self.updateCard(&card, status: status, subtitle: subtitle, outputJSON: outputJSON)
            items[index] = .toolCard(card)
            if status.isTerminal {
                activeToolItemIndex = nil
            }
        }

        for event in thread.events {
            switch event.kind {
            case .message:
                appendMessage(matching: event.summary)
            case .toolQueued:
                let call = Self.decode(ToolCall.self, event.payloadJSON)
                appendToolCard(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: call?.name ?? "Tool",
                    subtitle: "Queued",
                    status: .queued,
                    inputJSON: call?.argumentsJSON ?? event.payloadJSON
                ))
            case .toolRunning:
                updateActiveToolCard(status: .running, subtitle: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    subtitle: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                items.append(.toolCard(Self.safetyReviewCard(for: event)))
            case .messageFeedback, .approvalDecided, .reviewComment, .notice:
                continue
            }
        }

        for message in thread.messages where message.role != .tool && !consumedMessageIDs.contains(message.id) {
            items.append(.message(MessageSurface(message: message, feedback: feedbackByMessageID[message.id])))
        }
        return items
    }

    private static func safetyReviewCard(for event: ThreadEvent) -> ToolCardState {
        ToolCardState(
            id: event.id.uuidString,
            title: "Safety Check",
            subtitle: event.summary,
            status: .review,
            inputJSON: event.payloadJSON,
            isExpanded: true
        )
    }

    private static func updateCard(
        _ cards: inout [ToolCardState],
        at index: Int,
        status: ToolCardStatus,
        subtitle: String,
        outputJSON: String? = nil
    ) {
        guard cards.indices.contains(index) else { return }
        updateCard(&cards[index], status: status, subtitle: subtitle, outputJSON: outputJSON)
    }

    private static func updateCard(
        _ card: inout ToolCardState,
        status: ToolCardStatus,
        subtitle: String,
        outputJSON: String? = nil
    ) {
        card.status = status
        card.subtitle = subtitle
        card.density = ToolCardState.defaultDensity(status: status, isExpanded: card.isExpanded)
        card.isExpanded = card.density == .expanded
        if let outputJSON {
            card.outputJSON = outputJSON
            card.artifacts = artifacts(from: outputJSON)
        }
    }

    private static func artifacts(from outputJSON: String) -> [ToolArtifactState] {
        guard let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON) else {
            return []
        }
        return result.artifacts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { value in
                ToolArtifactState(value: value, textPreview: ToolArtifactPreviewBuilder.textPreview(for: value))
            }
    }

    private static func messageFeedbackByMessageID(for thread: ChatThread) -> [UUID: MessageFeedbackValue] {
        var feedbackByMessageID: [UUID: MessageFeedbackValue] = [:]
        for event in thread.events where event.kind == .messageFeedback {
            guard let feedback = decode(MessageFeedback.self, event.payloadJSON) else { continue }
            feedbackByMessageID[feedback.messageID] = feedback.value
        }
        return feedbackByMessageID
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}

private extension ToolCardStatus {
    var isTerminal: Bool {
        self == .done || self == .failed
    }
}
