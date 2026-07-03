import Foundation

/// One row in the Attention section: a thread that needs morning triage.
public struct AttentionItem: Sendable, Hashable, Identifiable {
    public var threadID: UUID
    public var title: String
    public var verdict: TriageVerdict
    public var summary: String
    public var unseenCount: Int
    public var updatedAt: Date

    public var id: UUID { threadID }

    public init(
        threadID: UUID,
        title: String,
        verdict: TriageVerdict,
        summary: String,
        unseenCount: Int,
        updatedAt: Date
    ) {
        self.threadID = threadID
        self.title = title
        self.verdict = verdict
        self.summary = summary
        self.unseenCount = max(0, unseenCount)
        self.updatedAt = updatedAt
    }

    public var unseenLabel: String? {
        unseenCount == 0 ? nil : "\(unseenCount) new"
    }
}

/// Ranked Attention rows plus the preview cursor used by j/k navigation.
public struct AttentionModel: Sendable, Hashable {
    public private(set) var items: [AttentionItem]
    public private(set) var selectedThreadID: UUID?

    public init(items: [AttentionItem], selectedThreadID: UUID? = nil) {
        let ranked = Self.rank(items)
        self.items = ranked
        if let selectedThreadID, ranked.contains(where: { $0.threadID == selectedThreadID }) {
            self.selectedThreadID = selectedThreadID
        } else {
            self.selectedThreadID = ranked.first?.threadID
        }
    }

    public static func rank(_ items: [AttentionItem]) -> [AttentionItem] {
        items.sorted { lhs, rhs in
            if lhs.verdict.severity != rhs.verdict.severity {
                return lhs.verdict.severity > rhs.verdict.severity
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.threadID.uuidString < rhs.threadID.uuidString
        }
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public var selectedIndex: Int? {
        guard let selectedThreadID else { return nil }
        return items.firstIndex { $0.threadID == selectedThreadID }
    }

    public var selectedItem: AttentionItem? {
        guard let index = selectedIndex else { return nil }
        return items[index]
    }

    public mutating func moveDown() {
        guard let index = selectedIndex else { return }
        let next = min(index + 1, items.count - 1)
        selectedThreadID = items[next].threadID
    }

    public mutating func moveUp() {
        guard let index = selectedIndex else { return }
        let prev = max(index - 1, 0)
        selectedThreadID = items[prev].threadID
    }

    public mutating func select(_ threadID: UUID) {
        guard items.contains(where: { $0.threadID == threadID }) else { return }
        selectedThreadID = threadID
    }

    public static func build(
        from threads: [ChatThread],
        selectedThreadID: UUID? = nil
    ) -> AttentionModel {
        let items: [AttentionItem] = threads.compactMap { thread in
            guard let stamp = TriageStamp.derive(from: thread), stamp.verdict.needsAttention else {
                return nil
            }
            guard ThreadTriageRecord.needsAttention(in: thread) else { return nil }
            return AttentionItem(
                threadID: thread.id,
                title: thread.title,
                verdict: stamp.verdict,
                summary: stamp.summary,
                unseenCount: ThreadReturnWatermarkRecord.unseenCount(in: thread),
                updatedAt: thread.updatedAt
            )
        }
        return AttentionModel(items: items, selectedThreadID: selectedThreadID)
    }
}
