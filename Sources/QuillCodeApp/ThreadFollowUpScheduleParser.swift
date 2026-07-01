import Foundation
import QuillCodeCore

struct ThreadFollowUpSchedule: Equatable, Sendable {
    var scheduleDescription: String
    var nextRunAt: Date
    var recurrence: QuillAutomationRecurrence?
}

enum ThreadFollowUpScheduleParser {
    private static let maximumDelay: TimeInterval = 366 * 24 * 60 * 60

    static func parse(
        _ value: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ThreadFollowUpSchedule? {
        let normalized = normalize(value)
        guard !normalized.isEmpty else { return nil }

        if let recurrence = ThreadFollowUpScheduleIntervalParser.recurrence(from: normalized),
           recurrence.intervalSeconds <= maximumDelay {
            return ThreadFollowUpSchedule(
                scheduleDescription: recurrence.scheduleDescription,
                nextRunAt: recurrence.nextRun(after: now),
                recurrence: recurrence
            )
        }

        if let delay = ThreadFollowUpScheduleIntervalParser.relativeDelay(from: normalized),
           delay > 0,
           delay <= maximumDelay {
            return ThreadFollowUpSchedule(
                scheduleDescription: relativeDescription(seconds: delay),
                nextRunAt: now.addingTimeInterval(delay),
                recurrence: nil
            )
        }

        if let tomorrow = ThreadFollowUpScheduleCalendarParser.tomorrowSchedule(
            from: normalized,
            now: now,
            calendar: calendar
        ) {
            return tomorrow
        }

        if let calendarSchedule = ThreadFollowUpScheduleCalendarParser.oneOffSchedule(
            from: normalized,
            now: now,
            calendar: calendar,
            maximumDelay: maximumDelay
        ) {
            return calendarSchedule
        }

        return nil
    }

    static func relativeDescription(seconds: TimeInterval) -> String {
        ThreadFollowUpScheduleIntervalParser.relativeDescription(seconds: seconds)
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
    }
}
