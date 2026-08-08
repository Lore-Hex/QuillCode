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

    func testFetchUsesAuthenticatedCurrentKeyEndpointAndDecodesLimits() async throws {
        CreditsURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.trustedrouter.test/v1/key")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-secret")
            return Self.response(request: request, statusCode: 200, body: Self.keyUsageBody)
        }
        let fetchedAt = Date(timeIntervalSince1970: 200)

        let snapshot = try await TrustedRouterCreditsClient(
            apiKey: " sk-test-secret ",
            baseURL: "https://api.trustedrouter.test/v1",
            urlSession: CreditsURLProtocol.session()
        ).fetch(fetchedAt: fetchedAt)

        XCTAssertEqual(snapshot.lifetime.usage, 86.090316)
        XCTAssertNil(snapshot.lifetime.limit)
        XCTAssertEqual(snapshot.daily.usage, 1.25)
        XCTAssertEqual(snapshot.daily.limit, 40)
        XCTAssertEqual(snapshot.daily.remaining, 38.75)
        XCTAssertEqual(snapshot.weekly.remaining, 197.356056)
        XCTAssertEqual(snapshot.monthly.limit, 800)
        XCTAssertEqual(snapshot.currency, "USD")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertFalse(snapshot.budgetAlertOnly)
        XCTAssertNotNil(snapshot.daily.resetsAt)
    }

    func testDefaultInferenceBaseRoutesCurrentKeyMetadataToControlHost() async throws {
        CreditsURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://trustedrouter.com/v1/key")
            return Self.response(request: request, statusCode: 200, body: Self.keyUsageBody)
        }

        _ = try await TrustedRouterCreditsClient(
            apiKey: "sk-test",
            urlSession: CreditsURLProtocol.session()
        ).fetch()
    }

    func testMissingKeyAndInvalidUsageFailClosed() async {
        do {
            _ = try await TrustedRouterCreditsClient(apiKey: " \n").fetch()
            XCTFail("Expected a missing-key error")
        } catch {
            XCTAssertEqual(
                TrustedRouterCreditsClient.userFacingFailure(for: error),
                "TrustedRouter sign-in is required to load key usage and limits."
            )
        }

        CreditsURLProtocol.handler = { request in
            Self.response(
                request: request,
                statusCode: 200,
                body: Self.keyUsageBody.replacingOccurrences(
                    of: "\"usage\":86.090316",
                    with: "\"usage\":-1"
                )
            )
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
                "TrustedRouter returned invalid key usage or limits."
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
            "TrustedRouter rate-limited the key usage refresh; retry in 91s."
        )

        let extreme = TrustedRouterError.rateLimit(
            statusCode: 429,
            message: "provider detail",
            payload: nil,
            retryAfterSeconds: .greatestFiniteMagnitude
        )
        XCTAssertEqual(
            TrustedRouterCreditsClient.userFacingFailure(for: extreme),
            "TrustedRouter rate-limited the key usage refresh."
        )
    }

    private static let keyUsageBody = #"""
    {"data":{
      "usage":86.090316,
      "limit":null,
      "limit_remaining":null,
      "usage_daily":1.25,
      "limit_daily":40.0,
      "limit_daily_remaining":38.75,
      "limit_daily_resets_at":"2026-08-09T00:00:00Z",
      "usage_weekly":2.643944,
      "limit_weekly":200.0,
      "limit_weekly_remaining":197.356056,
      "limit_weekly_resets_at":"2026-08-10T00:00:00Z",
      "usage_monthly":2.643944,
      "limit_monthly":800.0,
      "limit_monthly_remaining":797.356056,
      "limit_monthly_resets_at":"2026-09-01T00:00:00Z",
      "budget_alert_only":false
    }}
    """#

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
