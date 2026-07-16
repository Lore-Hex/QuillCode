import XCTest
@testable import QuillCodeAgent
import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TrustedRouterCreditsClientTests: XCTestCase {
    override func tearDown() {
        CreditsURLProtocol.reset()
        super.tearDown()
    }

    func testFetchUsesAuthenticatedCreditsEndpointAndDecodesBalance() async throws {
        CreditsURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.trustedrouter.test/v1/credits")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-secret")
            return Self.response(
                request: request,
                statusCode: 200,
                body: #"{"balance":12.5,"currency":"usd"}"#
            )
        }
        let fetchedAt = Date(timeIntervalSince1970: 200)

        let snapshot = try await TrustedRouterCreditsClient(
            apiKey: " sk-test-secret ",
            baseURL: "https://api.trustedrouter.test/v1",
            urlSession: CreditsURLProtocol.session()
        ).fetch(fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.balance, 12.5)
        XCTAssertEqual(snapshot.currency, "USD")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testMissingKeyAndInvalidBalanceFailClosed() async {
        do {
            _ = try await TrustedRouterCreditsClient(apiKey: " \n").fetch()
            XCTFail("Expected a missing-key error")
        } catch {
            XCTAssertEqual(
                TrustedRouterCreditsClient.userFacingFailure(for: error),
                "TrustedRouter sign-in is required to load account credits."
            )
        }

        CreditsURLProtocol.handler = { request in
            Self.response(request: request, statusCode: 200, body: #"{"balance":1e999,"currency":"USD"}"#)
        }
        do {
            _ = try await TrustedRouterCreditsClient(
                apiKey: "sk-test",
                baseURL: "https://api.trustedrouter.test/v1",
                urlSession: CreditsURLProtocol.session()
            ).fetch()
            XCTFail("Expected an invalid response")
        } catch {
            XCTAssertEqual(
                TrustedRouterCreditsClient.userFacingFailure(for: error),
                "TrustedRouter account credits could not be refreshed."
            )
        }
    }

    func testAuthenticationFailureMessageDoesNotExposeProviderPayloadOrKey() async {
        CreditsURLProtocol.handler = { request in
            Self.response(
                request: request,
                statusCode: 401,
                body: #"{"error":{"message":"rejected sk-test-secret internal-account-7"}}"#
            )
        }

        do {
            _ = try await TrustedRouterCreditsClient(
                apiKey: "sk-test-secret",
                baseURL: "https://api.trustedrouter.test/v1",
                urlSession: CreditsURLProtocol.session()
            ).fetch()
            XCTFail("Expected authentication failure")
        } catch {
            let message = TrustedRouterCreditsClient.userFacingFailure(for: error)
            XCTAssertEqual(message, "TrustedRouter rejected the saved account credentials.")
            XCTAssertFalse(message.contains("sk-test-secret"))
            XCTAssertFalse(message.contains("internal-account-7"))
        }
    }

    func testRateLimitMessageBoundsProviderRetryValue() {
        let bounded = TrustedRouterError.rateLimit(
            statusCode: 429,
            message: "provider detail",
            payload: nil,
            retryAfterSeconds: 90.2
        )
        XCTAssertEqual(
            TrustedRouterCreditsClient.userFacingFailure(for: bounded),
            "TrustedRouter rate-limited the account balance refresh; retry in 91s."
        )

        let extreme = TrustedRouterError.rateLimit(
            statusCode: 429,
            message: "provider detail",
            payload: nil,
            retryAfterSeconds: .greatestFiniteMagnitude
        )
        XCTAssertEqual(
            TrustedRouterCreditsClient.userFacingFailure(for: extreme),
            "TrustedRouter rate-limited the account balance refresh."
        )
    }

    private static func response(
        request: URLRequest,
        statusCode: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(body.utf8)
        )
    }
}

private final class CreditsURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CreditsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
