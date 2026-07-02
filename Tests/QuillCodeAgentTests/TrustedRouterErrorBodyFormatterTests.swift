import XCTest
@testable import QuillCodeAgent

final class TrustedRouterErrorBodyFormatterTests: XCTestCase {
    func testAuthFailureCarriesSignInHint() {
        let message = TrustedRouterErrorBodyFormatter.streamingMessage(statusCode: 401, body: "unauthorized")
        XCTAssertTrue(message.contains("HTTP 401"), message)
        XCTAssertTrue(message.contains("unauthorized"), message)
        XCTAssertTrue(message.contains("Sign in again"), message)
    }

    func testForbiddenCarriesPermissionHint() {
        let message = TrustedRouterErrorBodyFormatter.streamingMessage(statusCode: 403, body: "")
        XCTAssertTrue(message.contains("HTTP 403"), message)
        XCTAssertTrue(message.contains("Permission denied"), message)
    }

    func testOtherStatusesStayUnhinted() {
        // 401/403 need opposite responses; everything else keeps the plain message (429/5xx already
        // have the self-healing retry path).
        for code in [400, 404, 429, 500, 503] {
            let message = TrustedRouterErrorBodyFormatter.streamingMessage(statusCode: code, body: "x")
            XCTAssertEqual(message, "TrustedRouter streaming request failed with HTTP \(code): x")
        }
    }

    func testEmptyBodyStillFormats() {
        XCTAssertEqual(
            TrustedRouterErrorBodyFormatter.streamingMessage(statusCode: 500, body: " \n"),
            "TrustedRouter streaming request failed with HTTP 500."
        )
    }

    func testBodyIsSingleLineAndBounded() {
        let body = "first line\nsecond\tline " + String(repeating: "x", count: 1_200)
        let message = TrustedRouterErrorBodyFormatter.streamingMessage(statusCode: 400, body: body)

        XCTAssertFalse(message.contains("\n"), message)
        XCTAssertTrue(message.contains("first line second line"), message)
        XCTAssertLessThan(message.count, 1_100)
        XCTAssertTrue(message.hasSuffix("..."), message)
    }
}
