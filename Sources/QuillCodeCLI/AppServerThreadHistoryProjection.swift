import Foundation
import QuillCodeCore

enum AppServerThreadHistoryProjection {
    static func turns(_ record: AppServerThreadRecord) -> [CLIJSONValue] {
        let userShellTurns = record.settings.userShellTurns ?? []
        let standaloneShellTurnIDs = Set(userShellTurns.map(\.id))
        let slices = turnSlices(
            in: record.thread,
            excludingTurnIDs: standaloneShellTurnIDs
        )
        let eventSlices = turnEventSlices(thread: record.thread, turns: slices)
        let conversationTurns = zip(slices, eventSlices).map { slice, events in
            OrderedTurn(
                id: slice.id,
                value: projectedTurn(slice, events: events, record: record)
            )
        }
        let shellTurns = userShellTurns.map { turn in
            OrderedTurn(
                id: turn.id,
                value: AppServerThreadProjection.turn(
                    id: turn.id,
                    items: [],
                    status: "completed",
                    startedAt: turn.startedAt,
                    completedAt: turn.completedAt,
                    itemsView: "full"
                )
            )
        }
        return orderedTurns(
            conversation: conversationTurns,
            userShell: shellTurns,
            messages: record.thread.messages
        )
    }

    private static func orderedTurns(
        conversation: [OrderedTurn],
        userShell: [OrderedTurn],
        messages: [ChatMessage]
    ) -> [CLIJSONValue] {
        let conversationByID = Dictionary(uniqueKeysWithValues: conversation.map { ($0.id, $0) })
        let shellByID = Dictionary(uniqueKeysWithValues: userShell.map { ($0.id, $0) })
        var emitted: Set<String> = []
        var result: [CLIJSONValue] = []

        for message in messages {
            let turnID = message.turnID ?? AppServerThreadProjection.turnIdentifier(message.id)
            guard emitted.insert(turnID).inserted else { continue }
            if let shell = shellByID[turnID] {
                result.append(shell.value)
            } else if message.role == .user, let turn = conversationByID[turnID] {
                result.append(turn.value)
            }
        }

        // Legacy or partially recovered records may have metadata without a transcript marker.
        // Keep their original collection order rather than silently dropping visible history.
        result.append(contentsOf: conversation.lazy.filter { emitted.insert($0.id).inserted }.map(\.value))
        result.append(contentsOf: userShell.lazy.filter { emitted.insert($0.id).inserted }.map(\.value))
        return result
    }

    private static func turnSlices(
        in thread: ChatThread,
        excludingTurnIDs: Set<String>
    ) -> [TurnSlice] {
        var starts: [(index: Int, id: String)] = []
        for (index, message) in thread.messages.enumerated() where message.role == .user {
            let id = message.turnID ?? AppServerThreadProjection.turnIdentifier(message.id)
            if starts.last?.id != id {
                starts.append((index, id))
            }
        }

        return starts.enumerated().compactMap { offset, start in
            let end = starts.indices.contains(offset + 1)
                ? starts[offset + 1].index
                : thread.messages.endIndex
            let messages = thread.messages[start.index..<end].filter { message in
                guard let turnID = message.turnID else { return true }
                return !excludingTurnIDs.contains(turnID)
            }
            guard let firstUser = messages.first(where: { $0.role == .user }) else { return nil }
            return TurnSlice(
                id: start.id,
                messages: messages,
                startedAt: firstUser.createdAt
            )
        }
    }

    private static func turnEventSlices(
        thread: ChatThread,
        turns: [TurnSlice]
    ) -> [[ThreadEvent]] {
        let events = thread.events
        guard !events.isEmpty else { return Array(repeating: [], count: turns.count) }

        let messageEventIndices = events.indices.filter { events[$0].kind == .message }
        var eventCursor = messageEventIndices.startIndex
        var boundaryByTurnID: [String: Int] = [:]
        var previousUserTurnID: String?

        for message in thread.messages where message.role == .user || message.role == .assistant {
            guard eventCursor < messageEventIndices.endIndex else { break }
            let expectedSummary = eventSummary(for: message)
            let remaining = messageEventIndices[eventCursor...]
            guard let matchedCursor = remaining.firstIndex(where: {
                events[$0].summary == expectedSummary
            }) else {
                return Array(repeating: [], count: turns.count)
            }
            let eventIndex = messageEventIndices[matchedCursor]
            eventCursor = messageEventIndices.index(after: matchedCursor)

            guard message.role == .user else { continue }
            let turnID = message.turnID ?? AppServerThreadProjection.turnIdentifier(message.id)
            guard turnID != previousUserTurnID else { continue }
            boundaryByTurnID[turnID] = eventIndex
            previousUserTurnID = turnID
        }

        guard turns.allSatisfy({ boundaryByTurnID[$0.id] != nil }) else {
            return Array(repeating: [], count: turns.count)
        }

        return turns.indices.map { index in
            guard let start = boundaryByTurnID[turns[index].id] else { return [] }
            let end = turns.indices.contains(index + 1)
                ? boundaryByTurnID[turns[index + 1].id] ?? events.endIndex
                : events.endIndex
            guard start <= end else { return [] }
            return Array(events[start..<end])
        }
    }

    private static func eventSummary(for message: ChatMessage) -> String {
        guard message.role == .user, message.content.isEmpty else { return message.content }
        return "Attached \(message.attachments.count) image\(message.attachments.count == 1 ? "" : "s")"
    }

    private static func projectedTurn(
        _ slice: TurnSlice,
        events: [ThreadEvent],
        record: AppServerThreadRecord
    ) -> CLIJSONValue {
        let userMessages = slice.messages.filter { $0.role == .user }
        guard let firstUser = userMessages.first else {
            return AppServerThreadProjection.turn(
                id: slice.id,
                items: [],
                status: "completed",
                startedAt: slice.startedAt,
                completedAt: slice.startedAt,
                itemsView: "full"
            )
        }

        var emptyBaseline = record.thread
        emptyBaseline.messages = []
        emptyBaseline.events = []
        var snapshot = emptyBaseline
        snapshot.messages = slice.messages
        snapshot.events = events

        var projector = AppServerProgressProjector(
            threadID: record.thread.id,
            turnID: slice.id,
            cwd: record.settings.cwd,
            baseline: emptyBaseline,
            userItem: AppServerThreadProjection.userMessageItem(firstUser)
        )
        for message in userMessages.dropFirst() {
            projector.addUserMessage(message, clientID: message.clientMessageID)
        }

        let completedAt = latestDate(messages: slice.messages, events: events) ?? slice.startedAt
        _ = projector.finish(snapshot, completedAt: completedAt)
        return AppServerThreadProjection.turn(
            id: slice.id,
            items: projector.items,
            status: "completed",
            startedAt: slice.startedAt,
            completedAt: completedAt,
            itemsView: "full"
        )
    }

    private static func latestDate(
        messages: [ChatMessage],
        events: [ThreadEvent]
    ) -> Date? {
        let latestMessage = messages.lazy.map(\.createdAt).max()
        let latestEvent = events.lazy.map(\.createdAt).max()
        switch (latestMessage, latestEvent) {
        case (.some(let message), .some(let event)): return max(message, event)
        case (.some(let message), .none): return message
        case (.none, .some(let event)): return event
        case (.none, .none): return nil
        }
    }
}

private struct TurnSlice {
    let id: String
    let messages: [ChatMessage]
    let startedAt: Date
}

private struct OrderedTurn {
    let id: String
    let value: CLIJSONValue
}
