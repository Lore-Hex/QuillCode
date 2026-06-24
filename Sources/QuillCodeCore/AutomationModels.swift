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

    public init(interval: Int, unit: QuillAutomationRecurrenceUnit) {
        self.interval = max(1, interval)
        self.unit = unit
    }

    public var intervalSeconds: TimeInterval {
        TimeInterval(interval * unit.seconds)
    }

    public var scheduleDescription: String {
        if interval == 1 {
            return "Every \(unit.label(count: 1))"
        }
        return "Every \(interval) \(unit.label(count: interval))"
    }

    public func nextRun(after date: Date) -> Date {
        date.addingTimeInterval(intervalSeconds)
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
