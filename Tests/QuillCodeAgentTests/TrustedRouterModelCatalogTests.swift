import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TrustedRouterModelCatalogTests: XCTestCase {
    override func tearDown() {
        ModelCatalogURLProtocol.reset()
        super.tearDown()
    }

    func testModelCatalogMapsProvidersAndCategories() {
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "trustedrouter/fast" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "tr/synth" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "tr/synth-code" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "z-ai/glm-5.2" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "moonshotai/kimi-k2.6" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "tr/socrates" })
        XCTAssertEqual(TrustedRouterModelCatalog.defaultModels.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "tr/synth"), "trustedrouter")
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "/synth"), "trustedrouter")
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "tr/fusion"), "trustedrouter")
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "z-ai/glm-5.2"), "z-ai")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "tr/synth", provider: "trustedrouter"), "Recommended")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "/synth", provider: "trustedrouter"), "Recommended")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "tr/fusion", provider: "trustedrouter"), "Recommended")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "moonshotai/kimi-k2.6", provider: "moonshotai"), "Safety")
    }

    func testModelCatalogAlwaysIncludesRankedRecommendedFallbacks() {
        let catalog = TrustedRouterModelCatalog(models: [
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: TrustedRouterDefaults.fastModel, provider: "trustedrouter", displayName: "Fast Duplicate", category: "Recommended"),
            .init(id: "/synth", provider: "trustedrouter", displayName: "Synth Alias", category: "Recommended"),
            .init(id: "tr/fusion", provider: "trustedrouter", displayName: "Legacy Fusion", category: "Recommended"),
            .init(id: "/fusion-code", provider: "trustedrouter", displayName: "Legacy Fusion Code", category: "Recommended")
        ])

        XCTAssertEqual(catalog.models.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
        XCTAssertEqual(Array(catalog.categories().prefix(3)), ["Recommended", "Safety", "Coding"])
        XCTAssertEqual(catalog.models.filter { $0.id == TrustedRouterDefaults.fastModel }.count, 1)
        XCTAssertEqual(catalog.models.filter { $0.id == TrustedRouterDefaults.synthModel }.count, 1)
        XCTAssertEqual(catalog.models.filter { $0.id == TrustedRouterDefaults.synthCodeModel }.count, 1)
        XCTAssertFalse(catalog.models.contains { $0.id == "/synth" })
        XCTAssertFalse(catalog.models.contains { $0.id.contains("fusion") })
        XCTAssertFalse(catalog.models.contains { $0.displayName.contains("Alias") })
        XCTAssertFalse(catalog.models.contains { $0.displayName.contains("Fusion") })
        XCTAssertTrue(catalog.models.contains { $0.id == "acme/code-pro" })
    }

    func testCatalogFetchDecodesLiveCapabilityMetadata() async throws {
        ModelCatalogURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                {
                  "data": [
                    {
                      "id": "acme/vision-code",
                      "display_name": "Vision Code",
                      "context_window": "128,000",
                      "pricing": { "prompt": "0.00000025", "completion": 0.00000125 },
                      "input_modalities": ["text", "image"],
                      "output_modalities": "text",
                      "supported_parameters": { "tools": true, "json_mode": true, "legacy": false },
                      "status": "available",
                      "description": "Vision coding model"
                    }
                  ]
                }
                """.utf8)
            )
        }
        let client = TrustedRouterModelCatalogClient(
            apiKey: "sk-test",
            baseURL: "https://api.trustedrouter.test/v1",
            urlSession: ModelCatalogURLProtocol.session()
        )

        let catalog = try await client.fetch()
        let model = try XCTUnwrap(catalog.models.first { $0.id == "acme/vision-code" })

        XCTAssertEqual(catalog.status.source, .liveTrustedRouter)
        XCTAssertNotNil(catalog.status.fetchedAt)
        XCTAssertEqual(model.displayName, "Vision Code")
        XCTAssertEqual(model.category, "acme")
        XCTAssertEqual(model.capabilities.contextWindowTokens, 128_000)
        XCTAssertEqual(model.capabilities.inputPricePerMillionTokens, 0.25)
        XCTAssertEqual(model.capabilities.outputPricePerMillionTokens, 1.25)
        XCTAssertEqual(model.capabilities.inputModalities, ["text", "image"])
        XCTAssertEqual(model.capabilities.outputModalities, ["text"])
        XCTAssertEqual(model.capabilities.capabilityTags, ["json mode", "tools"])
        XCTAssertEqual(model.capabilities.status, "available")
        XCTAssertEqual(model.capabilities.summary, "Vision coding model")
    }

    func testCatalogFetchEmptyResponseUsesFallbackStatus() async throws {
        ModelCatalogURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"data":[]}"#.utf8)
            )
        }
        let client = TrustedRouterModelCatalogClient(
            apiKey: "sk-test",
            baseURL: "https://api.trustedrouter.test/v1",
            urlSession: ModelCatalogURLProtocol.session()
        )

        let catalog = try await client.fetch()

        XCTAssertEqual(catalog.status.source, .fallbackAfterFailure)
        XCTAssertEqual(catalog.status.failureMessage, "TrustedRouter returned an empty model catalog.")
        XCTAssertEqual(
            catalog.models.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id),
            TrustedRouterDefaults.recommendedModelIDs
        )
    }
}

private final class ModelCatalogURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
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
