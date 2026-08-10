import Foundation
import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopIssueReporterTests: XCTestCase {
    func testIssueURLContainsOnlyBoundedBuildAndSystemMetadata() throws {
        let commit = String(repeating: "a", count: 40)
        let metadata = QuillCodeDesktopBuildMetadata(
            version: "0.2.0",
            build: "641",
            commit: commit,
            channel: "tester",
            architecture: "arm64",
            operatingSystem: "macOS 15.6.0"
        )

        let url = try XCTUnwrap(QuillCodeDesktopIssueReporter.issueURL(metadata: metadata))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try components.queryItems.orEmpty.map { item in
            (item.name, try XCTUnwrap(item.value))
        })

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/Lore-Hex/QuillCode/issues/new")
        XCTAssertEqual(query["labels"], "bug")
        XCTAssertEqual(query["title"], "[Bug] ")
        let body = try XCTUnwrap(query["body"])
        for expected in ["0.2.0 (641)", commit, "tester", "macOS 15.6.0", "arm64"] {
            XCTAssertTrue(body.contains(expected), body)
        }
        for forbidden in ["/Users/", "transcript", "API key:", "project path"] {
            XCTAssertFalse(body.contains(forbidden), body)
        }
    }

    func testBuildMetadataRejectsNoncanonicalEmbeddedCommit() {
        XCTAssertTrue(
            QuillCodeDesktopBuildMetadata.isCanonicalCommit(String(repeating: "a", count: 40))
        )
        XCTAssertFalse(
            QuillCodeDesktopBuildMetadata.isCanonicalCommit(String(repeating: "A", count: 40))
        )
        XCTAssertFalse(QuillCodeDesktopBuildMetadata.isCanonicalCommit("development"))
    }

    func testUnexpectedExitReportContainsOnlyBoundedBuildIncidentContext() throws {
        let current = QuillCodeDesktopBuildMetadata(
            version: "0.1.0",
            build: "698",
            commit: String(repeating: "b", count: 40),
            channel: "tester",
            architecture: "arm64",
            operatingSystem: "macOS 15.6.0"
        )
        let previous = QuillCodeDesktopBuildMetadata(
            version: "0.1.0",
            build: "697",
            commit: String(repeating: "a", count: 40),
            channel: "tester",
            architecture: "arm64",
            operatingSystem: "macOS 15.5.0"
        )
        let record = QuillCodeDesktopLaunchRecord(
            processIdentifier: 123,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            phase: .ready,
            metadata: previous
        )
        let incident = try XCTUnwrap(
            QuillCodeDesktopUnexpectedExit(
                record: record,
                now: record.startedAt.addingTimeInterval(10)
            )
        )

        let url = try XCTUnwrap(
            QuillCodeDesktopIssueReporter.issueURL(metadata: current, incident: incident)
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try components.queryItems.orEmpty.map { item in
            (item.name, try XCTUnwrap(item.value))
        })
        let body = try XCTUnwrap(query["body"])

        XCTAssertEqual(query["title"], "[Crash] ")
        XCTAssertTrue(body.contains("Ended unexpectedly while the app was running"), body)
        XCTAssertTrue(body.contains("0.1.0 (697)"), body)
        XCTAssertTrue(body.contains(previous.commit), body)
        for forbidden in ["/Users/", "transcript", "API key:", "project path", "123"] {
            XCTAssertFalse(body.contains(forbidden), body)
        }
    }
}

private extension Optional where Wrapped == [URLQueryItem] {
    var orEmpty: [URLQueryItem] { self ?? [] }
}
