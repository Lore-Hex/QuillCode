import Foundation
import QuillCodeCore

/// Session-only, content-free accounting for destroyed confidential and side conversations.
/// Usage is compacted by local day and model, bounding retained events to the active month plus
/// any prior-month days in the active week while preserving exact spend and provider-call counts.
struct WorkspaceEphemeralSpendLedger: Sendable, Hashable {
    private var receiptThreadID = UUID()
    private var retainedSince: Date?
    private var buckets: [Bucket: Aggregate] = [:]
    private var cachedReceiptThread: ChatThread?

    var isEmpty: Bool { buckets.isEmpty }
    var bucketCount: Int { buckets.count }

    mutating func retain(
        _ thread: ChatThread,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        guard thread.runtimeContext.isEphemeral else { return }
        let retentionStart = prepareRetentionWindow(calendar: calendar, now: now)
        var didChange = false

        for event in thread.events {
            guard event.createdAt >= retentionStart,
                  event.createdAt <= now,
                  let record = ModelTokenUsageEvent.record(from: event)
            else {
                continue
            }
            let modelID = record.modelID ?? thread.model
            let bucket = Bucket(
                dayStart: calendar.startOfDay(for: event.createdAt),
                modelID: TrustedRouterDefaults.canonicalModelID(modelID)
            )
            if var aggregate = buckets[bucket] {
                aggregate.usage = Self.adding(aggregate.usage, record.usage)
                aggregate.callCount = Self.saturatingAdd(aggregate.callCount, record.callCount)
                aggregate.latestCreatedAt = max(aggregate.latestCreatedAt, event.createdAt)
                buckets[bucket] = aggregate
            } else {
                buckets[bucket] = Aggregate(
                    eventID: event.id,
                    usage: record.usage,
                    callCount: record.callCount,
                    latestCreatedAt: event.createdAt
                )
            }
            didChange = true
        }
        if didChange {
            cachedReceiptThread = nil
        }
    }

    mutating func periodThreads(
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [ChatThread] {
        _ = prepareRetentionWindow(calendar: calendar, now: now)
        if let cachedReceiptThread {
            return [cachedReceiptThread]
        }
        let events = buckets
            .sorted { lhs, rhs in
                if lhs.key.dayStart != rhs.key.dayStart {
                    return lhs.key.dayStart < rhs.key.dayStart
                }
                return lhs.key.modelID < rhs.key.modelID
            }
            .map { bucket, aggregate -> ThreadEvent in
                var event = ModelTokenUsageEvent.event(
                    usage: aggregate.usage,
                    modelID: bucket.modelID,
                    callCount: aggregate.callCount
                )
                event.id = aggregate.eventID
                event.createdAt = aggregate.latestCreatedAt
                return event
            }
        guard let first = events.first, let last = events.last else { return [] }

        let thread = ChatThread(
            id: receiptThreadID,
            title: "Ephemeral spend receipts",
            events: events,
            createdAt: first.createdAt,
            updatedAt: last.createdAt
        )
        cachedReceiptThread = thread
        return [thread]
    }

    @discardableResult
    private mutating func prepareRetentionWindow(calendar: Calendar, now: Date) -> Date {
        let today = calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? today
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let currentStart = min(monthStart, weekStart)
        if let retainedSince, currentStart > retainedSince {
            let oldCount = buckets.count
            buckets = buckets.filter { $0.value.latestCreatedAt >= currentStart }
            if buckets.count != oldCount {
                cachedReceiptThread = nil
            }
        }
        retainedSince = currentStart
        return currentStart
    }

    private static func adding(_ lhs: ModelTokenUsage, _ rhs: ModelTokenUsage) -> ModelTokenUsage {
        ModelTokenUsage(
            promptTokens: saturatingAdd(lhs.promptTokens, rhs.promptTokens),
            completionTokens: saturatingAdd(lhs.completionTokens, rhs.completionTokens),
            totalTokens: saturatingAdd(lhs.totalTokens, rhs.totalTokens)
        )
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }

    private struct Bucket: Sendable, Hashable {
        var dayStart: Date
        var modelID: String
    }

    private struct Aggregate: Sendable, Hashable {
        var eventID: UUID
        var usage: ModelTokenUsage
        var callCount: Int
        var latestCreatedAt: Date
    }
}
