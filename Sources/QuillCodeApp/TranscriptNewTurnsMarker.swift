import Foundation

/// Tracks, per thread, the last transcript item the user has seen, so that on returning to a
/// thread that has grown we can show an "N new turns" pill that jumps to the first unseen item.
///
/// Design:
/// - The marker is the **timeline-item id** of the last item the user had seen (stable across
///   reload because ids are derived from message/tool ids, not array positions).
/// - "New" items are those that appear *after* the marked id in timeline order. If the marked id
///   is no longer present (e.g. the tail was compacted/forked away) we treat everything as seen
///   rather than flashing a bogus count — a stale marker must never produce a negative or
///   nonsensical number.
/// - A `nil` marker (a thread never opened before, or freshly created) means "nothing to
///   announce": we do not badge a thread the user is looking at for the first time.
///
/// Nothing here is UI: the count and the jump target are pure functions of (timeline, marker),
/// and the marker itself round-trips through `Codable` for persistence.
public struct TranscriptNewTurnsMarker: Codable, Sendable, Equatable {
    /// The timeline-item id of the last item the user saw, or `nil` if the thread was never
    /// viewed (so there is nothing "new" to announce).
    public var lastSeenItemID: String?

    public init(lastSeenItemID: String? = nil) {
        self.lastSeenItemID = lastSeenItemID
    }

    /// Mark the whole current timeline as seen — its last item becomes the new watermark. Calling
    /// this on an empty timeline leaves the marker unchanged (there is nothing to have seen).
    public mutating func markSeen(timeline: [TranscriptTimelineItemSurface]) {
        guard let last = timeline.last else { return }
        lastSeenItemID = last.id
    }

    /// Convenience for `TranscriptSurface` callers.
    public mutating func markSeen(transcript: TranscriptSurface) {
        markSeen(timeline: transcript.timelineItems)
    }
}

/// The derived "N new turns" pill state for one thread: how many unseen items there are and which
/// item the pill should scroll to. Absent (`nil`) when there is nothing to show.
public struct TranscriptNewTurnsPill: Sendable, Equatable {
    /// How many unseen items there are (always ≥ 1 when a pill exists).
    public var count: Int
    /// The id of the first unseen item — where the pill scrolls the user on tap.
    public var firstUnseenItemID: String

    public init(count: Int, firstUnseenItemID: String) {
        self.count = count
        self.firstUnseenItemID = firstUnseenItemID
    }

    /// User-facing label, correctly singular/plural.
    public var label: String {
        count == 1 ? "1 new turn" : "\(count) new turns"
    }
}

public enum TranscriptNewTurnsResolver {
    /// Resolve the pill for a thread given its current timeline and the persisted marker.
    ///
    /// Returns `nil` (no pill) when:
    /// - the thread was never viewed (`marker.lastSeenItemID == nil`),
    /// - the marked item is the last item (nothing new), or
    /// - the marked id is no longer in the timeline (stale marker — treat as all seen).
    ///
    /// Otherwise returns a pill whose `count` is the number of items after the marked one and
    /// whose `firstUnseenItemID` is the first of those. The count can never be negative: it is a
    /// suffix length of the array.
    public static func resolve(
        timeline: [TranscriptTimelineItemSurface],
        marker: TranscriptNewTurnsMarker
    ) -> TranscriptNewTurnsPill? {
        guard let lastSeenID = marker.lastSeenItemID else { return nil }
        guard let seenIndex = timeline.firstIndex(where: { $0.id == lastSeenID }) else {
            // Marked item was compacted/forked away. Do not invent a count.
            return nil
        }
        let firstUnseenIndex = timeline.index(after: seenIndex)
        guard firstUnseenIndex < timeline.endIndex else { return nil }
        let unseen = timeline[firstUnseenIndex...]
        guard let first = unseen.first else { return nil }
        return TranscriptNewTurnsPill(
            count: unseen.count,
            firstUnseenItemID: first.id
        )
    }

    public static func resolve(
        transcript: TranscriptSurface,
        marker: TranscriptNewTurnsMarker
    ) -> TranscriptNewTurnsPill? {
        resolve(timeline: transcript.timelineItems, marker: marker)
    }
}

/// Per-thread "N new turns" bookkeeping with the watermark semantics the pill needs to actually
/// work within a session: the *foreground* thread's watermark stays pinned to whatever the user
/// last acknowledged (it is NOT auto-advanced just because the thread re-appeared), and it is
/// advanced to the thread's current end only when the user **leaves** the thread or **taps the
/// pill**. A thread that grows in the background while unselected therefore accumulates unseen
/// turns, and on return the pill surfaces them.
///
/// This is deliberately separate from SwiftUI: `observe`, `leave`, and `markSeen` are the three
/// state transitions, `pill(for:)` is a pure read, and it is all directly unit-testable. The
/// native view drives these from `.onAppear` / `.onChange(of: threadID)` / the pill tap.
public struct TranscriptNewTurnsTracker: Equatable {
    /// The acknowledged watermark per thread — the last item the user has seen.
    private var markers: [UUID: TranscriptNewTurnsMarker] = [:]
    /// The most recently observed tail (last timeline-item id) per thread, updated on every
    /// `observe`. Used to advance the watermark when the user *leaves* a thread, capturing what
    /// they had on screen at that moment (not what the thread later grows to in the background).
    private var observedTails: [UUID: String] = [:]

    public init() {}

    /// Record the current transcript for `threadID` (the foreground thread on this render). This
    /// updates the observed tail but does NOT move the acknowledged watermark, so a thread that
    /// grew in the background still resolves to a pill when the user returns to it.
    public mutating func observe(threadID: UUID?, timeline: [TranscriptTimelineItemSurface]) {
        guard let threadID, let tail = timeline.last?.id else { return }
        observedTails[threadID] = tail
    }

    public mutating func observe(threadID: UUID?, transcript: TranscriptSurface) {
        observe(threadID: threadID, timeline: transcript.timelineItems)
    }

    /// The user is leaving `threadID`: advance its acknowledged watermark to the last tail we
    /// observed while it was foreground. On return, only turns added *after* this point are "new".
    public mutating func leave(threadID: UUID?) {
        guard let threadID, let tail = observedTails[threadID] else { return }
        markers[threadID, default: TranscriptNewTurnsMarker()].lastSeenItemID = tail
    }

    /// Explicitly mark `threadID` seen up to the given timeline's end — used on pill tap, when the
    /// user has acknowledged the new turns.
    public mutating func markSeen(threadID: UUID?, timeline: [TranscriptTimelineItemSurface]) {
        guard let threadID else { return }
        markers[threadID, default: TranscriptNewTurnsMarker()].markSeen(timeline: timeline)
        if let tail = timeline.last?.id {
            observedTails[threadID] = tail
        }
    }

    public mutating func markSeen(threadID: UUID?, transcript: TranscriptSurface) {
        markSeen(threadID: threadID, timeline: transcript.timelineItems)
    }

    /// The pill for `threadID` given its current timeline, using that thread's acknowledged
    /// watermark. `nil` (no pill) for a never-left thread or one with nothing new.
    public func pill(
        for threadID: UUID?,
        timeline: [TranscriptTimelineItemSurface]
    ) -> TranscriptNewTurnsPill? {
        guard let threadID, let marker = markers[threadID] else { return nil }
        return TranscriptNewTurnsResolver.resolve(timeline: timeline, marker: marker)
    }

    public func pill(for threadID: UUID?, transcript: TranscriptSurface) -> TranscriptNewTurnsPill? {
        pill(for: threadID, timeline: transcript.timelineItems)
    }
}
