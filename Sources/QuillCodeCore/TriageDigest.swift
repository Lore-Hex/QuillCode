import Foundation

/// The per-thread **return digest** (issue #877): a compact card the user lands on when they press
/// Enter on an Attention row. It summarizes one overnight run so the user can trust it without reading
/// the whole transcript — the integrity verdict + reasons, the final outcome, and an "unseen turns since
/// last viewed" seam so they see exactly what changed.
///
/// Pure and deterministic: built from a `ChatThread` plus its unseen-turn count (which the app derives
/// from the reused `TranscriptNewTurns` marker). No SwiftUI, so both surfaces render the same content.
public struct TriageDigest: Sendable, Hashable {
    public var threadID: UUID
    public var title: String
    /// The persisted integrity verdict, or `nil` if the thread was never scanned.
    public var verdict: TriageVerdict?
    /// The one-line verdict summary from the persisted record (the top reason). Empty when unavailable.
    public var verdictSummary: String
    /// The full reason list, re-derived from the transcript for the card body. Empty for a clean or
    /// never-scanned run. (The persisted record keeps only the summary line; the reasons are cheap to
    /// re-scan and give the card its detail.)
    public var reasons: [String]
    /// A one-line description of how the run ended (its final outcome).
    public var outcome: String
    /// The number of transcript turns that arrived since the user last viewed this thread — the unseen
    /// seam. Always ≥ 0.
    public var unseenCount: Int

    public init(
        threadID: UUID,
        title: String,
        verdict: TriageVerdict?,
        verdictSummary: String,
        reasons: [String],
        outcome: String,
        unseenCount: Int
    ) {
        self.threadID = threadID
        self.title = title
        self.verdict = verdict
        self.verdictSummary = verdictSummary
        self.reasons = reasons
        self.outcome = outcome
        self.unseenCount = max(0, unseenCount)
    }

    /// The unseen-seam label ("N unseen turns"), or `nil` when nothing is unseen.
    public var unseenSeamLabel: String? {
        switch unseenCount {
        case 0: return nil
        case 1: return "1 unseen turn"
        default: return "\(unseenCount) unseen turns"
        }
    }

    /// Build a digest for a thread. `unseenCount` is supplied by the caller (the app computes it from
    /// the reused `TranscriptNewTurns` marker so the seam matches the transcript pill exactly).
    public static func build(for thread: ChatThread, unseenCount: Int) -> TriageDigest {
        let stamp = TriageStamp.derive(from: thread)
        // The persisted record keeps only the summary line; re-scan for the full reason list to populate
        // the card body. This is a read-only derivation and does not touch the persisted verdict.
        let reasons: [String]
        if stamp != nil {
            reasons = RunIntegrityScanner.scan(thread).reasons.map(\.detail)
        } else {
            reasons = []
        }
        return TriageDigest(
            threadID: thread.id,
            title: thread.title,
            verdict: stamp?.verdict,
            verdictSummary: stamp?.summary ?? "",
            reasons: reasons,
            outcome: outcomeLine(for: thread),
            unseenCount: unseenCount
        )
    }

    /// A one-line "how the run ended" summary drawn from the thread's final assistant message, falling
    /// back to a neutral line when the thread has no assistant reply yet.
    static func outcomeLine(for thread: ChatThread) -> String {
        guard let final = thread.messages.last(where: { $0.role == .assistant })?.content else {
            return "No final answer recorded."
        }
        return firstLine(of: final, maxLength: 140)
    }

    /// The first non-empty line of `text`, truncated to `maxLength` with an ellipsis. Never returns an
    /// empty string for non-empty input.
    static func firstLine(of text: String, maxLength: Int) -> String {
        let firstNonEmpty = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        let line = (firstNonEmpty ?? text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard line.count > maxLength else { return line }
        let end = line.index(line.startIndex, offsetBy: maxLength)
        return String(line[line.startIndex..<end]).trimmingCharacters(in: .whitespaces) + "…"
    }
}
