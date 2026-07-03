import Foundation
import QuillCodeCore

/// The render-ready "Attention" sidebar section for the morning triage inbox (issue #877). This is the
/// thin, `Codable`/`Hashable` surface both the native SwiftUI sidebar and the HTML harness renderer
/// consume; all the ranking / selection / triage *semantics* live in `QuillCodeCore`'s `AttentionModel`
/// (shared, pure, tested) so the two surfaces cannot drift.
public struct AttentionSectionSurface: Codable, Sendable, Hashable {
    /// The severity-ranked rows (RED first, then UNVERIFIED). Empty when nothing needs attention.
    public var rows: [AttentionRowSurface]
    /// The thread id the triage cursor is on, or nil when the section is empty.
    public var selectedThreadID: UUID?

    public init(rows: [AttentionRowSurface] = [], selectedThreadID: UUID? = nil) {
        self.rows = rows
        self.selectedThreadID = selectedThreadID
    }

    public var isEmpty: Bool { rows.isEmpty }

    /// Build the section surface from the pure model plus the current sidebar selection. The section's
    /// own cursor prefers the model's selection but falls back so a selected attention thread stays
    /// highlighted when it is the sidebar's selected thread too.
    public init(model: AttentionModel) {
        self.rows = model.items.map(AttentionRowSurface.init)
        self.selectedThreadID = model.selectedThreadID
    }
}

/// One row of the Attention section: the verdict badge, thread title, one-line summary, and the unseen
/// turn count, plus whether this row is the current triage cursor.
public struct AttentionRowSurface: Codable, Sendable, Hashable, Identifiable {
    public var threadID: UUID
    public var title: String
    public var verdict: TriageVerdict
    public var badgeLabel: String
    public var summary: String
    public var unseenCount: Int
    public var unseenLabel: String?

    public var id: UUID { threadID }

    public init(item: AttentionItem) {
        self.threadID = item.threadID
        self.title = item.title
        self.verdict = item.verdict
        self.badgeLabel = item.verdict.badgeLabel
        self.summary = item.summary
        self.unseenCount = item.unseenCount
        self.unseenLabel = item.unseenLabel
    }

    public init(
        threadID: UUID,
        title: String,
        verdict: TriageVerdict,
        summary: String,
        unseenCount: Int
    ) {
        self.threadID = threadID
        self.title = title
        self.verdict = verdict
        self.badgeLabel = verdict.badgeLabel
        self.summary = summary
        self.unseenCount = max(0, unseenCount)
        self.unseenLabel = unseenCount == 0 ? nil : "\(max(0, unseenCount)) new"
    }
}

/// The render-ready return digest card (issue #877). Mirrors `QuillCodeCore.TriageDigest` as a
/// `Codable`/`Hashable` surface for the two render paths.
public struct AttentionDigestSurface: Codable, Sendable, Hashable {
    public var threadID: UUID
    public var title: String
    public var verdict: TriageVerdict?
    public var badgeLabel: String?
    public var verdictSummary: String
    public var reasons: [String]
    public var outcome: String
    public var unseenCount: Int
    public var unseenSeamLabel: String?

    public init(digest: TriageDigest) {
        self.threadID = digest.threadID
        self.title = digest.title
        self.verdict = digest.verdict
        self.badgeLabel = digest.verdict?.badgeLabel
        self.verdictSummary = digest.verdictSummary
        self.reasons = digest.reasons
        self.outcome = digest.outcome
        self.unseenCount = digest.unseenCount
        self.unseenSeamLabel = digest.unseenSeamLabel
    }
}
