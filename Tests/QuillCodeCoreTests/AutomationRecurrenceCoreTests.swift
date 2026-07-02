import Foundation
import XCTest
@testable import QuillCodeCore

final class AutomationRecurrenceCoreTests: XCTestCase {
    func testCalendarAutomationRecurrenceDescribesAndAdvancesWeekdays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let mondayMorning = try XCTUnwrap(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 6,
            hour: 10,
            minute: 0,
            second: 0
        )))
        let mondayEvening = try XCTUnwrap(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 6,
            hour: 18,
            minute: 0,
            second: 0
        )))
        let tuesdayEvening = try XCTUnwrap(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 7,
            hour: 18,
            minute: 0,
            second: 0
        )))
        let recurrence = QuillAutomationRecurrence(
            interval: 1,
            unit: .weeks,
            weekdays: [6, 2, 3, 4, 5],
            hour: 18,
            minute: 0
        )

        XCTAssertEqual(recurrence.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(recurrence.scheduleDescription, "Every weekday at 6:00 PM")
        XCTAssertEqual(recurrence.nextRun(after: mondayMorning, calendar: calendar), mondayEvening)
        XCTAssertEqual(recurrence.nextRun(after: mondayEvening, calendar: calendar), tuesdayEvening)
    }

    func testCalendarAutomationRecurrenceDecodesOlderIntervalPayload() throws {
        let data = try XCTUnwrap(#"{"interval":2,"unit":"hours"}"#.data(using: .utf8))

        let recurrence = try JSONDecoder().decode(QuillAutomationRecurrence.self, from: data)

        XCTAssertEqual(recurrence, QuillAutomationRecurrence(interval: 2, unit: .hours))
        XCTAssertNil(recurrence.weekdays)
        XCTAssertNil(recurrence.hour)
        XCTAssertNil(recurrence.minute)
        XCTAssertEqual(recurrence.scheduleDescription, "Every 2 hours")
    }
}
