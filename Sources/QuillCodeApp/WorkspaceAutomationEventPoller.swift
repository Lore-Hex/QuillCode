import Foundation
import QuillCodeCore

enum WorkspaceAutomationEventPoller {
    static let maximumConcurrentPolls = 4

    static func pendingEvents(
        in automations: [QuillAutomation],
        now: Date,
        eventSources: [UUID: any AutomationEventSource],
        maximumConcurrentPolls: Int = maximumConcurrentPolls
    ) async -> [UUID: String] {
        let candidates = automations.compactMap { automation -> Candidate? in
            guard automation.status == .active,
                  automation.nextRunAt.map({ $0 > now }) ?? true,
                  automation.kind == .monitor,
                  automation.scheduleKind == .event,
                  let source = eventSources[automation.id]
            else {
                return nil
            }
            return Candidate(
                automationID: automation.id,
                lastRunAt: automation.lastRunAt,
                source: source
            )
        }
        guard !candidates.isEmpty, maximumConcurrentPolls > 0 else { return [:] }

        var events: [UUID: String] = [:]
        for batchStart in stride(from: 0, to: candidates.count, by: maximumConcurrentPolls) {
            guard !Task.isCancelled else { return [:] }
            let batchEnd = min(batchStart + maximumConcurrentPolls, candidates.count)
            let batchEvents = await poll(candidates[batchStart..<batchEnd])
            guard !Task.isCancelled else {
                return [:]
            }
            for event in batchEvents {
                events[event.automationID] = event.description
            }
        }
        return events
    }

    private static func poll(
        _ candidates: ArraySlice<Candidate>
    ) async -> [PendingEvent] {
        let (stream, continuation) = AsyncStream<PendingEvent?>.makeStream(
            bufferingPolicy: .bufferingNewest(candidates.count)
        )
        let completion = BatchCompletion(
            remaining: candidates.count,
            continuation: continuation
        )
        let tasks = candidates.map { candidate in
            Task.detached(priority: .utility) {
                completion.submit(candidate.poll())
            }
        }

        var events: [PendingEvent] = []
        for await event in stream {
            if let event {
                events.append(event)
            }
        }
        tasks.forEach { $0.cancel() }
        return Task.isCancelled ? [] : events
    }

    private struct Candidate: Sendable {
        let automationID: UUID
        let lastRunAt: Date?
        let source: any AutomationEventSource

        func poll() -> PendingEvent? {
            guard !Task.isCancelled,
                  let description = source.pendingEvent(since: lastRunAt),
                  !Task.isCancelled
            else {
                return nil
            }
            return PendingEvent(automationID: automationID, description: description)
        }
    }

    private struct PendingEvent: Sendable {
        let automationID: UUID
        let description: String
    }

    private final class BatchCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        private let continuation: AsyncStream<PendingEvent?>.Continuation

        init(
            remaining: Int,
            continuation: AsyncStream<PendingEvent?>.Continuation
        ) {
            self.remaining = remaining
            self.continuation = continuation
        }

        func submit(_ event: PendingEvent?) {
            lock.lock()
            guard remaining > 0 else {
                lock.unlock()
                return
            }
            remaining -= 1
            let isComplete = remaining == 0
            continuation.yield(event)
            if isComplete {
                continuation.finish()
            }
            lock.unlock()
        }
    }
}
