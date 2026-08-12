import Foundation

/// Content-free model-usage receipts retained while a transcript payload is offloaded.
/// Bucketing by local day and canonical model preserves the app's day/week/month spend periods
/// without retaining one event per provider call.
public struct ThreadPeriodUsageSnapshot: Codable, Sendable, Hashable {
    public static let maximumBucketCount = 128

    public var calendarIdentifier: String
    public var timeZoneIdentifier: String
    public var events: [ThreadEvent]

    public static func currentPeriodRetentionStart(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? today
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        return min(monthStart, weekStart)
    }

    public init?(
        thread: ChatThread,
        retainingSince retentionStart: Date,
        calendar: Calendar = .current,
        now: Date = Date(),
        maximumBucketCount: Int = maximumBucketCount
    ) {
        guard maximumBucketCount >= 0 else { return nil }
        var buckets: [Bucket: Aggregate] = [:]

        for event in thread.events {
            guard event.createdAt >= retentionStart,
                  event.createdAt <= now,
                  let record = ModelTokenUsageEvent.record(from: event)
            else {
                continue
            }
            let modelID = TrustedRouterDefaults.canonicalModelID(record.modelID ?? thread.model)
            let bucket = Bucket(
                dayStart: calendar.startOfDay(for: event.createdAt),
                modelID: modelID
            )
            if var aggregate = buckets[bucket] {
                aggregate.usage = Self.adding(aggregate.usage, record.usage)
                aggregate.callCount = Self.saturatingAdd(aggregate.callCount, record.callCount)
                buckets[bucket] = aggregate
            } else {
                guard buckets.count < maximumBucketCount else { return nil }
                buckets[bucket] = Aggregate(
                    eventID: event.id,
                    usage: record.usage,
                    callCount: record.callCount
                )
            }
        }

        self.calendarIdentifier = String(describing: calendar.identifier)
        self.timeZoneIdentifier = calendar.timeZone.identifier
        self.events = buckets
            .sorted { lhs, rhs in
                if lhs.key.dayStart != rhs.key.dayStart {
                    return lhs.key.dayStart < rhs.key.dayStart
                }
                return lhs.key.modelID < rhs.key.modelID
            }
            .map { bucket, aggregate in
                var event = ModelTokenUsageEvent.event(
                    usage: aggregate.usage,
                    modelID: bucket.modelID,
                    callCount: aggregate.callCount
                )
                event.id = aggregate.eventID
                event.createdAt = bucket.dayStart
                return event
            }
    }

    public func isCompatible(with calendar: Calendar) -> Bool {
        calendarIdentifier == String(describing: calendar.identifier)
            && timeZoneIdentifier == calendar.timeZone.identifier
            && events.count <= Self.maximumBucketCount
    }

    public func events(since start: Date, through end: Date) -> [ThreadEvent] {
        events.filter { $0.createdAt >= start && $0.createdAt <= end }
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

    private struct Bucket: Hashable {
        var dayStart: Date
        var modelID: String
    }

    private struct Aggregate {
        var eventID: UUID
        var usage: ModelTokenUsage
        var callCount: Int
    }
}
