import Foundation

enum SidebarActivityLabelFormatter {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * minute
    private static let day: TimeInterval = 24 * hour
    private static let week: TimeInterval = 7 * day

    static func label(for date: Date, relativeTo now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        switch elapsed {
        case ..<minute:
            return "now"
        case ..<hour:
            return "\(Int(elapsed / minute))m"
        case ..<day:
            return "\(Int(elapsed / hour))h"
        case ..<week:
            return "\(Int(elapsed / day))d"
        case ..<(8 * week):
            return "\(Int(elapsed / week))w"
        default:
            return calendarLabel(for: date, relativeTo: now)
        }
    }

    private static func calendarLabel(for date: Date, relativeTo now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdy")
        return formatter.string(from: date)
    }
}
