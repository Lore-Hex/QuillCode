import Foundation
import QuillCodeCore

struct WorkspaceToolCardEventReducer<State> {
    var state: State

    private var activeToolCardIndex: Int?
    private var activeApprovalCardIndex: Int?
    private let appendCard: (inout State, ToolCardState) -> Int
    private let card: (State, Int) -> ToolCardState?
    private let replaceCard: (inout State, Int, ToolCardState) -> Void
    private let orphanCardID: (() -> String)?

    init(
        state: State,
        orphanCardID: (() -> String)? = nil,
        appendCard: @escaping (inout State, ToolCardState) -> Int,
        card: @escaping (State, Int) -> ToolCardState?,
        replaceCard: @escaping (inout State, Int, ToolCardState) -> Void
    ) {
        self.state = state
        self.orphanCardID = orphanCardID
        self.appendCard = appendCard
        self.card = card
        self.replaceCard = replaceCard
    }

    mutating func apply(_ event: ThreadEvent) {
        switch event.kind {
        case .toolQueued:
            activeToolCardIndex = appendCard(&state, WorkspaceToolCardProjection.queuedCard(for: event))
        case .toolRunning:
            updateActiveToolCard(status: .running, stateLabel: "Running")
        case .toolProgress:
            updateActiveToolProgress(event)
        case .toolCompleted:
            updateActiveToolCard(status: .done, stateLabel: "Completed", outputJSON: event.payloadJSON)
        case .toolFailed:
            updateActiveToolCard(status: .failed, stateLabel: "Failed", outputJSON: event.payloadJSON)
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
        status: ToolCardStatus,
        stateLabel: String,
        outputJSON: String? = nil
    ) {
        guard let index = activeToolCardIndex,
              var currentCard = card(state, index)
        else {
            appendOrphanCard(status: status, stateLabel: stateLabel, outputJSON: outputJSON)
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
        status: ToolCardStatus,
        stateLabel: String,
        outputJSON: String?
    ) {
        guard let orphanCardID else { return }
        _ = appendCard(&state, WorkspaceToolCardProjection.orphanCard(
            id: orphanCardID(),
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
            orphanCardID: { "orphan-\(UUID().uuidString)" },
            appendCard: { items, card in
                items.append(.toolCard(card))
                return items.count - 1
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

private extension ToolCardStatus {
    var isTerminal: Bool {
        self == .done || self == .failed
    }
}
