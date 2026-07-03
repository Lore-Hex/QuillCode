import Foundation

/// # Morning triage inbox (issue #877)
///
/// The morning ritual for unattended daily driving: six overnight runs, reviewable before the coffee
/// cools. This file is the **pure, deterministic core** — no SwiftUI, no persistence side effects — so
/// the native app and the E2E HTML harness can share exactly the same ranking / selection / triage
/// semantics. (The batch this ships in has repeatedly had native-vs-harness divergence bugs; keeping
/// the semantics here, and mirroring them line-for-line in the harness JS, is the defense.)
///
/// The pieces:
/// - `TriageStamp` — a thread's persistent verdict stamp, derived from its latest **persisted**
///   `RunIntegrityRecord` (the Run Integrity badge — never self-report). A thread with no run has no
///   stamp.
/// - `ThreadTriageState` + `ThreadTriageRecord` — the user's triage decision (pending / acknowledged /
///   dismissed), persisted onto the thread as a `.notice` event exactly like `RunIntegrityRecord`, so
///   it round-trips through the existing thread store with zero new plumbing and survives reload.
/// - `AttentionItem` — one row in the Attention section: verdict + title + unseen-turn count.
/// - `AttentionModel` — the ranking (severity order, ties by recency) and a selection cursor with
///   j/k clamping.
/// - `AttentionReducer` — the pure state machine for the j/k/a/d triage keys.

// MARK: - Verdict stamp

/// The severity of a thread's run-integrity verdict, for the triage stamp. This is a **projection** of
/// `RunIntegrityVerdict` with an explicit severity ordering so the Attention section can rank rows and
/// so `verified` is representable but known to be "does not need attention".
public enum TriageVerdict: String, Codable, Sendable, Hashable, CaseIterable {
    /// A test/verify command failed and was left standing — the loudest alarm.
    case red
    /// A success claim is not backed by a passing test, or a test was skipped — honest uncertainty.
    case unverified
    /// Nothing dishonest detected — a clean run. Never surfaced in Attention.
    case verified

    /// Higher = more urgent. Used to rank the Attention section (RED before UNVERIFIED).
    public var severity: Int {
        switch self {
        case .red: return 2
        case .unverified: return 1
        case .verified: return 0
        }
    }

    /// Whether a thread with this verdict belongs in the Attention section at all. A clean `verified`
    /// run does not need the morning triage.
    public var needsAttention: Bool { self != .verified }

    /// The badge text, matching the Run Integrity badge exactly.
    public var badgeLabel: String {
        switch self {
        case .red: return "RED"
        case .unverified: return "UNVERIFIED"
        case .verified: return "VERIFIED"
        }
    }

    public init(_ verdict: RunIntegrityVerdict) {
        switch verdict {
        case .red: self = .red
        case .unverified: self = .unverified
        case .verified: self = .verified
        }
    }
}

/// A thread's persistent triage stamp: the verdict plus the one-line summary from the run-integrity
/// record. `nil` when the thread has never been scanned (no run → no stamp).
public struct TriageStamp: Sendable, Hashable {
    public var verdict: TriageVerdict
    public var summary: String

    public init(verdict: TriageVerdict, summary: String) {
        self.verdict = verdict
        self.summary = summary
    }

    /// Derive the stamp from a thread by reading its latest **persisted** `RunIntegrityRecord`. This is
    /// the verdict SOURCE — the record already written by the Run Integrity feature — not a re-derivation
    /// from the transcript / self-report. Returns `nil` when no record was ever written.
    public static func derive(from thread: ChatThread) -> TriageStamp? {
        guard let payload = RunIntegrityRecord.latest(in: thread) else { return nil }
        return TriageStamp(verdict: TriageVerdict(payload.verdict), summary: payload.summary)
    }
}

// MARK: - Triage state (persisted user decision)

/// The user's triage decision for a thread, defaulting to `pending` (needs review). `acknowledged` and
/// `dismissed` both remove the thread from Attention; they are kept distinct so the digest / history can
/// tell "I read it and it's fine" (a) from "I don't care about this run" (d).
public enum ThreadTriageState: String, Codable, Sendable, Hashable {
    /// Not yet triaged — appears in Attention.
    case pending
    /// The user pressed `a`: acknowledged / read. Removed from Attention.
    case acknowledged
    /// The user pressed `d`: dismissed. Removed from Attention.
    case dismissed

    /// Whether a thread in this triage state should still surface in the Attention section.
    public var isActionable: Bool { self == .pending }
}

/// Persists a `ThreadTriageState` onto a thread as a `.notice` event, mirroring `RunIntegrityRecord`'s
/// convention so it round-trips through the existing thread store and survives reload. The most recent
/// record wins; a thread with no record is `pending` by default.
public enum ThreadTriageRecord {
    /// The well-known summary marker identifying the triage-state notice among a thread's events.
    public static let eventSummary = "thread-triage-state"

    /// The Codable payload stored in the notice event's `payloadJSON`.
    public struct Payload: Codable, Sendable, Hashable {
        public var state: ThreadTriageState
        /// The id of the `RunIntegrityRecord` event this decision was made about. A triage decision is
        /// bound to the SPECIFIC run/verdict it triaged — when a later run re-stamps a fresh integrity
        /// record (new id), the decision is stale and the thread re-opens for triage. `nil` for a
        /// decision made when no integrity record was present, or decoded from an older payload.
        public var verdictRecordID: UUID?

        public init(state: ThreadTriageState, verdictRecordID: UUID? = nil) {
            self.state = state
            self.verdictRecordID = verdictRecordID
        }
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        event.kind == .notice && event.summary == eventSummary
    }

    /// Build the notice event for a triage state bound to the given integrity-record id. Returns nil
    /// only if encoding somehow fails.
    public static func event(for state: ThreadTriageState, verdictRecordID: UUID?) -> ThreadEvent? {
        let payload = Payload(state: state, verdictRecordID: verdictRecordID)
        guard let payloadJSON = try? JSONHelpers.encodePretty(payload) else { return nil }
        return ThreadEvent(kind: .notice, summary: eventSummary, payloadJSON: payloadJSON)
    }

    /// The most recent triage payload on a thread, or nil if none was ever recorded.
    public static func latestPayload(in thread: ChatThread) -> Payload? {
        for event in thread.events.reversed() where isRecord(event) {
            if let payloadJSON = event.payloadJSON,
               let payload = try? JSONHelpers.decode(Payload.self, from: payloadJSON) {
                return payload
            }
        }
        return nil
    }

    /// The current triage state of a thread: the most recently recorded one, or `.pending` if none was
    /// ever recorded (a fresh, un-triaged run is pending review).
    public static func current(in thread: ChatThread) -> ThreadTriageState {
        latestPayload(in: thread)?.state ?? .pending
    }

    /// Whether a thread still needs the morning-triage user's attention, given its persisted triage
    /// decision AND the CURRENT integrity record.
    ///
    /// BLOCKER-1 fix: a triage decision (`acknowledged` / `dismissed`) only silences the thread for the
    /// EXACT run it was made about. If a later run re-stamps the integrity badge (a new record id), the
    /// stale decision no longer applies, so the thread re-surfaces. This is the whole point of the
    /// inbox: a thread that goes RED again after you acked it must come back. A `pending` decision (or
    /// none) is always actionable.
    public static func needsAttention(in thread: ChatThread) -> Bool {
        guard let payload = latestPayload(in: thread), !payload.state.isActionable else {
            return true // pending or never triaged → needs attention
        }
        // Acknowledged/dismissed: only silenced while the triaged run is still the current one.
        let currentRecordID = RunIntegrityRecord.latestRecordID(in: thread)
        return payload.verdictRecordID != currentRecordID
    }

    /// Set the thread's triage state, binding the decision to the thread's CURRENT integrity record so a
    /// later run re-opens triage. Bumps `updatedAt` only when the effective decision actually changes,
    /// so re-recording the same (state, record) is idempotent and does not reshuffle the sidebar.
    @discardableResult
    public static func set(_ state: ThreadTriageState, on thread: inout ChatThread) -> Bool {
        let verdictRecordID = RunIntegrityRecord.latestRecordID(in: thread)
        if let existing = latestPayload(in: thread),
           existing.state == state,
           existing.verdictRecordID == verdictRecordID {
            return false
        }
        thread.events.removeAll(where: isRecord)
        if let event = event(for: state, verdictRecordID: verdictRecordID) {
            thread.events.append(event)
            thread.updatedAt = Date()
            return true
        }
        return false
    }
}

// MARK: - Return watermark (persistent "last viewed" for the unseen-turn seam)

/// The morning-triage "unseen turns" seam is a **cross-session** concept — the whole point is to see
/// what the overnight run added while you were away, across an app restart. So unlike the transcript
/// pill's session-only tracker, the watermark here is persisted onto the thread as a `.notice` event
/// (same convention as the other triage records) and the unseen count is derived from it.
///
/// The count semantics deliberately mirror `TranscriptNewTurnsResolver` in the app layer: it is the
/// suffix length of the message timeline after the watermarked item, so it is never negative; a `nil`
/// watermark (never viewed) yields 0 (nothing to announce); a stale watermark whose item is gone yields
/// 0 (never invent a count). The timeline used is the thread's non-tool messages, whose ids are stable
/// (`message-<uuid>`), matching the transcript timeline item ids for message turns.
public enum ThreadReturnWatermarkRecord {
    /// The well-known summary marker identifying the return-watermark notice among a thread's events.
    public static let eventSummary = "thread-return-watermark"

    public struct Payload: Codable, Sendable, Hashable {
        /// The stable timeline id of the last message the user saw, or nil if never viewed.
        public var lastSeenItemID: String?

        public init(lastSeenItemID: String?) {
            self.lastSeenItemID = lastSeenItemID
        }
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        event.kind == .notice && event.summary == eventSummary
    }

    /// The stable timeline id for a chat message — identical to the app's transcript timeline item id
    /// for message turns, so the seam count matches what the transcript pill would show.
    public static func timelineID(for message: ChatMessage) -> String {
        "message-\(message.id.uuidString)"
    }

    /// The ordered list of message-turn timeline ids for a thread (user + assistant turns; tool rows are
    /// excluded, matching how message turns are counted).
    public static func messageTimelineIDs(for thread: ChatThread) -> [String] {
        thread.messages.filter { $0.role != .tool }.map(timelineID(for:))
    }

    /// The last-seen watermark id recorded on the thread, or nil if never recorded.
    public static func lastSeenItemID(in thread: ChatThread) -> String? {
        for event in thread.events.reversed() where isRecord(event) {
            if let payloadJSON = event.payloadJSON,
               let payload = try? JSONHelpers.decode(Payload.self, from: payloadJSON) {
                return payload.lastSeenItemID
            }
        }
        return nil
    }

    /// The number of unseen message turns for a thread given its persisted watermark. Mirrors
    /// `TranscriptNewTurnsResolver`: 0 when never viewed, when caught up, or when the watermark item was
    /// compacted away; otherwise the suffix length after the watermarked item. Never negative.
    public static func unseenCount(in thread: ChatThread) -> Int {
        guard let lastSeen = lastSeenItemID(in: thread) else { return 0 }
        let ids = messageTimelineIDs(for: thread)
        guard let seenIndex = ids.firstIndex(of: lastSeen) else { return 0 }
        let firstUnseen = ids.index(after: seenIndex)
        guard firstUnseen < ids.endIndex else { return 0 }
        return ids.distance(from: firstUnseen, to: ids.endIndex)
    }

    /// Mark the thread seen up to its current last message — advancing the watermark to the tail. A no-op
    /// (returns false, leaves the thread untouched) when the timeline is empty or already at the tail.
    ///
    /// This deliberately does NOT bump `thread.updatedAt`: the watermark is invisible bookkeeping (the
    /// user leaving a thread must not reorder the recency-sorted sidebar). Callers that persist the
    /// thread should preserve its `updatedAt`.
    @discardableResult
    public static func markSeen(_ thread: inout ChatThread) -> Bool {
        guard let tail = messageTimelineIDs(for: thread).last else { return false }
        guard lastSeenItemID(in: thread) != tail else { return false }
        thread.events.removeAll(where: isRecord)
        guard let payloadJSON = try? JSONHelpers.encodePretty(Payload(lastSeenItemID: tail)) else {
            return false
        }
        thread.events.append(ThreadEvent(kind: .notice, summary: eventSummary, payloadJSON: payloadJSON))
        return true
    }
}

// MARK: - Attention item

/// One row in the Attention section: a thread that needs the morning triage. Built from a thread's
/// persisted verdict stamp (must be `red`/`unverified`), its title, and its unseen-turn count. Threads
/// whose stamp is `verified`, whose triage state is not `pending`, or which have no stamp at all are
/// NOT attention items.
public struct AttentionItem: Sendable, Hashable, Identifiable {
    public var threadID: UUID
    public var title: String
    public var verdict: TriageVerdict
    public var summary: String
    /// How many transcript turns arrived since the user last viewed this thread. Always ≥ 0.
    public var unseenCount: Int
    /// The thread's last-updated time, the tie-breaker for equal-severity rows (newer first).
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

    /// A short "N new" label for the unseen-turn count, or `nil` when nothing is new.
    public var unseenLabel: String? {
        unseenCount == 0 ? nil : "\(unseenCount) new"
    }
}

// MARK: - Attention model (ranking + selection)

/// The ranked Attention list plus a selection cursor. Pure and deterministic: given the same items and
/// the same selected id, it always ranks and clamps identically. The native sidebar and the harness JS
/// both build their list with this exact ordering.
public struct AttentionModel: Sendable, Hashable {
    /// The attention rows, already ranked (RED first, then UNVERIFIED; ties broken by `updatedAt`, newer
    /// first; final tie-break by threadID for total determinism).
    public private(set) var items: [AttentionItem]
    /// The thread id the triage cursor is on, or `nil` when the section is empty.
    public private(set) var selectedThreadID: UUID?

    /// Build a ranked model from unranked attention items, keeping the given selection if it still
    /// exists (else selecting the first row). Ranking is total and stable.
    public init(items: [AttentionItem], selectedThreadID: UUID? = nil) {
        let ranked = Self.rank(items)
        self.items = ranked
        if let selectedThreadID, ranked.contains(where: { $0.threadID == selectedThreadID }) {
            self.selectedThreadID = selectedThreadID
        } else {
            self.selectedThreadID = ranked.first?.threadID
        }
    }

    /// The total, deterministic ranking: severity desc, then recency desc, then threadID asc.
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

    /// The index of the current selection in the ranked list, or `nil` when empty.
    public var selectedIndex: Int? {
        guard let selectedThreadID else { return nil }
        return items.firstIndex { $0.threadID == selectedThreadID }
    }

    /// The currently selected item, or `nil` when the section is empty.
    public var selectedItem: AttentionItem? {
        guard let index = selectedIndex else { return nil }
        return items[index]
    }

    /// Move the cursor down one row (the `j` key). **Clamps** at the last row — never wraps, never goes
    /// out of range. A no-op on an empty section.
    public mutating func moveDown() {
        guard let index = selectedIndex else { return }
        let next = min(index + 1, items.count - 1)
        selectedThreadID = items[next].threadID
    }

    /// Move the cursor up one row (the `k` key). **Clamps** at the first row. A no-op on an empty
    /// section.
    public mutating func moveUp() {
        guard let index = selectedIndex else { return }
        let prev = max(index - 1, 0)
        selectedThreadID = items[prev].threadID
    }

    /// Explicitly select a row by id (e.g. the user clicked it). Ignored if the id is not in the list.
    public mutating func select(_ threadID: UUID) {
        guard items.contains(where: { $0.threadID == threadID }) else { return }
        selectedThreadID = threadID
    }

    /// Build the Attention model from a set of threads. A thread contributes a row iff it has a
    /// persisted RunIntegrity stamp that needs attention (RED / UNVERIFIED) AND it still needs the user's
    /// attention — either never triaged, or triaged against an OLDER run than its current verdict (so a
    /// thread that goes RED again after being acked re-surfaces). Everything derives from the ACTUAL
    /// persisted records on each thread — never self-report and never a stale copy.
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
