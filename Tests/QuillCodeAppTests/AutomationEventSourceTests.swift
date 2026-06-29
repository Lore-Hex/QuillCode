import XCTest
@testable import QuillCodeApp

final class AutomationEventSourceTests: XCTestCase {
    private func temporaryFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("automation-event-\(UUID().uuidString).txt")
    }

    func testFileChangeEventSourceFiresForModificationAfterSince() throws {
        let url = temporaryFileURL()
        try "x".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = FileChangeEventSource(path: url)
        let event = source.pendingEvent(since: Date(timeIntervalSince1970: 0))

        XCTAssertNotNil(event)
        XCTAssertTrue(event?.contains(url.lastPathComponent) == true)
    }

    func testFileChangeEventSourceIgnoresModificationsBeforeSince() throws {
        let url = temporaryFileURL()
        try "x".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = FileChangeEventSource(path: url)
        XCTAssertNil(source.pendingEvent(since: Date(timeIntervalSinceNow: 3_600)))
    }

    func testFileChangeEventSourceFiresWithoutSinceWhenFileExists() throws {
        let url = temporaryFileURL()
        try "x".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let source = FileChangeEventSource(path: url)
        XCTAssertNotNil(source.pendingEvent(since: nil))
    }

    func testFileChangeEventSourceIsNilForMissingFile() {
        let source = FileChangeEventSource(
            path: URL(fileURLWithPath: "/nonexistent/automation-\(UUID().uuidString)")
        )
        XCTAssertNil(source.pendingEvent(since: nil))
    }
}
