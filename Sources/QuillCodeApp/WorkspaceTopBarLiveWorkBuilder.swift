import Foundation
import QuillCodeCore

struct WorkspaceTopBarLiveWorkBuilder: Sendable, Hashable {
    var thread: ChatThread?

    func surface() -> TopBarLiveWorkSurface? {
        guard let thread else { return nil }
        let cards = WorkspaceTranscriptSurfaceBuilder(thread: thread).toolCards()
        return Self.surface(from: cards)
    }

    static func surface(from cards: [ToolCardState]) -> TopBarLiveWorkSurface? {
        let activeCards = cards.filter(\.status.isLiveWork)
        guard !activeCards.isEmpty else { return nil }

        let reviewCount = activeCards.filter { $0.status == .review }.count
        let runningCount = activeCards.filter { $0.status == .running }.count
        let queuedCount = activeCards.filter { $0.status == .queued }.count
        let primary = activeCards.first(where: { $0.status == .running })
            ?? activeCards.first(where: { $0.status == .review })
            ?? activeCards[0]

        return TopBarLiveWorkSurface(
            label: label(for: primary, activeCount: activeCards.count),
            detail: detail(
                primary: primary,
                activeCards: activeCards,
                runningCount: runningCount,
                queuedCount: queuedCount,
                reviewCount: reviewCount
            ),
            tone: reviewCount > 0 ? .review : .running
        )
    }

    private static func label(for primary: ToolCardState, activeCount: Int) -> String {
        if activeCount == 1 {
            return "\(primary.status.topBarVerb) \(primary.title)"
        }
        return "\(activeCount) active tasks"
    }

    private static func detail(
        primary: ToolCardState,
        activeCards: [ToolCardState],
        runningCount: Int,
        queuedCount: Int,
        reviewCount: Int
    ) -> String {
        let counts = [
            countPhrase(runningCount, noun: "running"),
            countPhrase(queuedCount, noun: "queued"),
            countPhrase(reviewCount, noun: "awaiting review"),
        ].compactMap { $0 }
        let titleList = activeCards.prefix(4).map(\.title).joined(separator: ", ")
        let overflow = activeCards.count > 4 ? " and \(activeCards.count - 4) more" : ""
        return "Current work: \(counts.joined(separator: ", ")). Focus: \(primary.title). Active tools: \(titleList)\(overflow)."
    }

    private static func countPhrase(_ count: Int, noun: String) -> String? {
        count > 0 ? "\(count) \(noun)" : nil
    }
}

private extension ToolCardStatus {
    var isLiveWork: Bool {
        switch self {
        case .queued, .running, .review:
            return true
        case .done, .failed:
            return false
        }
    }

    var topBarVerb: String {
        switch self {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .review:
            return "Review"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        }
    }
}
