import Foundation
import QuillCodeCore

enum ThreadFollowUpScheduleCalendarRecurrenceParser {
    typealias Clock = ThreadFollowUpScheduleCalendarParser.Clock

    static func recurringCalendarSchedule(
        from value: String,
        now: Date,
        calendar: Calendar,
        maximumDelay: TimeInterval
    ) -> ThreadFollowUpSchedule? {
        guard let recurrence = calendarRecurrence(from: value) else { return nil }
        let nextRunAt = recurrence.nextRun(after: now, calendar: calendar)
        guard nextRunAt.timeIntervalSince(now) <= maximumDelay else { return nil }
        return ThreadFollowUpSchedule(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence
        )
    }

    private static func calendarRecurrence(from value: String) -> QuillAutomationRecurrence? {
        let recurrenceText = recurrenceText(from: value)
        let pieces = recurrenceText.text.split(separator: " ", maxSplits: 1).map(String.init)
        guard let rawTarget = pieces.first else { return nil }

        let target = singularTarget(rawTarget)
        let remainder = pieces.dropFirst().first ?? ""
        if let weekdaySet = weekdaySet(from: target) {
            guard recurrenceText.hasExplicitPrefix || isPluralWeekdaySet(rawTarget) else { return nil }
            return weeklyRecurrence(weekdays: weekdaySet, remainder: remainder)
        }

        if let weekday = ThreadFollowUpScheduleCalendarParser.weekdayNumber(from: target) {
            guard recurrenceText.hasExplicitPrefix || isPluralWeekdayName(rawTarget) else { return nil }
            return weeklyRecurrence(weekdays: [weekday], remainder: remainder)
        }

        if let dayPart = ThreadFollowUpScheduleCalendarParser.dayPartClock(from: target), remainder.isEmpty {
            guard recurrenceText.hasExplicitPrefix else { return nil }
            return dailyRecurrence(clock: dayPart)
        }

        guard target == "daily" || target == "day" else { return nil }
        guard target == "daily" || recurrenceText.hasExplicitPrefix else { return nil }
        guard !remainder.isEmpty else { return nil }
        let clock = ThreadFollowUpScheduleCalendarParser.dayPartClock(from: remainder)
            ?? ThreadFollowUpScheduleCalendarParser.parseClock(
                ThreadFollowUpScheduleCalendarParser.clockRemainder(remainder)
            )
        guard let clock else { return nil }
        return dailyRecurrence(clock: clock)
    }

    private static func weeklyRecurrence(
        weekdays: [Int],
        remainder: String
    ) -> QuillAutomationRecurrence {
        let clock = ThreadFollowUpScheduleCalendarParser.weekdayClock(from: remainder)
        return QuillAutomationRecurrence(
            interval: 1,
            unit: .weeks,
            weekdays: weekdays,
            hour: clock.hour,
            minute: clock.minute
        )
    }

    private static func dailyRecurrence(clock: Clock) -> QuillAutomationRecurrence {
        QuillAutomationRecurrence(
            interval: 1,
            unit: .days,
            hour: clock.hour,
            minute: clock.minute
        )
    }

    private static func recurrenceText(from value: String) -> (text: String, hasExplicitPrefix: Bool) {
        for prefix in ["every ", "each "] where value.hasPrefix(prefix) {
            return (
                String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines),
                true
            )
        }
        return (value, false)
    }

    private static func singularTarget(_ value: String) -> String {
        switch value {
        case "mondays":
            return "monday"
        case "tuesdays":
            return "tuesday"
        case "wednesdays":
            return "wednesday"
        case "thursdays":
            return "thursday"
        case "fridays":
            return "friday"
        case "saturdays":
            return "saturday"
        case "sundays":
            return "sunday"
        case "weekdays":
            return "weekday"
        case "weekends":
            return "weekend"
        default:
            return value
        }
    }

    private static func weekdaySet(from value: String) -> [Int]? {
        switch value {
        case "weekday":
            return [2, 3, 4, 5, 6]
        case "weekend":
            return [1, 7]
        default:
            return nil
        }
    }

    private static func isPluralWeekdaySet(_ value: String) -> Bool {
        value == "weekdays" || value == "weekends"
    }

    private static func isPluralWeekdayName(_ value: String) -> Bool {
        switch value {
        case "mondays", "tuesdays", "wednesdays", "thursdays", "fridays", "saturdays", "sundays":
            return true
        default:
            return false
        }
    }
}
