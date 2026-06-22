import Foundation

struct ThreadFollowUpSchedule: Equatable, Sendable {
    var scheduleDescription: String
    var nextRunAt: Date
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

        if let delay = relativeDelay(from: normalized), delay > 0, delay <= maximumDelay {
            return ThreadFollowUpSchedule(
                scheduleDescription: relativeDescription(seconds: delay),
                nextRunAt: now.addingTimeInterval(delay)
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
                )
            )
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

    private static func parseClock(_ value: String) -> (hour: Int, minute: Int)? {
        var text = value
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        let meridiem: String?
        if text.hasSuffix("am") {
            meridiem = "am"
            text.removeLast(2)
        } else if text.hasSuffix("pm") {
            meridiem = "pm"
            text.removeLast(2)
        } else {
            meridiem = nil
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
