import XCTest
@testable import QuillCodeApp

final class SidebarActivityLabelFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFormatsRecentActivityWithCompactStableUnits() {
        let examples: [(TimeInterval, String)] = [
            (0, "now"),
            (59, "now"),
            (60, "1m"),
            (59 * 60, "59m"),
            (60 * 60, "1h"),
            (23 * 60 * 60, "23h"),
            (24 * 60 * 60, "1d"),
            (6 * 24 * 60 * 60, "6d"),
            (7 * 24 * 60 * 60, "1w"),
            (55 * 24 * 60 * 60, "7w")
        ]

        for (elapsed, expected) in examples {
            XCTAssertEqual(
                SidebarActivityLabelFormatter.label(
                    for: now.addingTimeInterval(-elapsed),
                    relativeTo: now
                ),
                expected
            )
        }
    }

    func testFutureActivityDoesNotRenderANegativeAge() {
        XCTAssertEqual(
            SidebarActivityLabelFormatter.label(
                for: now.addingTimeInterval(60),
                relativeTo: now
            ),
            "now"
        )
    }

    func testOlderActivityUsesACompactLocalizedCalendarLabel() {
        let oldDate = now.addingTimeInterval(-90 * 24 * 60 * 60)
        var style = Date.FormatStyle.dateTime
            .locale(.autoupdatingCurrent)
            .year(.twoDigits)
            .month(.defaultDigits)
            .day(.defaultDigits)
        style.timeZone = .autoupdatingCurrent

        let label = SidebarActivityLabelFormatter.label(for: oldDate, relativeTo: now)

        XCTAssertEqual(label, oldDate.formatted(style))
    }

    func testOlderSameYearActivityKeepsTheReadableMonthNameWithoutAYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let sameYearNow = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12))
        )
        let oldDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 4, hour: 12))
        )
        var style = Date.FormatStyle.dateTime
            .locale(.autoupdatingCurrent)
            .month(.abbreviated)
            .day()
        style.timeZone = .autoupdatingCurrent

        XCTAssertEqual(
            SidebarActivityLabelFormatter.label(for: oldDate, relativeTo: sameYearNow),
            oldDate.formatted(style)
        )
    }
}
