import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class WorkspaceRuntimeFactoryTests: XCTestCase {
    override func tearDown() {
        RuntimeFactoryCatalogURLProtocol.reset()
        super.tearDown()
    }

    func testUsesTrustedRouterWhenEnvironmentKeyExists() throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()

        let runtime = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["TRUSTEDROUTER_API_KEY": "sk-test"]
        ).makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .trustedRouter)
        XCTAssertEqual(runtime.statusLabel, QuillCodeRuntimeStatusLabel.trustedRouterSignedIn)
        XCTAssertTrue(runtime.contextSummaryGenerator.isModelBacked)
    }

    func testEnvironmentKeyCountsAsTrustedRouterCatalogCredential() throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()

        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["TRUSTEDROUTER_API_KEY": "sk-test"]
        )

        XCTAssertTrue(runtimeFactory.hasTrustedRouterAPIKey())
    }

    func testKeyFileCountsAsTrustedRouterCredential() throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()
        let keyFile = paths.home.appendingPathComponent("trustedrouter.key")
        try "sk-test-from-file\n".write(to: keyFile, atomically: true, encoding: .utf8)

        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_API_KEY_FILE": keyFile.path]
        )

        XCTAssertTrue(runtimeFactory.hasTrustedRouterAPIKey())
        XCTAssertEqual(runtimeFactory.makeRuntime(config: AppConfig()).mode, .trustedRouter)
    }

    func testUsesTrustedRouterWhenSecretExists() throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()
        try FileSecretStore(directory: paths.secretsDirectory).write(
            "sk-test",
            for: QuillSecretKeys.trustedRouterAPIKey
        )

        let runtime = QuillCodeRuntimeFactory(paths: paths, environment: [:])
            .makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .trustedRouter)
        XCTAssertTrue(runtime.contextSummaryGenerator.isModelBacked)
        XCTAssertTrue(QuillCodeRuntimeFactory(paths: paths, environment: [:]).hasTrustedRouterAPIKey())
    }

    func testCanForceMockForDeterministicRuns() throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()

        let runtime = QuillCodeRuntimeFactory(
            paths: paths,
            environment: [
                "TRUSTEDROUTER_API_KEY": "sk-test",
                "QUILLCODE_USE_MOCK_LLM": "true"
            ]
        ).makeRuntime(config: AppConfig())

        XCTAssertEqual(runtime.mode, .mock)
        XCTAssertEqual(runtime.statusLabel, QuillCodeRuntimeStatusLabel.mockLLM)
        XCTAssertFalse(runtime.contextSummaryGenerator.isModelBacked)
    }

    func testModelCatalogFetchesPublicCatalogWithoutKey() async throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()
        RuntimeFactoryCatalogURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://trustedrouter.com/models")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                <script type="application/ld+json">
                {"@type":"ItemList","itemListElement":[
                {"url":"https://trustedrouter.com/models/minimax/minimax-m3","name":"MiniMax M3"},
                {"url":"https://trustedrouter.com/models/anthropic/claude-sonnet-5","name":"Claude Sonnet 5"}
                ]}
                </script>
                """.utf8)
            )
        }

        let catalog = await QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_API_KEY_FILE": paths.home.appendingPathComponent("missing.key").path],
            modelCatalogURLSession: RuntimeFactoryCatalogURLProtocol.session()
        ).fetchModelCatalog(config: AppConfig())

        XCTAssertEqual(catalog.defaultModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(catalog.status.source, .publicTrustedRouter)
        XCTAssertTrue(catalog.models.contains { $0.id == "trustedrouter/fast" })
        XCTAssertTrue(catalog.models.contains { $0.id == TrustedRouterDefaults.prometheusModel })
        XCTAssertTrue(catalog.models.contains { $0.id == "minimax/minimax-m3" })
    }

    func testFetchTrustedRouterCreditsUsesConfiguredCredential() async throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()
        RuntimeFactoryCatalogURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.trustedrouter.test/v1/credits")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"balance":7.25,"currency":"USD"}"#.utf8)
            )
        }

        let result = await QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["TRUSTEDROUTER_API_KEY": "sk-test"],
            accountCreditsURLSession: RuntimeFactoryCatalogURLProtocol.session()
        ).fetchTrustedRouterCredits(config: AppConfig(
            apiBaseURL: "https://api.trustedrouter.test/v1"
        ))

        guard case .success(let snapshot) = result else {
            return XCTFail("Expected a live account credit snapshot")
        }
        XCTAssertEqual(snapshot.balance, 7.25)
        XCTAssertEqual(snapshot.currency, "USD")
    }

    func testFetchTrustedRouterCreditsIsUnavailableWithoutCredentialOrInMockMode() async throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()

        let missingCredential = await QuillCodeRuntimeFactory(
            paths: paths,
            environment: [
                "QUILLCODE_API_KEY_FILE": paths.home.appendingPathComponent("missing.key").path
            ]
        ).fetchTrustedRouterCredits(config: AppConfig())
        let forcedMock = await QuillCodeRuntimeFactory(
            paths: paths,
            environment: [
                "TRUSTEDROUTER_API_KEY": "sk-test",
                "QUILLCODE_USE_MOCK_LLM": "true"
            ]
        ).fetchTrustedRouterCredits(config: AppConfig())

        XCTAssertEqual(missingCredential, .unavailable)
        XCTAssertEqual(forcedMock, .unavailable)
    }
}

private final class RuntimeFactoryCatalogURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RuntimeFactoryCatalogURLProtocol.self]
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
