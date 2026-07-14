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

    func testOlderActivityFallsBackToALocalizedCalendarLabel() {
        let oldDate = now.addingTimeInterval(-90 * 24 * 60 * 60)
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMdy")

        let label = SidebarActivityLabelFormatter.label(for: oldDate, relativeTo: now)

        XCTAssertEqual(label, formatter.string(from: oldDate))
    }
}
