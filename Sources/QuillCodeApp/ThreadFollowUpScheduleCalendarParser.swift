import Foundation

enum ThreadFollowUpScheduleCalendarParser {
    typealias Clock = (hour: Int, minute: Int)

    static func tomorrowSchedule(
        from value: String,
        now: Date,
        calendar: Calendar
    ) -> ThreadFollowUpSchedule? {
        guard let clock = tomorrowClock(from: value) else { return nil }
        return ThreadFollowUpSchedule(
            scheduleDescription: "Tomorrow at \(clockDescription(hour: clock.hour, minute: clock.minute))",
            nextRunAt: dateTomorrow(from: now, hour: clock.hour, minute: clock.minute, calendar: calendar),
            recurrence: nil
        )
    }

    static func oneOffSchedule(
        from value: String,
        now: Date,
        calendar: Calendar,
        maximumDelay: TimeInterval
    ) -> ThreadFollowUpSchedule? {
        if let today = todaySchedule(from: value, now: now, calendar: calendar) {
            return today
        }
        if let weekday = weekdaySchedule(
            from: value,
            now: now,
            calendar: calendar,
            maximumDelay: maximumDelay
        ) {
            return weekday
        }
        if let clock = bareClockSchedule(from: value, now: now, calendar: calendar) {
            return clock
        }
        return nil
    }

    private static func tomorrowClock(from value: String) -> Clock? {
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

    private static func todaySchedule(
        from value: String,
        now: Date,
        calendar: Calendar
    ) -> ThreadFollowUpSchedule? {
        if value == "tonight" {
            return explicitTodaySchedule(label: "Tonight", clock: (19, 0), now: now, calendar: calendar)
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
        clock: Clock,
        now: Date,
        calendar: Calendar
    ) -> ThreadFollowUpSchedule? {
        let date = dateOnDay(
            from: now,
            addingDays: 0,
            hour: clock.hour,
            minute: clock.minute,
            calendar: calendar
        )
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
        guard isBareClockCandidate(original: value, normalizedClockText: clockText),
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

    private static func isBareClockCandidate(original: String, normalizedClockText: String) -> Bool {
        normalizedClockText != original
            || original.contains(":")
            || original.range(of: #"^\d{1,2}\s*(am|pm)$"#, options: .regularExpression) != nil
    }

    private static func weekdaySchedule(
        from value: String,
        now: Date,
        calendar: Calendar,
        maximumDelay: TimeInterval
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

        let clock = weekdayClock(from: tokens.dropFirst(weekdayTokenIndex + 1).joined(separator: " "))
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

    static func weekdayClock(from remainder: String) -> Clock {
        dayPartClock(from: remainder) ?? parseClock(clockRemainder(remainder)) ?? (9, 0)
    }

    static func parseClock(_ value: String, defaultMeridiem: String? = nil) -> Clock? {
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

        let meridiem = stripMeridiem(from: &text, defaultMeridiem: defaultMeridiem)
        let pieces = text.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2,
              let rawHour = Int(pieces[0]),
              rawHour >= 0,
              rawHour <= 23
        else {
            return nil
        }
        guard let minute = minuteValue(from: pieces) else { return nil }

        var hour = rawHour
        if meridiem == "pm", hour < 12 {
            hour += 12
        } else if meridiem == "am", hour == 12 {
            hour = 0
        }
        guard hour < 24 else { return nil }
        return (hour, minute)
    }

    private static func stripMeridiem(from text: inout String, defaultMeridiem: String?) -> String? {
        if text.hasSuffix("am") {
            text.removeLast(2)
            return "am"
        }
        if text.hasSuffix("pm") {
            text.removeLast(2)
            return "pm"
        }
        return defaultMeridiem
    }

    private static func minuteValue(from pieces: [Substring]) -> Int? {
        guard pieces.count == 2 else { return 0 }
        guard pieces[1].count == 2,
              let minute = Int(pieces[1]),
              minute >= 0,
              minute < 60
        else {
            return nil
        }
        return minute
    }

    static func clockRemainder<T: StringProtocol>(_ value: T, defaultPrefix: String = "at") -> String {
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

    static func dayPartClock(from value: String) -> Clock? {
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
        return calendar.date(from: components) ?? now.addingTimeInterval(TimeInterval(dayOffset) * 86_400)
    }

    static func weekdayNumber(from value: String) -> Int? {
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
        return calendar.date(from: components) ?? now.addingTimeInterval(86_400)
    }

    private static func clockDescription(hour: Int, minute: Int) -> String {
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let meridiem = hour < 12 ? "AM" : "PM"
        return "\(hour12):\(String(format: "%02d", minute)) \(meridiem)"
    }
}
