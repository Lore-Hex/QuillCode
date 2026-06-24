import XCTest
import QuillCodeCore
@testable import QuillCodeApp

private struct FakeBrowserPageFetcher: BrowserPageFetching {
    var result: Result<BrowserFetchedPage, BrowserPageFetchFailure>

    func fetchHTML(from url: URL) async throws -> BrowserFetchedPage {
        try result.get()
    }
}

@MainActor
final class WorkspaceBrowserIntegrationTests: XCTestCase {
    func testBrowserPreviewNormalizesURLsAndStoresComments() throws {
        let root = try makeTempDirectory()
        let previewFile = root.appendingPathComponent("preview.html")
        try """
        <!doctype html>
        <html>
          <head><title>Preview Page</title><script src="/app.js"></script></head>
          <body>
            <h1>Hero Preview</h1>
            <a href="/next">Next</a>
            <button>Buy now</button>
            <img src="/hero.png" alt="">
            <form><input name="email"></form>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("toggle-browser", workspaceRoot: root))
        XCTAssertTrue(model.browser.isVisible)

        XCTAssertTrue(model.openBrowserPreview("localhost:3000", workspaceRoot: root))
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(model.browser.title, "localhost")
        XCTAssertEqual(model.browser.status, "Preview ready")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Local web app")
        XCTAssertEqual(model.browser.snapshot?.inspectionDepth, .metadataOnly)
        XCTAssertEqual(
            model.browser.snapshot?.summary,
            "Live DOM capture is not attached yet; QuillCode has URL metadata for this local page."
        )
        XCTAssertEqual(model.browser.snapshot?.details, [
            "Host: localhost",
            "Scheme: HTTP",
            "Path: /"
        ])

        XCTAssertTrue(model.openBrowserPreview("preview.html", workspaceRoot: root))
        XCTAssertEqual(model.browser.currentURL, previewFile.standardizedFileURL.resolvingSymlinksInPath().absoluteString)
        XCTAssertEqual(model.browser.title, "Preview Page")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Local HTML")
        XCTAssertEqual(model.browser.snapshot?.inspectionDepth, .staticHTMLSnapshot)
        XCTAssertEqual(model.browser.snapshot?.summary, "HTML snapshot captured for browser review.")
        XCTAssertEqual(model.browser.snapshot?.details.filter { $0 == "Title: Preview Page" }.count, 1)
        XCTAssertEqual(model.browser.snapshot?.details.filter { $0 == "Heading: Hero Preview" }.count, 1)
        XCTAssertEqual(model.browser.snapshot.map { Array($0.details.suffix(4)) }, [
            "Links: 1",
            "Scripts: 1",
            "Images: 1",
            "Forms: 1"
        ])
        XCTAssertTrue(model.browser.snapshot?.outline.contains("H1: Hero Preview") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Link: Next -> /next") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Button: Buy now") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Input: email") == true)
        XCTAssertTrue(model.browser.snapshot?.textSnippet?.contains("Hero Preview Next Buy now") == true)

        XCTAssertTrue(model.addBrowserComment("Check the hero spacing"))
        XCTAssertEqual(model.browser.comments.count, 1)
        XCTAssertEqual(model.browser.comments[0].text, "Check the hero spacing")
        XCTAssertEqual(model.browser.comments[0].url, model.browser.currentURL)

        let inspectionResult = model.runToolCall(
            ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"),
            workspaceRoot: root
        )
        XCTAssertTrue(inspectionResult.ok)
        let inspection = try JSONHelpers.decode(BrowserInspectionToolOutput.self, from: inspectionResult.stdout)
        XCTAssertEqual(inspection.title, "Preview Page")
        XCTAssertEqual(inspection.sourceLabel, "Local HTML")
        XCTAssertEqual(inspection.inspectionDepth, .staticHTMLSnapshot)
        XCTAssertTrue(inspection.outline.contains("H1: Hero Preview"))
        XCTAssertEqual(inspection.comments.map(\.text), ["Check the hero spacing"])

        XCTAssertFalse(model.openBrowserPreview("not-a-valid-target", workspaceRoot: root))
        XCTAssertEqual(model.browser.status, "Invalid address")
        XCTAssertEqual(model.lastError, "Enter an http, https, file, localhost, or project file URL.")
    }

    func testBrowserPreviewSupportsHistoryNavigationAndReload() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.openBrowserPreview("localhost:3000"))
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertFalse(model.browser.canGoBack)
        XCTAssertFalse(model.browser.canGoForward)
        XCTAssertTrue(model.browser.canReload)

        XCTAssertTrue(model.openBrowserPreview("localhost:5173/dashboard"))
        XCTAssertEqual(model.browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(model.browser.history, [
            "http://localhost:3000",
            "http://localhost:5173/dashboard"
        ])
        XCTAssertEqual(model.browser.historyIndex, 1)
        XCTAssertTrue(model.browser.canGoBack)
        XCTAssertFalse(model.browser.canGoForward)

        XCTAssertTrue(model.goBackInBrowser())
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(model.browser.historyIndex, 0)
        XCTAssertFalse(model.browser.canGoBack)
        XCTAssertTrue(model.browser.canGoForward)

        XCTAssertTrue(model.reloadBrowserPreview())
        XCTAssertEqual(model.browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(model.browser.status, "Reloaded")
        XCTAssertEqual(model.browser.history, [
            "http://localhost:3000",
            "http://localhost:5173/dashboard"
        ])
        XCTAssertEqual(model.browser.historyIndex, 0)

        XCTAssertTrue(model.openBrowserPreview("example.com"))
        XCTAssertEqual(model.browser.currentURL, "https://example.com")
        XCTAssertEqual(model.browser.history, [
            "http://localhost:3000",
            "https://example.com"
        ])
        XCTAssertEqual(model.browser.historyIndex, 1)
        XCTAssertFalse(model.browser.canGoForward)
    }

    func testBrowserPreviewFetchesReachableHTMLSnapshot() async throws {
        let model = QuillCodeWorkspaceModel()
        let html = """
        <!doctype html>
        <html>
          <head><title>Running App</title></head>
          <body>
            <h1>Dashboard</h1>
            <a href="/settings">Settings</a>
            <button>Launch</button>
            <form aria-label="Search"><input placeholder="Find files"></form>
          </body>
        </html>
        """
        let fetchedURL = try XCTUnwrap(URL(string: "http://localhost:5173/dashboard"))
        let fetcher = FakeBrowserPageFetcher(result: .success(BrowserFetchedPage(
            finalURL: fetchedURL,
            statusCode: 200,
            contentType: "text/html; charset=utf-8",
            html: html,
            byteCount: 512,
            wasTruncated: false
        )))

        let didOpen = await model.openBrowserPreview("localhost:5173", pageFetcher: fetcher)
        XCTAssertTrue(didOpen)

        XCTAssertEqual(model.browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(model.browser.addressDraft, "http://localhost:5173/dashboard")
        XCTAssertEqual(model.browser.title, "Running App")
        XCTAssertEqual(model.browser.status, "Preview ready")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Local web app")
        XCTAssertEqual(model.browser.snapshot?.inspectionDepth, .staticHTMLSnapshot)
        XCTAssertEqual(model.browser.snapshot?.summary, "Fetched an HTML snapshot for this local page.")
        XCTAssertTrue(model.browser.snapshot?.details.contains("HTTP: 200") == true)
        XCTAssertTrue(model.browser.snapshot?.details.contains("Content-Type: text/html; charset=utf-8") == true)
        XCTAssertTrue(model.browser.snapshot?.details.contains("Size: 512 bytes") == true)
        XCTAssertTrue(model.browser.snapshot?.details.contains("Title: Running App") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("H1: Dashboard") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Link: Settings -> /settings") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Button: Launch") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Input: Find files") == true)
        XCTAssertTrue(model.browser.snapshot?.outline.contains("Form: Search") == true)
        XCTAssertTrue(model.browser.snapshot?.textSnippet?.contains("Dashboard Settings Launch") == true)
    }

    func testBrowserPreviewKeepsMetadataSnapshotWhenHTMLFetchFails() async throws {
        let model = QuillCodeWorkspaceModel()
        let fetcher = FakeBrowserPageFetcher(result: .failure(.httpStatus(503)))

        let didOpen = await model.openBrowserPreview("example.com", pageFetcher: fetcher)
        XCTAssertTrue(didOpen)

        XCTAssertEqual(model.browser.currentURL, "https://example.com")
        XCTAssertEqual(model.browser.title, "example.com")
        XCTAssertEqual(model.browser.status, "Preview ready")
        XCTAssertEqual(model.browser.snapshot?.sourceLabel, "Web page")
        XCTAssertEqual(model.browser.snapshot?.inspectionDepth, .metadataOnly)
        XCTAssertTrue(model.browser.snapshot?.details.contains("Snapshot fetch: The page returned HTTP 503.") == true)
        XCTAssertNil(model.lastError)
    }

    func testComposerCanInspectCurrentBrowserPage() async throws {
        let root = try makeTempDirectory()
        let previewFile = root.appendingPathComponent("preview.html")
        try """
        <!doctype html>
        <html>
          <head><title>Browser Agent</title></head>
          <body>
            <h1>Agent Preview</h1>
            <p>Visible copy.</p>
          </body>
        </html>
        """.write(to: previewFile, atomically: true, encoding: .utf8)
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.openBrowserPreview("preview.html", workspaceRoot: root))
        model.setDraft("inspect browser page")
        await model.submitComposer(workspaceRoot: root)

        let thread = try XCTUnwrap(model.selectedThread)
        XCTAssertTrue(thread.events.contains { $0.summary.contains(ToolDefinition.browserInspect.name) })
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.browserInspect.name)
        XCTAssertEqual(model.currentToolCards.last?.status, .done)
        XCTAssertTrue(thread.messages.last?.content.contains("Inspected `Browser Agent`") == true)
        XCTAssertTrue(thread.messages.last?.content.contains("H1: Agent Preview") == true)
        XCTAssertTrue(thread.messages.last?.content.contains("Visible copy.") == true)
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeAppTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
