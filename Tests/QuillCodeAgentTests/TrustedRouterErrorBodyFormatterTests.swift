import XCTest
@testable import QuillCodeAgent

final class TrustedRouterErrorBodyFormatterTests: XCTestCase {
    func testUnauthorizedIncludesAuthHint() {
        let message = TrustedRouterErrorBodyFormatter.streamingMessage(
            statusCode: 401,
            body: #"{"error":"unauthorized"}"#
        )

        XCTAssertTrue(message.contains("HTTP 401"), message)
        XCTAssertTrue(message.contains("QUILLCODE_API_KEY"), message)
        XCTAssertTrue(message.contains("quill-code auth set-key"), message)
    }

    func testForbiddenIncludesPermissionsHint() {
        let message = TrustedRouterErrorBodyFormatter.streamingMessage(statusCode: 403, body: "forbidden")

        XCTAssertTrue(message.contains("HTTP 403"), message)
        XCTAssertTrue(message.contains("Permission denied"), message)
        XCTAssertTrue(message.contains("plan/permissions"), message)
    }

    func testOtherStatusesKeepPlainMessage() {
        XCTAssertEqual(
            TrustedRouterErrorBodyFormatter.streamingMessage(statusCode: 500, body: "boom"),
            "TrustedRouter streaming request failed with HTTP 500: boom"
        )
        XCTAssertNil(TrustedRouterErrorBodyFormatter.hint(forStatusCode: 500))
    }

    func testEmptyBodyStillGetsHint() {
        let message = TrustedRouterErrorBodyFormatter.streamingMessage(statusCode: 401, body: "  \n")

        XCTAssertTrue(message.hasPrefix("TrustedRouter streaming request failed with HTTP 401."), message)
        XCTAssertTrue(message.contains("quill-code auth set-key"), message)
    }

    func testStreamingHTTPErrorDescriptionCarriesHint() {
        let error = TrustedRouterAgentError.streamingHTTPError(statusCode: 401, body: "unauthorized")

        XCTAssertTrue(String(describing: error).contains("quill-code auth set-key"), String(describing: error))
    }
}
