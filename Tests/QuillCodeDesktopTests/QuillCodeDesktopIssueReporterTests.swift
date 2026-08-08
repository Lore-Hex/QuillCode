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
}

private extension Optional where Wrapped == [URLQueryItem] {
    var orEmpty: [URLQueryItem] { self ?? [] }
}
