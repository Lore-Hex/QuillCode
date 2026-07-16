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
}
