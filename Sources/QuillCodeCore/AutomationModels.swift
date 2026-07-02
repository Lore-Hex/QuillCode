import Foundation

public enum QuillAutomationKind: String, Codable, Sendable, Hashable, CaseIterable {
    case threadFollowUp = "thread_follow_up"
    case workspaceSchedule = "workspace_schedule"
    case monitor

    public var label: String {
        switch self {
        case .threadFollowUp:
            return "Thread follow-up"
        case .workspaceSchedule:
            return "Workspace schedule"
        case .monitor:
            return "Monitor"
        }
    }
}

public enum QuillAutomationStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case active
    case paused

    public var label: String {
        switch self {
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        }
    }
}

public enum QuillAutomationScheduleKind: String, Codable, Sendable, Hashable, CaseIterable {
    case heartbeat
    case cron
    case event

    public var label: String {
        switch self {
        case .heartbeat:
            return "Heartbeat"
        case .cron:
            return "Cron"
        case .event:
            return "Event"
        }
    }
}

public enum QuillAutomationEventSourceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case fileChange = "file_change"

    public var label: String {
        switch self {
        case .fileChange:
            return "File change"
        }
    }
}

public struct QuillAutomationEventSource: Codable, Sendable, Hashable {
    public var kind: QuillAutomationEventSourceKind
    public var path: String

    public init(
        kind: QuillAutomationEventSourceKind,
        path: String
    ) {
        self.kind = kind
        self.path = path
    }
}

public enum QuillAutomationRecurrenceUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case minutes
    case hours
    case days
    case weeks

    public var seconds: Int {
        switch self {
        case .minutes:
            return 60
        case .hours:
            return 3_600
        case .days:
            return 86_400
        case .weeks:
            return 604_800
        }
    }

    public func label(count: Int) -> String {
        switch self {
        case .minutes:
            return count == 1 ? "minute" : "minutes"
        case .hours:
            return count == 1 ? "hour" : "hours"
        case .days:
            return count == 1 ? "day" : "days"
        case .weeks:
            return count == 1 ? "week" : "weeks"
        }
    }
}

public struct QuillAutomationRecurrence: Codable, Sendable, Hashable {
    public var interval: Int
    public var unit: QuillAutomationRecurrenceUnit
    public var weekdays: [Int]?
    public var hour: Int?
    public var minute: Int?

    public init(
        interval: Int,
        unit: QuillAutomationRecurrenceUnit,
        weekdays: [Int]? = nil,
        hour: Int? = nil,
        minute: Int? = nil
    ) {
        self.interval = max(1, interval)
        self.unit = unit
        self.weekdays = Self.normalizedWeekdays(weekdays)
        let clock = Self.normalizedClock(hour: hour, minute: minute)
        self.hour = clock?.hour
        self.minute = clock?.minute
    }

    public var intervalSeconds: TimeInterval {
        TimeInterval(interval * unit.seconds)
    }

    public var scheduleDescription: String {
        if let description = calendarScheduleDescription {
            return description
        }
        if interval == 1 {
            return "Every \(unit.label(count: 1))"
        }
        return "Every \(interval) \(unit.label(count: interval))"
    }

    public func nextRun(after date: Date) -> Date {
        nextRun(after: date, calendar: .current)
    }

    public func nextRun(after date: Date, calendar: Calendar) -> Date {
        guard let clock = Self.normalizedClock(hour: hour, minute: minute) else {
            return date.addingTimeInterval(intervalSeconds)
        }
        if let weekdays, !weekdays.isEmpty {
            return nextMatchingWeekday(
                after: date,
                weekdays: weekdays,
                clock: clock,
                calendar: calendar
            ) ?? date.addingTimeInterval(intervalSeconds)
        }
        guard unit == .days, interval == 1 else {
            return date.addingTimeInterval(intervalSeconds)
        }
        return nextMatchingClock(after: date, clock: clock, calendar: calendar)
            ?? date.addingTimeInterval(intervalSeconds)
    }

    private var calendarScheduleDescription: String? {
        guard let clock = Self.normalizedClock(hour: hour, minute: minute) else {
            return nil
        }
        let clockText = Self.clockDescription(hour: clock.hour, minute: clock.minute)
        if let weekdays, !weekdays.isEmpty {
            if weekdays == [2, 3, 4, 5, 6] {
                return "Every weekday at \(clockText)"
            }
            if weekdays == [1, 7] {
                return "Every weekend at \(clockText)"
            }
            if weekdays.count == 1, let weekday = weekdays.first {
                return "Every \(Self.weekdayDescription(weekday)) at \(clockText)"
            }
            if weekdays == [1, 2, 3, 4, 5, 6, 7] {
                return "Every day at \(clockText)"
            }
        }
        guard unit == .days, interval == 1 else { return nil }
        return "Every day at \(clockText)"
    }

    private func nextMatchingWeekday(
        after date: Date,
        weekdays: [Int],
        clock: (hour: Int, minute: Int),
        calendar: Calendar
    ) -> Date? {
        weekdays
            .compactMap { weekday in
                calendar.nextDate(
                    after: date,
                    matching: DateComponents(
                        calendar: calendar,
                        timeZone: calendar.timeZone,
                        hour: clock.hour,
                        minute: clock.minute,
                        second: 0,
                        weekday: weekday
                    ),
                    matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first,
                    direction: .forward
                )
            }
            .min()
    }

    private func nextMatchingClock(
        after date: Date,
        clock: (hour: Int, minute: Int),
        calendar: Calendar
    ) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                hour: clock.hour,
                minute: clock.minute,
                second: 0
            ),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private static func normalizedWeekdays(_ weekdays: [Int]?) -> [Int]? {
        guard let weekdays else { return nil }
        let normalized = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedClock(hour: Int?, minute: Int?) -> (hour: Int, minute: Int)? {
        guard let hour, (0...23).contains(hour) else { return nil }
        let minute = minute ?? 0
        guard (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func weekdayDescription(_ weekday: Int) -> String {
        switch weekday {
        case 1:
            return "Sunday"
        case 2:
            return "Monday"
        case 3:
            return "Tuesday"
        case 4:
            return "Wednesday"
        case 5:
            return "Thursday"
        case 6:
            return "Friday"
        case 7:
            return "Saturday"
        default:
            return "day"
        }
    }

    private static func clockDescription(hour: Int, minute: Int) -> String {
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let meridiem = hour < 12 ? "AM" : "PM"
        return "\(hour12):\(String(format: "%02d", minute)) \(meridiem)"
    }

}

public struct QuillAutomation: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var detail: String
    public var kind: QuillAutomationKind
    public var status: QuillAutomationStatus
    public var scheduleKind: QuillAutomationScheduleKind
    public var scheduleDescription: String
    public var projectID: UUID?
    public var threadID: UUID?
    public var eventSource: QuillAutomationEventSource?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastRunAt: Date?
    public var nextRunAt: Date?
    public var recurrence: QuillAutomationRecurrence?

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        kind: QuillAutomationKind,
        status: QuillAutomationStatus = .active,
        scheduleKind: QuillAutomationScheduleKind,
        scheduleDescription: String,
        projectID: UUID? = nil,
        threadID: UUID? = nil,
        eventSource: QuillAutomationEventSource? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.status = status
        self.scheduleKind = scheduleKind
        self.scheduleDescription = scheduleDescription
        self.projectID = projectID
        self.threadID = threadID
        self.eventSource = eventSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.recurrence = recurrence
    }

    public static func sortedForDisplay(_ automations: [QuillAutomation]) -> [QuillAutomation] {
        automations.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .active
            }
            switch (lhs.nextRunAt, rhs.nextRunAt) {
            case let (lhsRun?, rhsRun?) where lhsRun != rhsRun:
                return lhsRun < rhsRun
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }
}
