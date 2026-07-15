import CQuillPlatform
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuillCodePlatform
import XCTest

final class LoopbackHTTPCallbackServerTests: XCTestCase {
    func testCreatesListenerForExactConfiguredCallbackURL() throws {
        let reservedURL: URL
        do {
            let reservation = try LoopbackHTTPCallbackServer(callbackPath: "/registered/callback")
            reservedURL = reservation.callbackURL
            reservation.cancel()
        }

        let server = try LoopbackHTTPCallbackServer(callbackURL: reservedURL)
        XCTAssertEqual(server.callbackURL, reservedURL)
    }

    func testCapturesMatchingCallbackAndReturnsSuccessPage() async throws {
        let server = try LoopbackHTTPCallbackServer(callbackPath: "/oauth/callback")
        let wait = Task { try await server.waitForCallback() }
        let callback = try XCTUnwrap(URL(string: "?code=abc&state=expected", relativeTo: server.callbackURL))

        let (data, response) = try await URLSession.shared.data(from: callback)
        let captured = try await wait.value

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("sign-in is complete"))
        XCTAssertEqual(captured.path, "/oauth/callback")
        XCTAssertEqual(captured.query, "code=abc&state=expected")
        XCTAssertEqual(captured.port, server.callbackURL.port)
    }

    func testIgnoresUnrelatedRequestBeforeCapturingCallback() async throws {
        let server = try LoopbackHTTPCallbackServer(callbackPath: "/callback")
        let wait = Task { try await server.waitForCallback() }
        let unrelated = try XCTUnwrap(URL(string: "/favicon.ico", relativeTo: server.callbackURL))

        let (_, unrelatedResponse) = try await URLSession.shared.data(from: unrelated)
        XCTAssertEqual((unrelatedResponse as? HTTPURLResponse)?.statusCode, 404)

        let callback = try XCTUnwrap(URL(string: "?code=done", relativeTo: server.callbackURL))
        _ = try await URLSession.shared.data(from: callback)
        let captured = try await wait.value
        XCTAssertEqual(captured.query, "code=done")
    }

    func testIgnoresMalformedRequestBeforeCapturingCallback() async throws {
        let server = try LoopbackHTTPCallbackServer(callbackPath: "/callback")
        let wait = Task { try await server.waitForCallback() }
        var malformedRequest = URLRequest(url: server.callbackURL)
        malformedRequest.httpMethod = "POST"

        let (_, malformedResponse) = try await URLSession.shared.data(for: malformedRequest)
        XCTAssertEqual((malformedResponse as? HTTPURLResponse)?.statusCode, 400)

        let callback = try XCTUnwrap(URL(string: "?code=done", relativeTo: server.callbackURL))
        _ = try await URLSession.shared.data(from: callback)
        let captured = try await wait.value
        XCTAssertEqual(captured.query, "code=done")
    }

    func testPartialRequestCannotHoldListenerOpenIndefinitely() async throws {
        let server = try LoopbackHTTPCallbackServer(
            port: 0,
            callbackPath: "/callback",
            requestReceiveAttemptLimit: 2
        )
        let wait = Task { try await server.waitForCallback() }
        let rawPort = try XCTUnwrap(server.callbackURL.port)
        let port = try XCTUnwrap(UInt16(exactly: rawPort))
        let stalledDescriptor = cquill_loopback_connect(port)
        XCTAssertGreaterThanOrEqual(stalledDescriptor, 0)
        defer {
            _ = cquill_descriptor_close(stalledDescriptor)
            server.cancel()
            wait.cancel()
        }

        let partialRequest = Data("GET /callback HTTP/1.1\r\nHost: localhost".utf8)
        let sendResult = partialRequest.withUnsafeBytes { bytes in
            cquill_socket_send_all(
                stalledDescriptor,
                bytes.baseAddress,
                bytes.count
            )
        }
        XCTAssertEqual(sendResult, 0)
        try await Task.sleep(for: .milliseconds(250))

        let callback = try XCTUnwrap(URL(string: "?code=recovered", relativeTo: server.callbackURL))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        let (_, response) = try await URLSession(configuration: configuration).data(from: callback)
        let captured = try await wait.value

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(captured.query, "code=recovered")
    }

    func testCancellationEndsPendingWait() async throws {
        let server = try LoopbackHTTPCallbackServer()
        let wait = Task { try await server.waitForCallback() }
        try await Task.sleep(for: .milliseconds(20))
        server.cancel()

        do {
            _ = try await wait.value
            XCTFail("Expected cancellation")
        } catch let error as LoopbackHTTPCallbackError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testRejectsUnsafeCallbackPaths() {
        XCTAssertThrowsError(try LoopbackHTTPCallbackServer(callbackPath: "/callback?bad=1"))
        XCTAssertThrowsError(try LoopbackHTTPCallbackServer(callbackPath: "#fragment"))
    }

    func testRejectsCallbackURLsThatAreNotExactLocalhostHTTPRedirects() throws {
        let invalidValues = [
            "https://localhost:3000/callback",
            "http://127.0.0.1:3000/callback",
            "http://localhost/callback",
            "http://user@localhost:3000/callback",
            "http://localhost:3000/callback?state=caller-owned",
            "http://localhost:3000/callback#fragment",
            "http://localhost:3000/"
        ]

        for value in invalidValues {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertThrowsError(
                try LoopbackHTTPCallbackServer(callbackURL: url),
                "Expected to reject \(value)"
            ) { error in
                guard let callbackError = error as? LoopbackHTTPCallbackError,
                      case .invalidCallbackURL = callbackError
                else {
                    return XCTFail("Unexpected error for \(value): \(error)")
                }
            }
        }
    }
}
