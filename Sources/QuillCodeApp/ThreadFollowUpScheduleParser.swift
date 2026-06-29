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

        if let recurrence = recurrence(from: normalized),
           recurrence.intervalSeconds <= maximumDelay {
            return ThreadFollowUpSchedule(
                scheduleDescription: recurrence.scheduleDescription,
                nextRunAt: recurrence.nextRun(after: now),
                recurrence: recurrence
            )
        }

        if let delay = relativeDelay(from: normalized), delay > 0, delay <= maximumDelay {
            return ThreadFollowUpSchedule(
                scheduleDescription: relativeDescription(seconds: delay),
                nextRunAt: now.addingTimeInterval(delay),
                recurrence: nil
            )
        }

        if let tomorrowTime = tomorrowClock(from: normalized) {
            return ThreadFollowUpSchedule(
                scheduleDescription: "Tomorrow at \(clockDescription(hour: tomorrowTime.hour, minute: tomorrowTime.minute))",
                nextRunAt: dateTomorrow(
                    from: now,
                    hour: tomorrowTime.hour,
                    minute: tomorrowTime.minute,
                    calendar: calendar
                ),
                recurrence: nil
            )
        }

        if let calendarSchedule = oneOffCalendarSchedule(
            from: normalized,
            now: now,
            calendar: calendar
        ) {
            return calendarSchedule
        }

        return nil
    }

    static func relativeDescription(seconds: TimeInterval) -> String {
        let roundedSeconds = Int(seconds.rounded())
        if roundedSeconds % 86_400 == 0 {
            let days = roundedSeconds / 86_400
            return days == 1 ? "In 1 day" : "In \(days) days"
        }
        if roundedSeconds % 3_600 == 0 {
            let hours = roundedSeconds / 3_600
            return hours == 1 ? "In 1 hour" : "In \(hours) hours"
        }
        if roundedSeconds % 60 == 0 {
            let minutes = roundedSeconds / 60
            return minutes == 1 ? "In 1 minute" : "In \(minutes) minutes"
        }
        return "In \(roundedSeconds) seconds"
    }

    private static func recurrence(from value: String) -> QuillAutomationRecurrence? {
        switch value {
        case "hourly", "every hour":
            return QuillAutomationRecurrence(interval: 1, unit: .hours)
        case "daily", "every day":
            return QuillAutomationRecurrence(interval: 1, unit: .days)
        case "weekly", "every week":
            return QuillAutomationRecurrence(interval: 1, unit: .weeks)
        default:
            break
        }

        guard value.hasPrefix("every ") else { return nil }
        let tokens = value.dropFirst("every ".count).split(separator: " ").map(String.init)
        if tokens.count == 1, let unit = recurrenceUnit(from: tokens[0]) {
            return QuillAutomationRecurrence(interval: 1, unit: unit)
        }
        guard tokens.count >= 2,
              let amount = Int(tokens[0]),
              amount > 0,
              let unit = recurrenceUnit(from: tokens[1])
        else {
            return nil
        }
        return QuillAutomationRecurrence(interval: amount, unit: unit)
    }

    private static func recurrenceUnit(from value: String) -> QuillAutomationRecurrenceUnit? {
        switch value {
        case "m", "min", "mins", "minute", "minutes":
            return .minutes
        case "h", "hr", "hrs", "hour", "hours":
            return .hours
        case "d", "day", "days":
            return .days
        case "w", "wk", "wks", "week", "weeks":
            return .weeks
        default:
            return nil
        }
    }

    private static func relativeDelay(from value: String) -> TimeInterval? {
        var tokens = value.split(separator: " ").map(String.init)
        if tokens.first == "in" {
            tokens.removeFirst()
        }
        guard tokens.count >= 2, let amount = Int(tokens[0]), amount > 0 else {
            return nil
        }
        switch tokens[1] {
        case "s", "sec", "secs", "second", "seconds":
            return TimeInterval(amount)
        case "m", "min", "mins", "minute", "minutes":
            return TimeInterval(amount * 60)
        case "h", "hr", "hrs", "hour", "hours":
            return TimeInterval(amount * 3_600)
        case "d", "day", "days":
            return TimeInterval(amount * 86_400)
        default:
            return nil
        }
    }

    private static func tomorrowClock(from value: String) -> (hour: Int, minute: Int)? {
        guard value == "tomorrow" || value.hasPrefix("tomorrow ") else { return nil }
        let remainder = value
            .dropFirst("tomorrow".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remainder.isEmpty else { return (9, 0) }

        switch remainder {
        case "morning":
            return (9, 0)
        case "afternoon":
            return (13, 0)
        case "evening":
            return (17, 0)
        default:
            let clockText = remainder
                .replacingOccurrences(of: "at ", with: "")
                .replacingOccurrences(of: "around ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return parseClock(clockText)
        }
    }

    private static func oneOffCalendarSchedule(
        from value: String,
        now: Date,
        calendar: Calendar
    ) -> ThreadFollowUpSchedule? {
        if let today = todaySchedule(from: value, now: now, calendar: calendar) {
            return today
        }
        if let weekday = weekdaySchedule(from: value, now: now, calendar: calendar) {
            return weekday
        }
        if let clock = bareClockSchedule(from: value, now: now, calendar: calendar) {
            return clock
        }
        return nil
    }

    private static func todaySchedule(
        from value: String,
        now: Date,
        calendar: Calendar
    ) -> ThreadFollowUpSchedule? {
        if value == "tonight" {
            return explicitTodaySchedule(
                label: "Tonight",
                clock: (19, 0),
                now: now,
                calendar: calendar
            )
        }
        if value.hasPrefix("tonight ") {
            let clockText = clockRemainder(value.dropFirst("tonight".count), defaultPrefix: "")
            guard let clock = parseClock(clockText, defaultMeridiem: "pm") else { return nil }
            return explicitTodaySchedule(label: "Tonight", clock: clock, now: now, calendar: calendar)
        }
        guard value.hasPrefix("today ") else { return nil }
        let remainder = value
            .dropFirst("today".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clock = dayPartClock(from: remainder) ?? parseClock(clockRemainder(remainder)) else {
            return nil
        }
        return explicitTodaySchedule(label: "Today", clock: clock, now: now, calendar: calendar)
    }

    private static func explicitTodaySchedule(
        label: String,
        clock: (hour: Int, minute: Int),
        now: Date,
        calendar: Calendar
    ) -> ThreadFollowUpSchedule? {
        let date = dateOnDay(from: now, addingDays: 0, hour: clock.hour, minute: clock.minute, calendar: calendar)
        guard date > now else { return nil }
        return ThreadFollowUpSchedule(
            scheduleDescription: "\(label) at \(clockDescription(hour: clock.hour, minute: clock.minute))",
            nextRunAt: date,
            recurrence: nil
        )
    }

    private static func bareClockSchedule(
        from value: String,
        now: Date,
        calendar: Calendar
    ) -> ThreadFollowUpSchedule? {
        let clockText = clockRemainder(value)
        guard clockText != String(value) || value.contains(":") || value.range(of: #"^\d{1,2}\s*(am|pm)$"#, options: .regularExpression) != nil,
              let clock = parseClock(clockText)
        else {
            return nil
        }
        let today = dateOnDay(from: now, addingDays: 0, hour: clock.hour, minute: clock.minute, calendar: calendar)
        let date: Date
        let label: String
        if today > now {
            date = today
            label = "Today"
        } else {
            date = dateOnDay(from: now, addingDays: 1, hour: clock.hour, minute: clock.minute, calendar: calendar)
            label = "Tomorrow"
        }
        return ThreadFollowUpSchedule(
            scheduleDescription: "\(label) at \(clockDescription(hour: clock.hour, minute: clock.minute))",
            nextRunAt: date,
            recurrence: nil
        )
    }

    private static func weekdaySchedule(
        from value: String,
        now: Date,
        calendar: Calendar
    ) -> ThreadFollowUpSchedule? {
        let tokens = value.split(separator: " ", maxSplits: 2).map(String.init)
        guard !tokens.isEmpty else { return nil }

        let isExplicitNext = tokens.first == "next"
        let isExplicitThis = tokens.first == "this" || tokens.first == "on"
        let weekdayTokenIndex = (isExplicitNext || isExplicitThis) ? 1 : 0
        guard tokens.indices.contains(weekdayTokenIndex),
              let weekday = weekdayNumber(from: tokens[weekdayTokenIndex])
        else {
            return nil
        }

        let consumedPrefixCount = weekdayTokenIndex + 1
        let remainder = tokens.dropFirst(consumedPrefixCount).joined(separator: " ")
        let clock = dayPartClock(from: remainder)
            ?? parseClock(clockRemainder(remainder))
            ?? (9, 0)
        guard let candidate = nextDate(
            matchingWeekday: weekday,
            hour: clock.hour,
            minute: clock.minute,
            after: now,
            calendar: calendar
        ) else {
            return nil
        }
        let scheduled = isExplicitNext && calendar.isDate(candidate, inSameDayAs: now)
            ? calendar.date(byAdding: .day, value: 7, to: candidate) ?? candidate
            : candidate
        guard scheduled.timeIntervalSince(now) <= maximumDelay else { return nil }

        let weekdayName = weekdayDescription(weekday)
        let prefix = isExplicitNext ? "Next \(weekdayName)" : weekdayName
        return ThreadFollowUpSchedule(
            scheduleDescription: "\(prefix) at \(clockDescription(hour: clock.hour, minute: clock.minute))",
            nextRunAt: scheduled,
            recurrence: nil
        )
    }

    private static func parseClock(
        _ value: String,
        defaultMeridiem: String? = nil
    ) -> (hour: Int, minute: Int)? {
        var text = value
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        if text == "noon" {
            return (12, 0)
        }
        if text == "midnight" {
            return (0, 0)
        }
        let meridiem: String?
        if text.hasSuffix("am") {
            meridiem = "am"
            text.removeLast(2)
        } else if text.hasSuffix("pm") {
            meridiem = "pm"
            text.removeLast(2)
        } else {
            meridiem = defaultMeridiem
        }

        let pieces = text.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2,
              let rawHour = Int(pieces[0]),
              rawHour >= 0,
              rawHour <= 23
        else {
            return nil
        }
        let minute: Int
        if pieces.count == 2 {
            guard pieces[1].count == 2,
                  let parsedMinute = Int(pieces[1]),
                  parsedMinute >= 0,
                  parsedMinute < 60
            else {
                return nil
            }
            minute = parsedMinute
        } else {
            minute = 0
        }

        var hour = rawHour
        if meridiem == "pm", hour < 12 {
            hour += 12
        } else if meridiem == "am", hour == 12 {
            hour = 0
        }
        guard hour < 24 else { return nil }
        return (hour, minute)
    }

    private static func clockRemainder<T: StringProtocol>(
        _ value: T,
        defaultPrefix: String = "at"
    ) -> String {
        var text = String(value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in [defaultPrefix, "at", "around", "about"] where !prefix.isEmpty {
            if text.hasPrefix("\(prefix) ") {
                text = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    private static func dayPartClock(from value: String) -> (hour: Int, minute: Int)? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "morning":
            return (9, 0)
        case "afternoon":
            return (13, 0)
        case "evening":
            return (17, 0)
        case "tonight", "night":
            return (19, 0)
        default:
            return nil
        }
    }

    private static func nextDate(
        matchingWeekday weekday: Int,
        hour: Int,
        minute: Int,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.nextDate(
            after: now,
            matching: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                hour: hour,
                minute: minute,
                second: 0,
                weekday: weekday
            ),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private static func dateOnDay(
        from now: Date,
        addingDays dayOffset: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.day = (components.day ?? 0) + dayOffset
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? now.addingTimeInterval(TimeInterval(dayOffset) * 24 * 60 * 60)
    }

    private static func weekdayNumber(from value: String) -> Int? {
        switch value {
        case "sunday", "sun":
            return 1
        case "monday", "mon":
            return 2
        case "tuesday", "tue", "tues":
            return 3
        case "wednesday", "wed":
            return 4
        case "thursday", "thu", "thur", "thurs":
            return 5
        case "friday", "fri":
            return 6
        case "saturday", "sat":
            return 7
        default:
            return nil
        }
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
            return "Weekday"
        }
    }

    private static func dateTomorrow(
        from now: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.day = (components.day ?? 0) + 1
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    private static func clockDescription(hour: Int, minute: Int) -> String {
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let meridiem = hour < 12 ? "AM" : "PM"
        return "\(hour12):\(String(format: "%02d", minute)) \(meridiem)"
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
