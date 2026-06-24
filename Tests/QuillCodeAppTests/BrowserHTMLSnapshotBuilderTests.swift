import XCTest
@testable import QuillCodeApp

final class BrowserHTMLSnapshotBuilderTests: XCTestCase {
    func testSnapshotExtractsDetailsOutlineAndReadableText() {
        let html = """
        <!doctype html>
        <html>
          <head>
            <title>Kitchen &amp; Docs</title>
            <script>window.secret = "ignored"</script>
          </head>
          <body>
            <h1>Overview</h1>
            <p>Welcome &amp; continue.</p>
            <a href="/docs">Docs</a>
            <button>Save</button>
            <form aria-label="Search form"><input placeholder="Find docs"></form>
            <img src="/hero.png" alt="Hero">
            <style>.hidden { display: none }</style>
          </body>
        </html>
        """

        let snapshot = BrowserHTMLSnapshotBuilder.snapshot(
            sourceLabel: "Local HTML",
            summary: "Captured.",
            details: ["File: index.html"],
            html: html
        )

        XCTAssertEqual(snapshot.sourceLabel, "Local HTML")
        XCTAssertEqual(snapshot.inspectionDepth, .staticHTMLSnapshot)
        XCTAssertEqual(snapshot.summary, "Captured.")
        XCTAssertEqual(snapshot.details, [
            "File: index.html",
            "Title: Kitchen & Docs",
            "Heading: Overview",
            "Links: 1",
            "Scripts: 1",
            "Images: 1",
            "Forms: 1"
        ])
        XCTAssertEqual(snapshot.outline, [
            "H1: Overview",
            "Link: Docs -> /docs",
            "Button: Save",
            "Form: Search form",
            "Input: Find docs",
            "Image: Hero"
        ])
        XCTAssertEqual(snapshot.textSnippet, "Overview Welcome & continue. Docs Save")
    }

    func testSnapshotCanRepresentNetworkHTMLDepth() {
        let snapshot = BrowserHTMLSnapshotBuilder.snapshot(
            sourceLabel: "Local web app",
            summary: "Fetched.",
            details: ["HTTP: 200"],
            html: "<html><head><title>Running App</title></head><body><h1>Dashboard</h1></body></html>",
            inspectionDepth: .networkHTMLSnapshot
        )

        XCTAssertEqual(snapshot.inspectionDepth, .networkHTMLSnapshot)
        XCTAssertEqual(snapshot.details, [
            "HTTP: 200",
            "Title: Running App",
            "Heading: Dashboard",
            "Links: 0",
            "Scripts: 0",
            "Images: 0",
            "Forms: 0"
        ])
    }

    func testSnapshotFallsBackThroughInputAndImageLabels() {
        let html = """
        <h2>Controls</h2>
        <form id="login"><input name="email"><input type="password"></form>
        <img src="/fallback.png">
        <a href="/empty"></a>
        """

        let snapshot = BrowserHTMLSnapshotBuilder.snapshot(
            sourceLabel: "Web page",
            summary: "Captured.",
            details: [],
            html: html
        )

        XCTAssertEqual(snapshot.outline, [
            "H2: Controls",
            "Form: login",
            "Input: email",
            "Input: password",
            "Image: /fallback.png",
            "Link: /empty -> /empty"
        ])
    }

    func testSnapshotLimitsOutlineAndTruncatesSnippet() {
        let headings = (0..<40)
            .map { "<h3>Section \($0)</h3>" }
            .joined()
        let longText = String(repeating: "word ", count: 220)
        let html = "<body>\(headings)<p>\(longText)</p></body>"

        let snapshot = BrowserHTMLSnapshotBuilder.snapshot(
            sourceLabel: "Web page",
            summary: "Captured.",
            details: [],
            html: html
        )

        XCTAssertEqual(snapshot.outline.count, 24)
        XCTAssertEqual(snapshot.outline.first, "H3: Section 0")
        XCTAssertEqual(snapshot.outline.last, "H3: Section 23")
        XCTAssertTrue(snapshot.textSnippet?.hasSuffix("...") == true)
        XCTAssertLessThanOrEqual(snapshot.textSnippet?.count ?? 0, 803)
    }

    func testSnapshotOmitsEmptyTextSnippet() {
        let snapshot = BrowserHTMLSnapshotBuilder.snapshot(
            sourceLabel: "Web page",
            summary: "Captured.",
            details: [],
            html: "<script>console.log('only script')</script><style>body {}</style>"
        )

        XCTAssertNil(snapshot.textSnippet)
    }
}
