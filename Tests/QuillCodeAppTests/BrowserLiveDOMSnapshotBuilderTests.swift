import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class BrowserLiveDOMSnapshotBuilderTests: XCTestCase {
    func testLiveDOMSnapshotPrefersRenderedOutlineAndVisibleText() throws {
        let originalURL = try XCTUnwrap(URL(string: "http://localhost:5173"))
        let finalURL = try XCTUnwrap(URL(string: "http://localhost:5173/dashboard"))
        let capture = BrowserLiveDOMSnapshot(
            finalURL: finalURL,
            title: "Rendered Dashboard",
            visibleText: "  Dashboard\nReady now  ",
            outline: ["H1: Rendered Dashboard", "Button: Start"],
            html: "<html><head><title>Source Title</title></head><body><h1>Source Heading</h1></body></html>",
            viewportDescription: "390x844 @3x"
        )

        let snapshot = BrowserLiveDOMSnapshotBuilder.snapshot(
            capture,
            originalURL: originalURL,
            sourceLabel: "Local web app"
        )

        XCTAssertEqual(snapshot.sourceLabel, "Local web app")
        XCTAssertEqual(snapshot.inspectionDepth, .liveDOMSnapshot)
        XCTAssertEqual(snapshot.summary, "Captured a live DOM snapshot from the rendered browser session.")
        XCTAssertTrue(snapshot.details.contains("Final URL: http://localhost:5173/dashboard"))
        XCTAssertTrue(snapshot.details.contains("Title: Rendered Dashboard"))
        XCTAssertTrue(snapshot.details.contains("Viewport: 390x844 @3x"))
        XCTAssertEqual(snapshot.outline, ["H1: Rendered Dashboard", "Button: Start"])
        XCTAssertEqual(snapshot.textSnippet, "Dashboard Ready now")
    }

    func testLiveDOMSnapshotWorksWithoutHTMLSource() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/app"))
        let capture = BrowserLiveDOMSnapshot(
            finalURL: url,
            title: "Rendered App",
            visibleText: "Rendered copy",
            outline: ["Main landmark"]
        )

        let snapshot = BrowserLiveDOMSnapshotBuilder.snapshot(
            capture,
            originalURL: url,
            sourceLabel: "Web page"
        )

        XCTAssertEqual(snapshot.inspectionDepth, .liveDOMSnapshot)
        XCTAssertEqual(snapshot.details, [
            "Host: example.com",
            "Scheme: HTTPS",
            "Path: /app",
            "Title: Rendered App"
        ])
        XCTAssertEqual(snapshot.outline, ["Main landmark"])
        XCTAssertEqual(snapshot.textSnippet, "Rendered copy")
    }

    func testLiveDOMCaptureBoundsPageControlledPayloadBeforeStorage() throws {
        let oversizedURL = try XCTUnwrap(URL(string: "https://example.com/?q=" + String(
            repeating: "u",
            count: BrowserLiveDOMSnapshot.maximumURLCharacters + 20
        )))
        let capture = BrowserLiveDOMSnapshot(
            finalURL: oversizedURL,
            title: String(repeating: "t", count: BrowserLiveDOMSnapshot.maximumTitleCharacters + 20),
            visibleText: String(
                repeating: "v",
                count: BrowserLiveDOMSnapshot.maximumVisibleTextCharacters + 20
            ),
            outline: (0..<(BrowserLiveDOMSnapshot.maximumOutlineCount + 5)).map { index in
                "\(index)-" + String(
                    repeating: "o",
                    count: BrowserLiveDOMSnapshot.maximumOutlineCharacters + 20
                )
            },
            html: String(repeating: "h", count: BrowserLiveDOMSnapshot.maximumHTMLCharacters + 20),
            viewportDescription: String(
                repeating: "p",
                count: BrowserLiveDOMSnapshot.maximumViewportCharacters + 20
            )
        )

        XCTAssertEqual(capture.finalURL.absoluteString.count, BrowserLiveDOMSnapshot.maximumURLCharacters)
        XCTAssertEqual(capture.title?.count, BrowserLiveDOMSnapshot.maximumTitleCharacters)
        XCTAssertEqual(capture.visibleText?.count, BrowserLiveDOMSnapshot.maximumVisibleTextCharacters)
        XCTAssertEqual(capture.outline.count, BrowserLiveDOMSnapshot.maximumOutlineCount)
        XCTAssertTrue(capture.outline.allSatisfy {
            $0.count == BrowserLiveDOMSnapshot.maximumOutlineCharacters
        })
        XCTAssertEqual(capture.html?.count, BrowserLiveDOMSnapshot.maximumHTMLCharacters)
        XCTAssertEqual(
            capture.viewportDescription?.count,
            BrowserLiveDOMSnapshot.maximumViewportCharacters
        )
    }
}
