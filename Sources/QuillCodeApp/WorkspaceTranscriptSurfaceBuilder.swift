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
        var activeApprovalCardIndex: Int?

        func updateActiveToolCard(status: ToolCardStatus, stateLabel: String, outputJSON: String? = nil) {
            guard let index = activeToolCardIndex else {
                return
            }
            Self.updateCard(&cards, at: index, status: status, stateLabel: stateLabel, outputJSON: outputJSON)
            if status.isTerminal {
                activeToolCardIndex = nil
            }
        }

        for event in thread.events {
            switch event.kind {
            case .toolQueued:
                let call = Self.decode(ToolCall.self, event.payloadJSON)
                let title = call?.name ?? "Tool"
                let inputJSON = call?.argumentsJSON ?? event.payloadJSON
                cards.append(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: title,
                    subtitle: Self.toolSubtitle(stateLabel: "Queued", title: title, inputJSON: inputJSON),
                    status: .queued,
                    inputJSON: inputJSON
                ))
                activeToolCardIndex = cards.count - 1
            case .toolRunning:
                updateActiveToolCard(status: .running, stateLabel: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    stateLabel: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    stateLabel: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                let reviewCard = Self.approvalReviewCard(
                    for: event,
                    fallback: activeToolCardIndex.flatMap { cards.indices.contains($0) ? cards[$0] : nil }
                )
                if let index = activeToolCardIndex, cards.indices.contains(index) {
                    cards[index] = reviewCard
                    activeApprovalCardIndex = index
                    activeToolCardIndex = nil
                } else {
                    cards.append(reviewCard)
                    activeApprovalCardIndex = cards.count - 1
                }
            case .approvalDecided:
                guard let index = activeApprovalCardIndex, cards.indices.contains(index) else { continue }
                Self.updateApprovalCard(&cards[index], decisionJSON: event.payloadJSON)
                activeApprovalCardIndex = nil
            case .message, .messageFeedback, .reviewComment, .notice:
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
        var activeApprovalItemIndex: Int?

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

        func updateActiveToolCard(status: ToolCardStatus, stateLabel: String, outputJSON: String? = nil) {
            guard let index = activeToolItemIndex,
                  var card = items[index].toolCard
            else {
                appendToolCard(ToolCardState(
                    id: "orphan-\(UUID().uuidString)",
                    title: "Tool",
                    subtitle: stateLabel,
                    status: status,
                    outputJSON: outputJSON,
                    artifacts: outputJSON.map(Self.artifacts(from:)) ?? []
                ))
                return
            }
            Self.updateCard(&card, status: status, stateLabel: stateLabel, outputJSON: outputJSON)
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
                let title = call?.name ?? "Tool"
                let inputJSON = call?.argumentsJSON ?? event.payloadJSON
                appendToolCard(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: title,
                    subtitle: Self.toolSubtitle(stateLabel: "Queued", title: title, inputJSON: inputJSON),
                    status: .queued,
                    inputJSON: inputJSON
                ))
            case .toolRunning:
                updateActiveToolCard(status: .running, stateLabel: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    stateLabel: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    stateLabel: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                let fallback = activeToolItemIndex.flatMap { items.indices.contains($0) ? items[$0].toolCard : nil }
                let reviewCard = Self.approvalReviewCard(for: event, fallback: fallback)
                if let index = activeToolItemIndex, items.indices.contains(index) {
                    items[index] = .toolCard(reviewCard)
                    activeApprovalItemIndex = index
                    activeToolItemIndex = nil
                } else {
                    items.append(.toolCard(reviewCard))
                    activeApprovalItemIndex = items.count - 1
                }
            case .approvalDecided:
                guard let index = activeApprovalItemIndex,
                      items.indices.contains(index),
                      var card = items[index].toolCard
                else { continue }
                Self.updateApprovalCard(&card, decisionJSON: event.payloadJSON)
                items[index] = .toolCard(card)
                activeApprovalItemIndex = nil
            case .messageFeedback, .reviewComment, .notice:
                continue
            }
        }

        for message in thread.messages where message.role != .tool && !consumedMessageIDs.contains(message.id) {
            items.append(.message(MessageSurface(message: message, feedback: feedbackByMessageID[message.id])))
        }
        return items
    }

    private static func approvalReviewCard(for event: ThreadEvent, fallback: ToolCardState? = nil) -> ToolCardState {
        let request = decode(ApprovalRequest.self, event.payloadJSON)
        let toolCall = request?.toolCall
        let title = toolCall?.name ?? fallback?.title ?? "Approval needed"
        let inputJSON = toolCall?.argumentsJSON ?? fallback?.inputJSON ?? event.payloadJSON
        let actions = request.flatMap { Self.approvalActions(for: $0) } ?? []

        return ToolCardState(
            id: fallback?.id ?? toolCall?.id ?? event.id.uuidString,
            title: title,
            subtitle: Self.approvalSubtitle(
                title: title,
                inputJSON: inputJSON,
                reason: request?.reason ?? event.summary,
                recommendedVerdict: request?.recommendedVerdict
            ),
            status: .review,
            inputJSON: inputJSON,
            actions: actions,
            isExpanded: true
        )
    }

    private static func approvalActions(for request: ApprovalRequest) -> [ToolCardActionSurface]? {
        guard request.recommendedVerdict != .deny else {
            return nil
        }
        return [
            ToolCardActionSurface(
                title: "Allow once",
                kind: .approve,
                requestID: request.id,
                style: .primary,
                systemImage: "checkmark"
            ),
            ToolCardActionSurface(
                title: "Skip",
                kind: .deny,
                requestID: request.id,
                style: .secondary,
                systemImage: "xmark"
            )
        ]
    }

    private static func approvalSubtitle(
        title: String,
        inputJSON: String?,
        reason: String,
        recommendedVerdict: ApprovalVerdict?
    ) -> String {
        let stateLabel = recommendedVerdict == .deny ? "Blocked" : "Needs your okay"
        let base = toolSubtitle(stateLabel: stateLabel, title: title, inputJSON: inputJSON)
        let cleanedReason = reason
            .replacingOccurrences(of: #"^(approve|deny|clarify):\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedReason.isEmpty,
              cleanedReason != base
        else {
            return base
        }
        return "\(base) · \(cleanedReason)"
    }

    private static func updateApprovalCard(_ card: inout ToolCardState, decisionJSON: String?) {
        let decision = decode(ApprovalDecision.self, decisionJSON)
        let stateLabel: String
        switch decision?.verdict {
        case .approve:
            stateLabel = "Approved"
        case .deny:
            stateLabel = "Skipped"
        case .clarify:
            stateLabel = "Needs detail"
        case .none:
            stateLabel = "Updated"
        }
        card.status = .done
        card.subtitle = toolSubtitle(stateLabel: stateLabel, title: card.title, inputJSON: card.inputJSON)
        card.outputJSON = decisionJSON
        card.actions = []
        card.density = ToolCardState.defaultDensity(status: card.status, isExpanded: false)
        card.isExpanded = false
    }

    private static func updateCard(
        _ cards: inout [ToolCardState],
        at index: Int,
        status: ToolCardStatus,
        stateLabel: String,
        outputJSON: String? = nil
    ) {
        guard cards.indices.contains(index) else { return }
        updateCard(&cards[index], status: status, stateLabel: stateLabel, outputJSON: outputJSON)
    }

    private static func updateCard(
        _ card: inout ToolCardState,
        status: ToolCardStatus,
        stateLabel: String,
        outputJSON: String? = nil
    ) {
        card.status = status
        card.subtitle = toolSubtitle(stateLabel: stateLabel, title: card.title, inputJSON: card.inputJSON)
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

    private static func toolSubtitle(stateLabel: String, title: String, inputJSON: String?) -> String {
        WorkspaceToolCardSubtitleBuilder.subtitle(stateLabel: stateLabel, toolName: title, inputJSON: inputJSON)
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
