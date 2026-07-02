import Foundation
import QuillCodeCore

struct WorkspaceEnvironmentSchedulePlan: Sendable, Equatable {
    let action: LocalEnvironmentAction
    let schedule: ThreadFollowUpSchedule
}

enum WorkspaceEnvironmentSchedulePlanner {
    private static let scheduleMarkers = [
        " every ",
        " in ",
        " at ",
        " today",
        " tonight",
        " tomorrow",
        " monday",
        " tuesday",
        " wednesday",
        " thursday",
        " friday",
        " saturday",
        " sunday",
        " next "
    ]

    static func plan(
        _ text: String,
        actions: [LocalEnvironmentAction],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WorkspaceEnvironmentSchedulePlan? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for match in actionPrefixMatches(in: trimmed, actions: actions) {
            guard let schedule = ThreadFollowUpScheduleParser.parse(
                match.scheduleText,
                now: now,
                calendar: calendar
            ) else {
                continue
            }
            return WorkspaceEnvironmentSchedulePlan(action: match.action, schedule: schedule)
        }

        return splitAtScheduleMarker(trimmed).flatMap { split in
            guard let action = LocalEnvironmentActionMatcher.action(matching: split.actionText, in: actions),
                  let schedule = ThreadFollowUpScheduleParser.parse(
                    split.scheduleText,
                    now: now,
                    calendar: calendar
                  )
            else {
                return nil
            }
            return WorkspaceEnvironmentSchedulePlan(action: action, schedule: schedule)
        }
    }

    private static func actionPrefixMatches(
        in text: String,
        actions: [LocalEnvironmentAction]
    ) -> [(action: LocalEnvironmentAction, scheduleText: String)] {
        actions
            .flatMap { action in
                candidateNames(for: action).map { (action: action, candidate: $0) }
            }
            .sorted { lhs, rhs in
                lhs.candidate.count > rhs.candidate.count
            }
            .compactMap { match in
                scheduleText(afterConsuming: match.candidate, from: text).map {
                    (action: match.action, scheduleText: $0)
                }
            }
    }

    private static func candidateNames(for action: LocalEnvironmentAction) -> [String] {
        stableUnique([
            action.title,
            action.relativePath,
            action.id,
            LocalEnvironmentActionMatcher.normalizedActionName(action.title),
            LocalEnvironmentActionMatcher.normalizedActionName(action.relativePath)
        ])
    }

    private static func scheduleText(afterConsuming candidate: String, from text: String) -> String? {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard let match = text.range(
            of: candidate,
            options: [.caseInsensitive, .anchored],
            range: text.startIndex..<text.endIndex
        ) else {
            return nil
        }
        let rawRemainder = String(text[match.upperBound...])
        guard rawRemainder.first.map(\.isWhitespace) == true else { return nil }
        let remainder = rawRemainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return remainder.isEmpty ? nil : remainder
    }

    private static func splitAtScheduleMarker(_ text: String) -> (actionText: String, scheduleText: String)? {
        let lowercased = text.lowercased()
        guard let match = scheduleMarkers
            .compactMap({ marker -> (marker: String, range: Range<String.Index>)? in
                lowercased.range(of: marker).map { (marker, $0) }
            })
            .min(by: { $0.range.lowerBound < $1.range.lowerBound })
        else {
            return nil
        }

        let actionText = String(text[..<match.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let scheduleText = String(text[match.range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actionText.isEmpty, !scheduleText.isEmpty else { return nil }
        return (actionText, scheduleText)
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !value.isEmpty {
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }
}
