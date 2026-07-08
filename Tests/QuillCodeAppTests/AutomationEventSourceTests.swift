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

    func testDirectoryChangeEventSourceFiresForModificationAfterSince() {
        let modifiedAt = Date(timeIntervalSince1970: 200)
        let source = DirectoryChangeEventSource(
            path: URL(fileURLWithPath: "/watched/logs"),
            modificationDate: { _ in modifiedAt }
        )

        XCTAssertEqual(source.pendingEvent(since: Date(timeIntervalSince1970: 199)), "logs directory changed")
        XCTAssertNil(source.pendingEvent(since: modifiedAt))
    }

    func testURLLastModifiedEventSourceFiresForNewerHeader() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/feed.xml"))
        let modifiedAt = Date(timeIntervalSince1970: 200)
        let source = URLLastModifiedEventSource(
            url: url,
            lastModifiedDate: { _ in modifiedAt }
        )

        XCTAssertEqual(
            source.pendingEvent(since: Date(timeIntervalSince1970: 199)),
            "https://example.com/feed.xml Last-Modified changed"
        )
        XCTAssertNil(source.pendingEvent(since: modifiedAt))
    }

    func testURLLastModifiedEventSourceStaysQuietWithoutHeader() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/feed.xml"))
        let source = URLLastModifiedEventSource(url: url, lastModifiedDate: { _ in nil })

        XCTAssertNil(source.pendingEvent(since: nil))
    }

    func testURLFeedUpdateEventSourceFiresForNewerFeedTimestamp() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/feed.xml"))
        let updatedAt = Date(timeIntervalSince1970: 300)
        let source = URLFeedUpdateEventSource(url: url, latestDate: { _ in updatedAt })

        XCTAssertEqual(
            source.pendingEvent(since: Date(timeIntervalSince1970: 299)),
            "https://example.com/feed.xml feed updated"
        )
        XCTAssertNil(source.pendingEvent(since: updatedAt))
    }

    func testURLFeedUpdateEventSourceStaysQuietWithoutFeedTimestamp() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/feed.xml"))
        let source = URLFeedUpdateEventSource(url: url, latestDate: { _ in nil })

        XCTAssertNil(source.pendingEvent(since: nil))
    }

    func testURLFeedUpdateEventSourceParsesRSSAndAtomDates() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/feed.xml"))
        let rssSource = URLFeedUpdateEventSource(url: url, latestDate: { _ in
            URLFeedUpdateEventSource.defaultLatestDate(
                in: """
                <rss><channel>
                  <item><pubDate>Mon, 06 Jul 2026 16:00:00 GMT</pubDate></item>
                  <item><pubDate>Mon, 06 Jul 2026 17:00:00 GMT</pubDate></item>
                </channel></rss>
                """
            )
        })
        let atomSource = URLFeedUpdateEventSource(url: url, latestDate: { _ in
            URLFeedUpdateEventSource.defaultLatestDate(
                in: """
                <feed xmlns="http://www.w3.org/2005/Atom">
                  <entry><updated>2026-07-06T18:30:00Z</updated></entry>
                </feed>
                """
            )
        })

        XCTAssertNotNil(rssSource.pendingEvent(since: Date(timeIntervalSince1970: 0)))
        XCTAssertNotNil(atomSource.pendingEvent(since: Date(timeIntervalSince1970: 0)))
        let atomDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T18:30:00Z"))
        XCTAssertNil(atomSource.pendingEvent(since: atomDate))
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

    func testDirectoryChangeResolverUsesSameProjectBoundsAsFileChanges() {
        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-project")
        let project = ProjectRef(name: "QuillCode", path: projectRoot.path)

        let url = AutomationEventSourceResolver.directoryChangeURL(
            for: "logs",
            project: project
        )

        XCTAssertEqual(
            url?.path,
            projectRoot.appendingPathComponent("logs").standardizedFileURL.path
        )
        XCTAssertNil(AutomationEventSourceResolver.directoryChangeURL(
            for: "../logs",
            project: project
        ))
    }

    func testURLLastModifiedResolverAllowsHTTPAndHTTPSOnly() {
        XCTAssertEqual(
            AutomationEventSourceResolver.urlLastModifiedURL(for: " https://example.com/feed.xml ")?.absoluteString,
            "https://example.com/feed.xml"
        )
        XCTAssertEqual(
            AutomationEventSourceResolver.urlLastModifiedURL(for: "http://localhost/status")?.absoluteString,
            "http://localhost/status"
        )
        XCTAssertNil(AutomationEventSourceResolver.urlLastModifiedURL(for: "file:///tmp/watch.txt"))
        XCTAssertNil(AutomationEventSourceResolver.urlLastModifiedURL(for: "example.com/feed.xml"))
        XCTAssertNil(AutomationEventSourceResolver.urlLastModifiedURL(for: "https://"))
    }

    func testURLFeedUpdateResolverAllowsHTTPAndHTTPSOnly() {
        XCTAssertEqual(
            AutomationEventSourceResolver.urlFeedUpdateURL(for: " https://example.com/feed.xml ")?.absoluteString,
            "https://example.com/feed.xml"
        )
        XCTAssertEqual(
            AutomationEventSourceResolver.urlFeedUpdateURL(for: "http://localhost/feed.xml")?.absoluteString,
            "http://localhost/feed.xml"
        )
        XCTAssertNil(AutomationEventSourceResolver.urlFeedUpdateURL(for: "file:///tmp/feed.xml"))
        XCTAssertNil(AutomationEventSourceResolver.urlFeedUpdateURL(for: "example.com/feed.xml"))
        XCTAssertNil(AutomationEventSourceResolver.urlFeedUpdateURL(for: "https://"))
    }

    func testResolverBuildsURLLastModifiedSource() {
        let source = AutomationEventSourceResolver.eventSource(
            for: QuillAutomationEventSource(
                kind: .urlLastModified,
                path: "https://example.com/feed.xml"
            ),
            project: nil
        )

        XCTAssertTrue(source is URLLastModifiedEventSource)
    }

    func testResolverBuildsDirectoryChangeSource() {
        let projectRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quillcode-project")
        let project = ProjectRef(name: "QuillCode", path: projectRoot.path)
        let source = AutomationEventSourceResolver.eventSource(
            for: QuillAutomationEventSource(
                kind: .directoryChange,
                path: "logs"
            ),
            project: project
        )

        XCTAssertTrue(source is DirectoryChangeEventSource)
    }

    func testResolverBuildsURLFeedUpdateSource() {
        let source = AutomationEventSourceResolver.eventSource(
            for: QuillAutomationEventSource(
                kind: .urlFeedUpdate,
                path: "https://example.com/feed.xml"
            ),
            project: nil
        )

        XCTAssertTrue(source is URLFeedUpdateEventSource)
    }
}
