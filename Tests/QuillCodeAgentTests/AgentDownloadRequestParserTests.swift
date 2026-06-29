import XCTest
@testable import QuillCodeAgent

final class AgentDownloadRequestParserTests: XCTestCase {
    func testDomainDownloadBuildsWorkspaceBoundedCurlCommand() {
        XCTAssertEqual(
            AgentDownloadRequestParser.shellCommand(from: "Can you download LinkedIn.com?"),
            "mkdir -p 'downloads' && curl -L --fail --silent --show-error --output 'downloads/linkedin.com.html' 'https://LinkedIn.com' && ls -lh 'downloads/linkedin.com.html'"
        )
    }

    func testURLDownloadIntoExplicitRelativePathKeepsRequestedPath() {
        XCTAssertEqual(
            AgentDownloadRequestParser.shellCommand(
                from: "Download https://example.com/report.pdf into `downloads/reports/latest.pdf`"
            ),
            "mkdir -p 'downloads/reports' && curl -L --fail --silent --show-error --output 'downloads/reports/latest.pdf' 'https://example.com/report.pdf' && ls -lh 'downloads/reports/latest.pdf'"
        )
    }

    func testUnsafeExplicitPathFallsBackToWorkspaceDownloadsFolder() {
        let command = AgentDownloadRequestParser.shellCommand(from: "Fetch https://example.com to `/tmp/example.html`")

        XCTAssertEqual(
            command,
            "mkdir -p 'downloads' && curl -L --fail --silent --show-error --output 'downloads/example.com.html' 'https://example.com' && ls -lh 'downloads/example.com.html'"
        )
        XCTAssertFalse(command?.contains("/tmp/example.html") == true)
    }

    func testNonDownloadRequestDoesNotPlanShellCommand() {
        XCTAssertNil(AgentDownloadRequestParser.shellCommand(from: "Open https://example.com in the browser"))
    }
}
