import XCTest
import QuillCodeCore
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

    func testFileChangeEventSourceCanUseDeterministicModificationProvider() {
        let modifiedAt = Date(timeIntervalSince1970: 100)
        let source = FileChangeEventSource(
            path: URL(fileURLWithPath: "/watched/example.txt"),
            modificationDate: { _ in modifiedAt }
        )

        XCTAssertEqual(source.pendingEvent(since: Date(timeIntervalSince1970: 99)), "example.txt changed")
        XCTAssertNil(source.pendingEvent(since: modifiedAt))
    }

    func testFileChangeEventSourceIsNilForMissingFile() {
        let source = FileChangeEventSource(
            path: URL(fileURLWithPath: "/nonexistent/automation-\(UUID().uuidString)")
        )
        XCTAssertNil(source.pendingEvent(since: nil))
    }

    func testFileChangeResolverAllowsAbsolutePathsWithoutProject() {
        let url = AutomationEventSourceResolver.fileChangeURL(
            for: "/tmp/quillcode/watch.log",
            project: nil
        )

        XCTAssertEqual(url?.path, "/tmp/quillcode/watch.log")
    }

    func testFileChangeResolverResolvesRelativePathsInsideLocalProject() {
        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-project")
        let project = ProjectRef(name: "QuillCode", path: projectRoot.path)

        let url = AutomationEventSourceResolver.fileChangeURL(
            for: "logs/watch.log",
            project: project
        )

        XCTAssertEqual(
            url?.path,
            projectRoot.appendingPathComponent("logs/watch.log").standardizedFileURL.path
        )
    }

    func testFileChangeResolverRejectsProjectRelativePathEscapes() {
        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-project")
        let project = ProjectRef(name: "QuillCode", path: projectRoot.path)

        XCTAssertNil(AutomationEventSourceResolver.fileChangeURL(
            for: "../outside.log",
            project: project
        ))
    }

    func testFileChangeResolverRejectsRelativePathsForRemoteProjects() {
        let project = ProjectRef(
            name: "Feather",
            path: "/srv/quill",
            connection: .ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        )

        XCTAssertNil(AutomationEventSourceResolver.fileChangeURL(
            for: "logs/watch.log",
            project: project
        ))
    }
}
