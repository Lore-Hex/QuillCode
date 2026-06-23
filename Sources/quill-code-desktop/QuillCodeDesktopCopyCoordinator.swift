import AppKit
import Foundation

struct QuillCodeDesktopCopyFeedback: Equatable, Sendable {
    let copiedTranscriptItemID: String
    let clearAfterNanoseconds: UInt64
}

@MainActor
protocol QuillCodePasteboardWriting {
    func writeString(_ text: String)
}

@MainActor
struct MacPasteboardWriter: QuillCodePasteboardWriting {
    func writeString(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

@MainActor
struct QuillCodeDesktopCopyCoordinator {
    static let defaultFeedbackDurationNanoseconds: UInt64 = 1_500_000_000

    private let pasteboard: any QuillCodePasteboardWriting
    private let feedbackDurationNanoseconds: UInt64

    init(
        pasteboard: any QuillCodePasteboardWriting = MacPasteboardWriter(),
        feedbackDurationNanoseconds: UInt64 = Self.defaultFeedbackDurationNanoseconds
    ) {
        self.pasteboard = pasteboard
        self.feedbackDurationNanoseconds = feedbackDurationNanoseconds
    }

    func copyTranscriptItem(id: String, text: String) -> QuillCodeDesktopCopyFeedback? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        pasteboard.writeString(text)
        return QuillCodeDesktopCopyFeedback(
            copiedTranscriptItemID: id,
            clearAfterNanoseconds: feedbackDurationNanoseconds
        )
    }
}
