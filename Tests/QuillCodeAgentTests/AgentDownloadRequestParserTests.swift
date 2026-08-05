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

extension AgentDownloadRequestParserTests {
    /// Live desktop failure: "Pull the transaction tables … Save it as transactions.csv" opened the
    /// run with `curl -L --fail … --output 'transactions.csv' 'https://transactions.csv'`, which
    /// died on "Could not resolve host". A bare local filename is an OUTPUT, never a fetch source.
    func testSaveAsLocalFilenameIsNotADownload() {
        XCTAssertNil(AgentDownloadRequestParser.shellCommand(
            from: "Pull the transaction tables out of these three bank statement PDFs into one clean CSV with date, description, and amount. Save it as transactions.csv"
        ))
        XCTAssertNil(AgentDownloadRequestParser.shellCommand(from: "Save it as report.md"))
        XCTAssertNil(AgentDownloadRequestParser.shellCommand(from: "save the summary as deck.pptx"))
        XCTAssertNil(AgentDownloadRequestParser.shellCommand(from: "fetch the numbers and save them as q3.xlsx"))
    }

    /// The real download paths must keep working.
    func testGenuineDownloadsStillParse() {
        let bareHost = AgentDownloadRequestParser.shellCommand(from: "download example.com/data.csv")
        XCTAssertNotNil(bareHost)
        XCTAssertEqual(bareHost?.contains("https://example.com/data.csv"), true)

        let explicit = AgentDownloadRequestParser.shellCommand(
            from: "save https://example.com/report.pdf as downloads/report.pdf"
        )
        XCTAssertNotNil(explicit)
        XCTAssertEqual(explicit?.contains("https://example.com/report.pdf"), true)
    }
}
