import Foundation
import QuillCodeCore

/// Matches persisted message events to their source messages without rescanning the transcript.
/// Duplicate message text is consumed in source order, matching the historical first-unconsumed
/// behavior of the transcript builder.
struct WorkspaceTranscriptMessageIndex {
    private struct Cursor {
        let messageIndices: [Int]
        var nextOffset = 0
    }

    private var cursorsByContent: [String: Cursor]
    private let messageIDs: [UUID]
    private var consumedMessageIDs: Set<UUID> = []

    init(messages: [ChatMessage]) {
        var indicesByContent: [String: [Int]] = [:]
        indicesByContent.reserveCapacity(messages.count)
        for index in messages.indices {
            indicesByContent[messages[index].content, default: []].append(index)
        }
        cursorsByContent = indicesByContent.mapValues { Cursor(messageIndices: $0) }
        messageIDs = messages.map(\.id)
    }

    mutating func consumeFirstIndex(matching content: String) -> Int? {
        guard var cursor = cursorsByContent[content] else { return nil }

        while cursor.messageIndices.indices.contains(cursor.nextOffset) {
            let messageIndex = cursor.messageIndices[cursor.nextOffset]
            cursor.nextOffset += 1
            guard messageIDs.indices.contains(messageIndex),
                  consumedMessageIDs.insert(messageIDs[messageIndex]).inserted
            else {
                continue
            }
            store(cursor, for: content)
            return messageIndex
        }

        cursorsByContent.removeValue(forKey: content)
        return nil
    }

    func isConsumed(_ messageID: UUID) -> Bool {
        consumedMessageIDs.contains(messageID)
    }

    private mutating func store(_ cursor: Cursor, for content: String) {
        if cursor.nextOffset == cursor.messageIndices.count {
            cursorsByContent.removeValue(forKey: content)
        } else {
            cursorsByContent[content] = cursor
        }
    }
}
