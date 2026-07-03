import Foundation

/// Pure, deterministic incremental-search logic for the transcript timeline.
///
/// The UI (SwiftUI find bar + HTML harness) is a thin consumer of this type: given a
/// transcript and a raw query string it produces the ordered list of matching timeline
/// items, and — for highlighting — the character ranges within each item's searchable text
/// that matched. All matching is **literal** (query characters are compared as-is, never as a
/// regex), case-insensitive, and unicode-safe (compared over `Character`s, so multi-scalar
/// graphemes are not split). Nothing here touches SwiftUI, so it is trivially testable and can
/// be mirrored byte-for-byte by the JavaScript harness.
///
/// Efficiency: matching is a single linear pass over the timeline, and within each item a
/// single left-to-right scan of the searchable text — O(text length) per item, O(total
/// transcript length) per keystroke. There is no quadratic backtracking and no per-keystroke
/// re-derivation of the timeline itself (the caller passes the already-built timeline).
struct TranscriptSearchIndex: Sendable, Equatable {
    /// A contiguous run of matched characters inside one timeline item's searchable text,
    /// expressed as a character offset + length (not `String.Index`, so it survives being
    /// carried across the Swift/JS boundary and is easy to assert on).
    struct MatchRange: Sendable, Equatable, Hashable {
        var start: Int
        var length: Int

        init(start: Int, length: Int) {
            self.start = start
            self.length = length
        }
    }

    /// One matching timeline item, in timeline order.
    struct Match: Sendable, Equatable, Identifiable {
        var id: String { timelineItemID }
        var timelineItemID: String
        var label: String
        /// Every occurrence of the query inside this item's searchable text, left to right.
        /// Always non-empty for a `Match` (an item with zero occurrences is not a match).
        var ranges: [MatchRange]

        init(timelineItemID: String, label: String, ranges: [MatchRange]) {
            self.timelineItemID = timelineItemID
            self.label = label
            self.ranges = ranges
        }
    }

    var matches: [Match]

    init(matches: [Match]) {
        self.matches = matches
    }

    /// Whether the query matched nothing (either blank or genuinely absent).
    var isEmpty: Bool { matches.isEmpty }

    var count: Int { matches.count }

    /// The total number of individual highlighted occurrences across all items.
    var totalOccurrences: Int { matches.reduce(0) { $0 + $1.ranges.count } }

    /// Build the index for `query` against `transcript`'s timeline. A blank query (empty or
    /// whitespace-only) yields an empty index — searching for nothing matches nothing, which
    /// is the expected "no highlight, no status" state.
    static func build(transcript: TranscriptSurface, query: String) -> TranscriptSearchIndex {
        build(timeline: transcript.timelineItems, query: query)
    }

    /// Timeline-based overload so callers that already have the ordered items (or want to test
    /// the pure logic) do not have to construct a whole `TranscriptSurface`.
    static func build(
        timeline: [TranscriptTimelineItemSurface],
        query: String
    ) -> TranscriptSearchIndex {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return TranscriptSearchIndex(matches: []) }

        let needle = Array(normalizedQuery.lowercased())
        let matches: [Match] = timeline.compactMap { item in
            let haystack = searchableText(for: item)
            let ranges = literalRanges(of: needle, in: haystack)
            guard !ranges.isEmpty else { return nil }
            return Match(
                timelineItemID: item.id,
                label: label(for: item),
                ranges: ranges
            )
        }
        return TranscriptSearchIndex(matches: matches)
    }

    /// Find every occurrence of `needle` (already lowercased characters) inside `haystack`,
    /// case-insensitively and literally. Returns character-offset ranges in left-to-right order.
    ///
    /// Implementation notes:
    /// - We compare over `Array<Character>` (grapheme clusters), so a query like an emoji or a
    ///   combining sequence is matched as one unit and offsets stay grapheme-aligned.
    /// - Occurrences are non-overlapping: after a hit we advance past its whole length, matching
    ///   the "next match" intuition (e.g. "aa" in "aaaa" is 2 hits, not 3).
    /// - `needle` is treated as plain text; regex metacharacters like `.` `*` `(` are literal.
    static func literalRanges(of needle: [Character], in haystack: String) -> [MatchRange] {
        guard !needle.isEmpty else { return [] }
        let hay = Array(haystack.lowercased())
        guard hay.count >= needle.count else { return [] }

        var ranges: [MatchRange] = []
        var index = 0
        let lastStart = hay.count - needle.count
        while index <= lastStart {
            var offset = 0
            while offset < needle.count && hay[index + offset] == needle[offset] {
                offset += 1
            }
            if offset == needle.count {
                ranges.append(MatchRange(start: index, length: needle.count))
                index += needle.count
            } else {
                index += 1
            }
        }
        return ranges
    }

    /// The text a timeline item is searched against. Mirrors the harness's
    /// `transcriptTimelineSearchText`, and the historical `QuillCodeTranscriptFindMatch`
    /// behavior, so all three surfaces agree on what "matches".
    static func searchableText(for item: TranscriptTimelineItemSurface) -> String {
        switch item.kind {
        case .message:
            return [
                item.message?.role.rawValue,
                item.message?.text
            ].compactMap { $0 }.joined(separator: "\n")
        case .toolCard:
            guard let card = item.toolCard else { return "" }
            return [
                card.title,
                card.subtitle,
                card.inputJSON,
                card.outputJSON,
                card.artifacts.map(\.label).joined(separator: "\n")
            ].compactMap { $0 }.joined(separator: "\n")
        }
    }

    static func label(for item: TranscriptTimelineItemSurface) -> String {
        switch item.kind {
        case .message:
            return item.message?.role.rawValue.capitalized ?? "Message"
        case .toolCard:
            return item.toolCard?.title ?? "Tool"
        }
    }
}

/// A wrap-around cursor over a fixed match count. Keeps "which match is active" and the
/// next/prev/clamp arithmetic in one tested place so the SwiftUI view, the desktop coordinator,
/// and the harness cannot drift on off-by-one or negative-modulo bugs.
struct TranscriptSearchCursor: Sendable, Equatable {
    private(set) var activeIndex: Int
    let count: Int

    init(activeIndex: Int = 0, count: Int) {
        self.count = max(0, count)
        self.activeIndex = Self.clamp(activeIndex, count: self.count)
    }

    /// The 1-based position for status text ("3 of 12"), or 0 when there are no matches.
    var humanPosition: Int { count == 0 ? 0 : activeIndex + 1 }

    mutating func next() {
        guard count > 0 else { return }
        activeIndex = (activeIndex + 1) % count
    }

    mutating func previous() {
        guard count > 0 else { return }
        activeIndex = (activeIndex - 1 + count) % count
    }

    /// Reset to the first match — used when the query changes so the user starts at the top.
    mutating func reset() {
        activeIndex = 0
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
