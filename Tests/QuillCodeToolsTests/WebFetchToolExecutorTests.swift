import XCTest
import QuillCodeCore
@testable import QuillCodeTools

/// Scripted `WebFetchHTTPClient` so executor tests are deterministic and never touch the
/// network: responses are consumed in order, and every request is recorded for inspection.
final class StubWebFetchHTTPClient: WebFetchHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var scriptedResults: [Result<WebFetchHTTPResponse, WebFetchHTTPClientError>]
    private var recordedRequests: [WebFetchHTTPRequest] = []

    init(_ results: [Result<WebFetchHTTPResponse, WebFetchHTTPClientError>]) {
        self.scriptedResults = results
    }

    convenience init(responses: [WebFetchHTTPResponse]) {
        self.init(responses.map { .success($0) })
    }

    var requests: [WebFetchHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    func perform(_ request: WebFetchHTTPRequest) throws -> WebFetchHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(request)
        guard !scriptedResults.isEmpty else {
            throw WebFetchHTTPClientError.transport("unscripted request to \(request.url.absoluteString)")
        }
        return try scriptedResults.removeFirst().get()
    }
}

final class WebFetchToolExecutorTests: XCTestCase {
    private func makeExecutor(
        responses: [WebFetchHTTPResponse],
        maxRedirects: Int = 5,
        outputMaxLines: Int = WebFetchMarkdownCapper.defaultMaxLines,
        outputMaxBytes: Int = WebFetchMarkdownCapper.defaultMaxBytes
    ) -> (WebFetchToolExecutor, StubWebFetchHTTPClient) {
        let client = StubWebFetchHTTPClient(responses: responses)
        let executor = WebFetchToolExecutor(
            client: client,
            maxRedirects: maxRedirects,
            outputMaxLines: outputMaxLines,
            outputMaxBytes: outputMaxBytes
        )
        return (executor, client)
    }

    private func htmlResponse(
        _ html: String,
        statusCode: Int = 200,
        contentType: String = "text/html; charset=utf-8",
        extraHeaders: [String: String] = [:]
    ) -> WebFetchHTTPResponse {
        var headers = ["content-type": contentType]
        for (name, value) in extraHeaders {
            headers[name.lowercased()] = value
        }
        return WebFetchHTTPResponse(statusCode: statusCode, headerFields: headers, body: Data(html.utf8))
    }

    // MARK: - Happy paths

    func testHTMLIsFetchedAndConverted() {
        let (executor, client) = makeExecutor(responses: [
            htmlResponse("<h1>Docs</h1><p>Welcome to the <a href=\"/guide\">guide</a>.</p>")
        ])
        let result = executor.fetch(urlString: "https://example.com/docs")
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("# Docs"))
        XCTAssertTrue(result.stdout.contains("[guide](https://example.com/guide)"))
        XCTAssertTrue(result.stdout.contains("HTTP 200"))
        XCTAssertTrue(result.stdout.contains("converted to markdown"))
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].url.absoluteString, "https://example.com/docs")
    }

    func testAcceptHeaderNegotiatesTextFormats() {
        let (executor, client) = makeExecutor(responses: [htmlResponse("<p>x</p>")])
        _ = executor.fetch(urlString: "https://example.com/")
        let accept = client.requests[0].headers["Accept"] ?? ""
        XCTAssertTrue(accept.contains("text/html"))
        XCTAssertTrue(accept.contains("text/markdown"))
        XCTAssertTrue(accept.contains("text/plain"))
        XCTAssertTrue(client.requests[0].headers["User-Agent"]?.contains("QuillCode") == true)
    }

    func testMarkdownPassesThroughUnchanged() {
        let markdown = "# Already markdown\n\n- item `code`"
        let (executor, _) = makeExecutor(responses: [
            htmlResponse(markdown, contentType: "text/markdown")
        ])
        let result = executor.fetch(urlString: "https://example.com/README.md")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains(markdown))
        XCTAssertTrue(result.stdout.contains("returned as-is"))
    }

    func testPlainTextPassesThrough() {
        let text = "RFC 9110\n\nHTTP Semantics <not html>"
        let (executor, _) = makeExecutor(responses: [
            htmlResponse(text, contentType: "text/plain; charset=utf-8")
        ])
        let result = executor.fetch(urlString: "https://example.com/rfc.txt")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains(text))
    }

    func testJSONPassesThroughAsText() {
        let (executor, _) = makeExecutor(responses: [
            htmlResponse(#"{"name":"quill"}"#, contentType: "application/json")
        ])
        let result = executor.fetch(urlString: "https://api.example.com/info")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains(#"{"name":"quill"}"#))
    }

    func testSchemelessURLDefaultsToHTTPS() {
        let (executor, client) = makeExecutor(responses: [htmlResponse("<p>x</p>")])
        let result = executor.fetch(urlString: "example.com/docs")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(client.requests[0].url.absoluteString, "https://example.com/docs")
    }

    // MARK: - Content-type refusal and sniffing

    func testBinaryContentTypeIsRefusedWithActionableError() {
        let (executor, _) = makeExecutor(responses: [
            htmlResponse("%PDF-1.4", contentType: "application/pdf")
        ])
        let result = executor.fetch(urlString: "https://example.com/paper.pdf")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("application/pdf") == true)
        XCTAssertTrue(result.error?.contains("curl") == true, "refusal should point at a download path: \(result.error ?? "")")
    }

    func testImageContentTypeIsRefused() {
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "image/png"],
                body: Data([0x89, 0x50, 0x4E, 0x47])
            )
        ])
        let result = executor.fetch(urlString: "https://example.com/img.png")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("image/png") == true)
    }

    func testMissingContentTypeSniffsHTML() {
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(statusCode: 200, body: Data("<!DOCTYPE html><h1>Sniffed</h1>".utf8))
        ])
        let result = executor.fetch(urlString: "https://example.com/")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("# Sniffed"))
    }

    func testMissingContentTypeWithBinaryBodyIsRefused() {
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(statusCode: 200, body: Data([0x00, 0x01, 0x02, 0xFF, 0x00, 0x10]))
        ])
        let result = executor.fetch(urlString: "https://example.com/mystery")
        XCTAssertFalse(result.ok)
    }

    // MARK: - Charset handling

    func testLatin1CharsetIsDecoded() {
        var body = Data("<p>caf".utf8)
        body.append(0xE9) // é in ISO-8859-1
        body.append(contentsOf: Data("</p>".utf8))
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "text/html; charset=iso-8859-1"],
                body: body
            )
        ])
        let result = executor.fetch(urlString: "https://example.com/")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("café"))
    }

    func testInvalidUTF8IsLossilyReplacedNotFatal() {
        var body = Data("<p>ok ".utf8)
        body.append(contentsOf: [0xFF, 0xFE, 0xFD]) // invalid UTF-8 bytes
        body.append(contentsOf: Data(" end</p>".utf8))
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "text/html; charset=utf-8"],
                body: body
            )
        ])
        let result = executor.fetch(urlString: "https://example.com/")
        XCTAssertTrue(result.ok, "hostile bytes must degrade, not fail: \(result.error ?? "")")
        XCTAssertTrue(result.stdout.contains("ok"))
        XCTAssertTrue(result.stdout.contains("end"))
    }

    func testMetaCharsetIsSniffedWhenHeaderIsSilent() {
        var body = Data("<html><head><meta charset=\"windows-1252\"></head><body><p>".utf8)
        body.append(0x93) // “ in windows-1252
        body.append(contentsOf: Data("quoted</p></body></html>".utf8))
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "text/html"],
                body: body
            )
        ])
        let result = executor.fetch(urlString: "https://example.com/")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("\u{201C}quoted"))
    }

    // MARK: - SSRF gate

    func testInternalInitialURLsAreBlockedWithoutAnyRequest() {
        let blockedURLs = [
            "http://localhost:8080/admin",
            "http://127.0.0.1/",
            "http://169.254.169.254/latest/meta-data/",
            "http://[::1]:6379/",
            "http://10.0.0.5/router",
            "http://metadata.google.internal/computeMetadata/v1/",
            "ftp://example.com/file",
            "http://user:pass@example.com/"
        ]
        for urlString in blockedURLs {
            let (executor, client) = makeExecutor(responses: [htmlResponse("<p>never</p>")])
            let result = executor.fetch(urlString: urlString)
            XCTAssertFalse(result.ok, "\(urlString) must be blocked")
            XCTAssertTrue(client.requests.isEmpty, "\(urlString) must be blocked BEFORE any network I/O")
        }
    }

    func testInvalidURLArgumentIsRejected() {
        let (executor, client) = makeExecutor(responses: [])
        XCTAssertFalse(executor.fetch(urlString: "not a url at all").ok)
        XCTAssertFalse(executor.fetch(urlString: "").ok)
        XCTAssertTrue(client.requests.isEmpty)
    }

    // MARK: - Redirects

    func testRelativeRedirectIsFollowedAndReported() {
        let (executor, client) = makeExecutor(responses: [
            WebFetchHTTPResponse(statusCode: 302, headerFields: ["location": "/moved/here"]),
            htmlResponse("<h1>Landed</h1>")
        ])
        let result = executor.fetch(urlString: "https://example.com/start")
        XCTAssertTrue(result.ok)
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests[1].url.absoluteString, "https://example.com/moved/here")
        XCTAssertTrue(result.stdout.contains("# Landed"))
        XCTAssertTrue(result.stdout.contains("1 redirect"))
    }

    func testRedirectToInternalHostIsBlocked() {
        let (executor, client) = makeExecutor(responses: [
            WebFetchHTTPResponse(
                statusCode: 302,
                headerFields: ["location": "http://169.254.169.254/latest/meta-data/"]
            ),
            htmlResponse("<p>never fetched</p>")
        ])
        let result = executor.fetch(urlString: "https://example.com/innocent")
        XCTAssertFalse(result.ok, "redirect laundering to the metadata endpoint must be blocked")
        XCTAssertEqual(client.requests.count, 1, "the internal hop must never be requested")
        XCTAssertTrue(result.error?.contains("redirect") == true)
        XCTAssertTrue(result.error?.contains("169.254") == true)
    }

    func testRedirectToLocalhostIsBlocked() {
        let (executor, client) = makeExecutor(responses: [
            WebFetchHTTPResponse(statusCode: 301, headerFields: ["location": "https://localhost/internal"])
        ])
        let result = executor.fetch(urlString: "https://example.com/")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testRedirectToFileSchemeIsBlocked() {
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(statusCode: 302, headerFields: ["location": "file:///etc/passwd"])
        ])
        let result = executor.fetch(urlString: "https://example.com/")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("http") == true)
    }

    func testRedirectCountIsCapped() {
        let hops = (0..<10).map { index in
            WebFetchHTTPResponse(
                statusCode: 302,
                headerFields: ["location": "https://example.com/hop/\(index)"]
            )
        }
        let (executor, client) = makeExecutor(responses: hops, maxRedirects: 3)
        let result = executor.fetch(urlString: "https://example.com/start")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("redirect") == true)
        XCTAssertEqual(client.requests.count, 4, "initial request + 3 redirects, then give up")
    }

    func testRedirectWithoutLocationFails() {
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(statusCode: 302)
        ])
        let result = executor.fetch(urlString: "https://example.com/")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Location") == true)
    }

    // MARK: - HTTP errors and Cloudflare retry

    func testNotFoundIsReported() {
        let (executor, _) = makeExecutor(responses: [htmlResponse("gone", statusCode: 404)])
        let result = executor.fetch(urlString: "https://example.com/missing")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("404") == true)
    }

    func testPlain403DoesNotTriggerRetry() {
        let (executor, client) = makeExecutor(responses: [
            htmlResponse("forbidden", statusCode: 403)
        ])
        let result = executor.fetch(urlString: "https://example.com/private")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(client.requests.count, 1, "no Cloudflare markers, no retry")
        XCTAssertTrue(result.error?.contains("host.browser.open") == true)
    }

    func testCloudflare403RetriesOnceWithBrowserHeaders() {
        let (executor, client) = makeExecutor(responses: [
            htmlResponse(
                "blocked", statusCode: 403,
                extraHeaders: ["cf-mitigated": "challenge", "server": "cloudflare"]
            ),
            htmlResponse("<h1>Through</h1>")
        ])
        let result = executor.fetch(urlString: "https://example.com/docs")
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("# Through"))
        XCTAssertEqual(client.requests.count, 2)
        let retryAgent = client.requests[1].headers["User-Agent"] ?? ""
        XCTAssertTrue(retryAgent.contains("Mozilla"), "retry must use a browser-like User-Agent")
        XCTAssertNotEqual(client.requests[0].headers["User-Agent"], client.requests[1].headers["User-Agent"])
    }

    func testPersistentCloudflareBlockSuggestsBrowserPane() {
        let blocked = htmlResponse(
            "denied", statusCode: 403,
            extraHeaders: ["cf-mitigated": "challenge"]
        )
        let (executor, client) = makeExecutor(responses: [blocked, blocked])
        let result = executor.fetch(urlString: "https://example.com/docs")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(client.requests.count, 2, "exactly one retry")
        XCTAssertTrue(result.error?.contains("host.browser.open") == true)
    }

    // MARK: - Size caps and truncation

    func testBodyCapWithNoDataIsAnError() {
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "text/html"],
                body: Data(),
                bodyExceededMaxBytes: true
            )
        ])
        let result = executor.fetch(urlString: "https://example.com/huge")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("cap") == true)
        XCTAssertTrue(result.error?.contains("curl") == true)
    }

    func testBodyCapWithPartialDataReturnsPrefixWithNote() {
        let (executor, _) = makeExecutor(responses: [
            WebFetchHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "text/html"],
                body: Data("<h1>Start</h1><p>partial".utf8),
                bodyExceededMaxBytes: true
            )
        ])
        let result = executor.fetch(urlString: "https://example.com/huge")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("# Start"))
        XCTAssertTrue(result.stdout.contains("cap"), "capped fetch must be flagged: \(result.stdout)")
    }

    func testLongOutputIsTruncatedWithMarker() {
        let paragraphs = (0..<500).map { "<p>Paragraph number \($0) with some text.</p>" }.joined()
        let (executor, _) = makeExecutor(
            responses: [htmlResponse(paragraphs)],
            outputMaxBytes: 2_000
        )
        let result = executor.fetch(urlString: "https://example.com/long")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("content truncated"))
        XCTAssertLessThan(result.stdout.utf8.count, 4_000)
    }

    func testTransportErrorIsSurfaced() {
        let client = StubWebFetchHTTPClient([.failure(.timedOut)])
        let executor = WebFetchToolExecutor(client: client)
        let result = executor.fetch(urlString: "https://example.com/slow")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("timed out") == true)
    }

    func testEmptyPageYieldsPlaceholder() {
        let (executor, _) = makeExecutor(responses: [htmlResponse("<html><body></body></html>")])
        let result = executor.fetch(urlString: "https://example.com/blank")
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("no readable text content"))
    }
}
