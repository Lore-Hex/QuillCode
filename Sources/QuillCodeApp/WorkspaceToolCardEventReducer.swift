import Foundation
import QuillCodeCore

struct WorkspaceToolCardEventReducer<State> {
    var state: State

    private var activeToolCardIndex: Int?
    private var activeApprovalCardIndex: Int?
    private let appendCard: (inout State, ToolCardState) -> Int
    private let appendOrphanCard: ((inout State, ToolCardState) -> Void)?
    private let card: (State, Int) -> ToolCardState?
    private let replaceCard: (inout State, Int, ToolCardState) -> Void

    init(
        state: State,
        appendCard: @escaping (inout State, ToolCardState) -> Int,
        appendOrphanCard: ((inout State, ToolCardState) -> Void)? = nil,
        card: @escaping (State, Int) -> ToolCardState?,
        replaceCard: @escaping (inout State, Int, ToolCardState) -> Void
    ) {
        self.state = state
        self.appendCard = appendCard
        self.appendOrphanCard = appendOrphanCard
        self.card = card
        self.replaceCard = replaceCard
    }

    mutating func apply(_ event: ThreadEvent) {
        switch event.kind {
        case .toolQueued:
            activeToolCardIndex = appendCard(&state, WorkspaceToolCardProjection.queuedCard(for: event))
        case .toolRunning:
            updateActiveToolCard(for: event, status: .running, stateLabel: "Running")
        case .toolProgress:
            updateActiveToolProgress(event)
        case .toolCompleted:
            updateActiveToolCard(
                for: event,
                status: .done,
                stateLabel: "Completed",
                outputJSON: event.payloadJSON
            )
        case .toolFailed:
            updateActiveToolCard(
                for: event,
                status: .failed,
                stateLabel: "Failed",
                outputJSON: event.payloadJSON
            )
        case .approvalRequested:
            replaceActiveToolWithApproval(for: event)
        case .approvalDecided:
            updateActiveApprovalCard(decisionJSON: event.payloadJSON)
        case .message, .messageFeedback, .reviewComment, .notice:
            return
        }
    }

    private mutating func updateActiveToolProgress(_ event: ThreadEvent) {
        guard let index = activeToolCardIndex,
              var currentCard = card(state, index),
              WorkspaceToolCardProjection.updateProgressCard(&currentCard, event: event)
        else {
            return
        }
        replaceCard(&state, index, currentCard)
    }

    private mutating func updateActiveToolCard(
        for event: ThreadEvent,
        status: ToolCardStatus,
        stateLabel: String,
        outputJSON: String? = nil
    ) {
        guard let index = activeToolCardIndex,
              var currentCard = card(state, index)
        else {
            appendOrphanCard(
                for: event,
                status: status,
                stateLabel: stateLabel,
                outputJSON: outputJSON
            )
            return
        }

        WorkspaceToolCardProjection.updateCard(
            &currentCard,
            status: status,
            stateLabel: stateLabel,
            outputJSON: outputJSON
        )
        replaceCard(&state, index, currentCard)
        if status.isTerminal {
            activeToolCardIndex = nil
        }
    }

    private mutating func appendOrphanCard(
        for event: ThreadEvent,
        status: ToolCardStatus,
        stateLabel: String,
        outputJSON: String?
    ) {
        guard let appendOrphanCard else { return }
        appendOrphanCard(&state, WorkspaceToolCardProjection.orphanCard(
            id: "orphan-\(event.id.uuidString.lowercased())",
            status: status,
            stateLabel: stateLabel,
            outputJSON: outputJSON
        ))
    }

    private mutating func replaceActiveToolWithApproval(for event: ThreadEvent) {
        let fallback = activeToolCardIndex.flatMap { card(state, $0) }
        let reviewCard = WorkspaceToolCardProjection.approvalReviewCard(for: event, fallback: fallback)

        if let index = activeToolCardIndex,
           card(state, index) != nil {
            replaceCard(&state, index, reviewCard)
            activeApprovalCardIndex = index
            activeToolCardIndex = nil
            return
        }

        activeApprovalCardIndex = appendCard(&state, reviewCard)
    }

    private mutating func updateActiveApprovalCard(decisionJSON: String?) {
        guard let index = activeApprovalCardIndex,
              var currentCard = card(state, index)
        else {
            return
        }
        WorkspaceToolCardProjection.updateApprovalCard(&currentCard, decisionJSON: decisionJSON)
        replaceCard(&state, index, currentCard)
        activeApprovalCardIndex = nil
    }
}

extension WorkspaceToolCardEventReducer where State == [ToolCardState] {
    static func toolCardList() -> Self {
        Self(
            state: [],
            appendCard: { cards, card in
                cards.append(card)
                return cards.count - 1
            },
            card: { cards, index in
                cards.indices.contains(index) ? cards[index] : nil
            },
            replaceCard: { cards, index, card in
                guard cards.indices.contains(index) else { return }
                cards[index] = card
            }
        )
    }
}

extension WorkspaceToolCardEventReducer where State == [TranscriptTimelineItemSurface] {
    static func timeline() -> Self {
        Self(
            state: [],
            appendCard: { items, card in
                items.append(.toolCard(card))
                return items.count - 1
            },
            appendOrphanCard: { items, card in
                items.append(.toolCard(card))
            },
            card: { items, index in
                guard items.indices.contains(index) else { return nil }
                return items[index].toolCard
            },
            replaceCard: { items, index, card in
                guard items.indices.contains(index) else { return }
                items[index] = .toolCard(card)
            }
        )
    }
}

struct WorkspaceTranscriptProjectionAccumulator {
    var toolCards: [ToolCardState] = []
    var timelineItems: [TranscriptTimelineItemSurface] = []
    private var timelineIndexByToolCardIndex: [Int] = []

    init(toolCardCapacity: Int, timelineCapacity: Int) {
        toolCards.reserveCapacity(toolCardCapacity)
        timelineItems.reserveCapacity(timelineCapacity)
        timelineIndexByToolCardIndex.reserveCapacity(toolCardCapacity)
    }

    mutating func appendMessage(_ message: MessageSurface) {
        timelineItems.append(.message(message))
    }

    mutating func appendToolCard(_ card: ToolCardState) -> Int {
        let cardIndex = toolCards.count
        toolCards.append(card)
        timelineIndexByToolCardIndex.append(timelineItems.count)
        timelineItems.append(.toolCard(card))
        return cardIndex
    }

    mutating func appendOrphanToolCard(_ card: ToolCardState) {
        timelineItems.append(.toolCard(card))
    }

    func toolCard(at index: Int) -> ToolCardState? {
        toolCards.indices.contains(index) ? toolCards[index] : nil
    }

    mutating func replaceToolCard(at index: Int, with card: ToolCardState) {
        guard toolCards.indices.contains(index),
              timelineIndexByToolCardIndex.indices.contains(index)
        else {
            return
        }
        let timelineIndex = timelineIndexByToolCardIndex[index]
        guard timelineItems.indices.contains(timelineIndex) else { return }
        toolCards[index] = card
        timelineItems[timelineIndex] = .toolCard(card)
    }

    mutating func synchronizeToolCardsFromTimeline() {
        for cardIndex in toolCards.indices {
            guard timelineIndexByToolCardIndex.indices.contains(cardIndex) else { continue }
            let timelineIndex = timelineIndexByToolCardIndex[cardIndex]
            guard timelineItems.indices.contains(timelineIndex),
                  let timelineCard = timelineItems[timelineIndex].toolCard
            else {
                continue
            }
            toolCards[cardIndex] = timelineCard
        }
    }
}

extension WorkspaceToolCardEventReducer where State == WorkspaceTranscriptProjectionAccumulator {
    static func transcriptProjection(state: State) -> Self {
        Self(
            state: state,
            appendCard: { state, card in
                state.appendToolCard(card)
            },
            appendOrphanCard: { state, card in
                state.appendOrphanToolCard(card)
            },
            card: { state, index in
                state.toolCard(at: index)
            },
            replaceCard: { state, index, card in
                state.replaceToolCard(at: index, with: card)
            }
        )
    }
}

private extension ToolCardStatus {
    var isTerminal: Bool {
        self == .done || self == .failed
    }
}
