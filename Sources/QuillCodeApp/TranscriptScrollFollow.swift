import CoreGraphics

/// Pure helpers for the transcript's conditional bottom-pinning (used by ``QuillCodeTranscriptView``).
/// Kept out of the view so the follow logic is unit-testable without a running SwiftUI hierarchy.
enum TranscriptScrollFollow {
    /// A signature that changes on every streamed chunk even though the tail item's id is stable —
    /// composed from the tail id, the item count, and the streamed length of the tail (thinking
    /// trace, tool output, or message text). `.onChange(of:)` on this fires per chunk, which the tail
    /// id alone cannot do (it only changes when a NEW timeline item is appended).
    static func contentSignature(for transcript: TranscriptSurface) -> String {
        let tailID = transcript.thinking?.id ?? transcript.timelineItems.last?.id ?? ""
        let tailLength: Int
        if let thinking = transcript.thinking {
            tailLength = thinking.traceLines.reduce(0) { $0 + $1.count } + thinking.subtitle.count
        } else if let card = transcript.timelineItems.last?.toolCard {
            tailLength = TranscriptItemTextFormatter.text(for: card).count
        } else if let message = transcript.timelineItems.last?.message {
            tailLength = message.text.count
        } else {
            tailLength = 0
        }
        return "\(tailID)#\(transcript.timelineItems.count)#\(tailLength)"
    }

    /// The reader is "pinned to bottom" when the end-of-content sentinel sits within `threshold` of the
    /// viewport bottom. A larger gap means they have scrolled up, so streaming must not follow them.
    static func isPinnedToBottom(
        bottomSentinelMaxY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat
    ) -> Bool {
        (bottomSentinelMaxY - viewportHeight) <= threshold
    }

    /// The pin transition for one geometry sample. Within `threshold` of the bottom ⇒ (re)pin,
    /// whatever moved the sentinel there. Beyond it, the prior state is PRESERVED unless
    /// `unpinBeyondThreshold` — so streaming keeps following an at-bottom reader through a large chunk
    /// (content growth and our own animated follow-scroll both widen the sentinel gap exactly like a
    /// scroll would, so the gap alone can't be trusted to un-pin). Callers set `unpinBeyondThreshold`
    /// when the reader genuinely falls behind: a real scroll UP (from the orthogonal content-offset
    /// signal, see ``pinnedAfterScrollSample``), or a growth that arrives while follow-scroll is
    /// suppressed (Find / review open) so the viewport will NOT auto-catch-up.
    static func resolvePinned(
        current: Bool,
        bottomSentinelMaxY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat,
        unpinBeyondThreshold: Bool
    ) -> Bool {
        if isPinnedToBottom(
            bottomSentinelMaxY: bottomSentinelMaxY,
            viewportHeight: viewportHeight,
            threshold: threshold
        ) {
            return true
        }
        return unpinBeyondThreshold ? false : current
    }

    /// Classify a content-offset sample, then resolve the pin. `contentTopMinY` is the transcript
    /// content's top edge in the scroll viewport's coordinate space — i.e. the (negated) scroll
    /// offset. It INCREASES only when the reader drags the content DOWN (scrolls up); appending a
    /// chunk at the bottom leaves the top put, and the follow-scroll animation drives it further
    /// negative. So "the top moved down past `scrollEpsilon` since the last sample" is an orthogonal,
    /// timing-free proxy for a deliberate scroll-up — unlike the sentinel gap, which a large chunk and
    /// a scroll widen identically. This is what stops a big streamed chunk (or the follow animation's
    /// own intermediate frames) from being misread as a scroll and dropping the follow.
    static func pinnedAfterScrollSample(
        current: Bool,
        bottomSentinelMaxY: CGFloat,
        viewportHeight: CGFloat,
        threshold: CGFloat,
        contentTopMinY: CGFloat,
        previousContentTopMinY: CGFloat,
        scrollEpsilon: CGFloat = 0.5
    ) -> Bool {
        let isUserScrollUp = (contentTopMinY - previousContentTopMinY) > scrollEpsilon
        return resolvePinned(
            current: current,
            bottomSentinelMaxY: bottomSentinelMaxY,
            viewportHeight: viewportHeight,
            threshold: threshold,
            unpinBeyondThreshold: isUserScrollUp
        )
    }
}
