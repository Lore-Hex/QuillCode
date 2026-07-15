import XCTest
@testable import QuillCodeAgent

final class TrustedRouterOAuthTests: XCTestCase {
    override func tearDown() {
        OAuthURLProtocol.reset()
        super.tearDown()
    }

    func testPKCEChallengeMatchesRFC7636Example() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(
            TrustedRouterPKCEChallenge.s256Challenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testCreateAuthorizationBuildsAuthorizeURLWithEmbeddedState() throws {
        let client = try TrustedRouterOAuthClient(baseURL: "https://api.trustedrouter.com/v1")
        let challenge = TrustedRouterPKCEChallenge(codeVerifier: "verifier")
        let authorization = try client.createAuthorization(
            callbackURL: "http://localhost:3000/callback?source=quillcode",
            keyLabel: "QuillCode Tests",
            limit: "5",
            usageLimitType: "monthly",
            challenge: challenge,
            state: "state-123"
        )

        XCTAssertEqual(authorization.codeVerifier, "verifier")
        XCTAssertEqual(authorization.state, "state-123")
        XCTAssertEqual(authorization.callbackURL.host(), "localhost")
        XCTAssertEqual(authorization.callbackURL.queryValue("state"), "state-123")
        XCTAssertEqual(authorization.callbackURL.queryValue("source"), "quillcode")
        XCTAssertEqual(authorization.url.scheme, "https")
        XCTAssertEqual(authorization.url.host(), "api.trustedrouter.com")
        XCTAssertEqual(authorization.url.path, "/v1/auth")
        XCTAssertEqual(authorization.url.queryValue("callback_url"), authorization.callbackURL.absoluteString)
        XCTAssertEqual(authorization.url.queryValue("code_challenge"), challenge.codeChallenge)
        XCTAssertEqual(authorization.url.queryValue("code_challenge_method"), "S256")
        XCTAssertEqual(authorization.url.queryValue("key_label"), "QuillCode Tests")
        XCTAssertEqual(authorization.url.queryValue("limit"), "5")
        XCTAssertEqual(authorization.url.queryValue("usage_limit_type"), "monthly")
    }

    func testParseCallbackRequiresMatchingStateAndCode() throws {
        let client = try TrustedRouterOAuthClient()
        let callback = URL(string: "http://localhost:3000/callback?code=auth_code-123&state=expected")!

        XCTAssertEqual(try client.parseCallback(callback, expectedState: "expected"), "auth_code-123")
        XCTAssertThrowsError(try client.parseCallback(callback, expectedState: "wrong")) { error in
            XCTAssertTrue(String(describing: error).contains("state"))
        }
        XCTAssertThrowsError(try client.parseCallback(URL(string: "http://localhost:3000/callback?state=expected")!, expectedState: "expected")) { error in
            XCTAssertTrue(String(describing: error).contains("code"))
        }
    }

    func testExchangeCodePostsNoAuthorizationHeaderAndDecodesToken() async throws {
        OAuthURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/keys")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
            let body = try XCTUnwrap(request.httpBodyText)
            XCTAssertTrue(body.contains(#""code":"auth_code-123""#))
            XCTAssertTrue(body.contains(#""code_verifier":"verifier""#))
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"key":"sk-tr-v1-test","user_id":"usr_123","identity":{"sub":"usr_123","email":"a@example.com","email_verified":true}}"#.utf8)
            )
        }
        let client = try TrustedRouterOAuthClient(
            baseURL: "https://api.trustedrouter.com/v1",
            urlSession: OAuthURLProtocol.session()
        )

        let token = try await client.exchangeCode(code: "auth_code-123", codeVerifier: "verifier")

        XCTAssertEqual(token.key, "sk-tr-v1-test")
        XCTAssertEqual(token.userID, "usr_123")
        XCTAssertEqual(token.identity?.email, "a@example.com")
        XCTAssertEqual(token.identity?.emailVerified, true)
    }

    func testFetchUserInfoUsesBearerKey() async throws {
        OAuthURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/userinfo")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer sk-tr-v1-test")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"data":{"sub":"usr_123","email":"a@example.com","email_verified":true}}"#.utf8)
            )
        }
        let client = try TrustedRouterOAuthClient(
            baseURL: "https://api.trustedrouter.com/v1",
            urlSession: OAuthURLProtocol.session()
        )

        let userInfo = try await client.fetchUserInfo(apiKey: "sk-tr-v1-test")

        XCTAssertEqual(userInfo.data.sub, "usr_123")
        XCTAssertEqual(userInfo.data.email, "a@example.com")
    }

    func testAccountProfileEnrichesTokenMetadataWithoutExposingKey() async throws {
        OAuthURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer secret-key")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"data":{"sub":"subject","email":"profile@example.com","wallet_address":"0x123"}}"#.utf8)
            )
        }
        let client = try TrustedRouterOAuthClient(urlSession: OAuthURLProtocol.session())
        let token = TrustedRouterOAuthToken(
            key: "secret-key",
            userID: "user-1",
            identity: nil
        )

        let profile = await client.accountProfile(from: token)

        XCTAssertEqual(profile?.userID, "user-1")
        XCTAssertEqual(profile?.subject, "subject")
        XCTAssertEqual(profile?.email, "profile@example.com")
        XCTAssertEqual(profile?.walletAddress, "0x123")
        XCTAssertFalse(String(describing: profile).contains("secret-key"))
    }
}

private final class OAuthURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OAuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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

private extension URL {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

private extension URLRequest {
    var httpBodyText: String? {
        if let httpBody {
            return String(data: httpBody, encoding: .utf8)
        }
        guard let httpBodyStream else { return nil }
        httpBodyStream.open()
        defer { httpBodyStream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while httpBodyStream.hasBytesAvailable {
            let count = httpBodyStream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8)
    }
}
