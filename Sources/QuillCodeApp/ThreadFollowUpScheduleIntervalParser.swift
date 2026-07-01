import Foundation
import QuillCodeCore

enum ThreadFollowUpScheduleIntervalParser {
    static func recurrence(from value: String) -> QuillAutomationRecurrence? {
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

    static func relativeDelay(from value: String) -> TimeInterval? {
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
}
