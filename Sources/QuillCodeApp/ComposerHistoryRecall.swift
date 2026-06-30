import Foundation
import QuillCodeCore

/// Pure logic for recalling previously sent composer messages with the Up/Down keys,
/// mirroring a shell or Codex prompt history. The composer view owns the transient
/// recall cursor; this type computes the next draft and cursor for each step and
/// builds the bounded history list from a thread's sent user messages.
public enum ComposerHistoryRecall {
    /// Maximum number of recent sent messages kept for recall.
    public static let maxEntries = 50

    /// The result of a recall step: the index now being shown and the draft to apply.
    public struct Step: Equatable {
        public var index: Int
        public var draft: String

        public init(index: Int, draft: String) {
            self.index = index
            self.draft = draft
        }
    }

    /// Builds the recall history (oldest first) from a thread's messages: non-empty
    /// user messages, with adjacent duplicates collapsed and bounded to ``maxEntries``.
    public static func history(from messages: [ChatMessage]) -> [String] {
        var entries: [String] = []
        for message in messages where message.role == .user {
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if entries.last == trimmed { continue }
            entries.append(trimmed)
        }
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        return entries
    }

    /// Recalls an older message. With no active recall it starts at the newest entry;
    /// otherwise it moves one entry older, clamping at the oldest.
    public static func older(history: [String], currentIndex: Int?) -> Step? {
        guard !history.isEmpty else { return nil }
        let index: Int
        if let currentIndex {
            index = max(0, currentIndex - 1)
        } else {
            index = history.count - 1
        }
        return Step(index: index, draft: history[index])
    }

    /// Recalls a newer message. Returns the next entry, or `nil` when stepping past the
    /// newest entry, signalling the caller to restore the in-progress draft and exit.
    public static func newer(history: [String], currentIndex: Int) -> Step? {
        guard currentIndex >= 0, currentIndex + 1 < history.count else { return nil }
        let index = currentIndex + 1
        return Step(index: index, draft: history[index])
    }
}
