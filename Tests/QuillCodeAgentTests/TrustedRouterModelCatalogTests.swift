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
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "trustedrouter/zeus" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "trustedrouter/fusion" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "trustedrouter/socrates" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "trustedrouter/aristotle" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "trustedrouter/plato" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "z-ai/glm-5.2" })
        XCTAssertTrue(TrustedRouterModelCatalog.defaultModels.contains { $0.id == "moonshotai/kimi-k2.6" })
        XCTAssertEqual(TrustedRouterModelCatalog.defaultModels.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "tr/prometheus"), "trustedrouter")
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "/prometheus"), "trustedrouter")
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "tr/zeus"), "trustedrouter")
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "tr/fusion"), "trustedrouter")
        XCTAssertEqual(TrustedRouterModelCatalogClient.provider(from: "z-ai/glm-5.2"), "z-ai")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "tr/prometheus", provider: "trustedrouter"), "Recommended")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "/prometheus", provider: "trustedrouter"), "Recommended")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "tr/zeus", provider: "trustedrouter"), "Recommended")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "tr/fusion", provider: "trustedrouter"), "Recommended")
        XCTAssertEqual(TrustedRouterModelCatalogClient.category(for: "moonshotai/kimi-k2.6", provider: "moonshotai"), "Safety")
    }

    func testModelCatalogAlwaysIncludesRankedRecommendedFallbacks() {
        let catalog = TrustedRouterModelCatalog(models: [
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: TrustedRouterDefaults.fastModel, provider: "trustedrouter", displayName: "Fast Duplicate", category: "Recommended"),
            .init(id: "/prometheus", provider: "trustedrouter", displayName: "Prometheus 1.0 Alias", category: "Recommended"),
            .init(id: "tr/fusion", provider: "trustedrouter", displayName: "Legacy Fusion", category: "Recommended"),
            .init(id: "/plato", provider: "trustedrouter", displayName: "Plato Alias", category: "Recommended")
        ])

        XCTAssertEqual(catalog.models.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
        XCTAssertEqual(Array(catalog.categories().prefix(3)), ["Recommended", "Safety", "Coding"])
        XCTAssertEqual(catalog.models.filter { $0.id == TrustedRouterDefaults.fastModel }.count, 1)
        XCTAssertEqual(catalog.models.filter { $0.id == TrustedRouterDefaults.prometheusModel }.count, 1)
        XCTAssertEqual(catalog.models.filter { $0.id == TrustedRouterDefaults.platoModel }.count, 1)
        XCTAssertFalse(catalog.models.contains { $0.id == "/prometheus" })
        XCTAssertFalse(catalog.models.contains { ["tr/fusion", "/plato"].contains($0.id) })
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
                      "created": 1747008000,
                      "pricing": { "prompt": "0.00000025", "completion": 0.00000125 },
                      "input_modalities": ["text", "image"],
                      "output_modalities": "text",
                      "supported_parameters": { "tools": true, "json_mode": true, "legacy": false },
                      "supports_personality": true,
                      "status": "available",
                      "description": "Vision coding model"
                    },
                    {
                      "id": "acme/vision-code-ms",
                      "created": 1747008000000,
                      "supportsPersonality": "false",
                      "pricing": { "prompt": "0.00000025", "completion": 0.00000125 }
                    },
                    {
                      "id": "acme/vision-code-dated",
                      "release_date": "2025-05-12",
                      "pricing": { "prompt": "0.00000025", "completion": 0.00000125 }
                    },
                    {
                      "id": "acme/broken-metadata",
                      "created": "1e999",
                      "pricing": { "prompt": "inf", "completion": "1e999" }
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
        XCTAssertEqual(model.capabilities.supportsPersonality, true)
        XCTAssertEqual(model.capabilities.status, "available")
        XCTAssertEqual(model.capabilities.summary, "Vision coding model")
        XCTAssertEqual(model.capabilities.releaseDate, Date(timeIntervalSince1970: 1_747_008_000))

        // 2025-05-12T00:00:00Z — the same instant expressed as a millisecond epoch and a date string.
        let millisecondModel = try XCTUnwrap(catalog.models.first { $0.id == "acme/vision-code-ms" })
        XCTAssertEqual(millisecondModel.capabilities.releaseDate, Date(timeIntervalSince1970: 1_747_008_000))
        XCTAssertEqual(millisecondModel.capabilities.supportsPersonality, false)
        let datedModel = try XCTUnwrap(catalog.models.first { $0.id == "acme/vision-code-dated" })
        XCTAssertEqual(datedModel.capabilities.releaseDate, Date(timeIntervalSince1970: 1_747_008_000))

        // Non-finite metadata ("inf"/"1e999" parse to +infinity via Double(String)) decodes as
        // absent, never as an infinite price or date that could poison downstream scoring.
        let brokenModel = try XCTUnwrap(catalog.models.first { $0.id == "acme/broken-metadata" })
        XCTAssertNil(brokenModel.capabilities.inputPricePerMillionTokens)
        XCTAssertNil(brokenModel.capabilities.outputPricePerMillionTokens)
        XCTAssertNil(brokenModel.capabilities.releaseDate)
    }

    func testPublicCatalogParserIncludesMiniMaxAndExcludesSyntheticRoutes() throws {
        let html = """
        <script type="application/ld+json">
        {"@type":"ItemList","itemListElement":[
        {"url":"https://trustedrouter.com/models/minimax/minimax-m3","name":"MiniMax M3"},
        {"url":"https://trustedrouter.com/models/minimax/minimax-m3","name":"MiniMax M3 Duplicate"},
        {"url":"https://trustedrouter.com/models/trustedrouter/synth","name":"Synth"},
        {"url":"https://trustedrouter.com/models/trustedrouter/synth-code","name":"Synth Code"},
        {"url":"https://trustedrouter.com/models/trustedrouter/fusion-code","name":"Fusion Code"},
        {"url":"https://trustedrouter.com/models/z-ai/glm-5.2","name":"GLM 5.2"}
        ]}
        </script>
        """

        let models = TrustedRouterModelCatalogClient.publicCatalogModels(fromHTML: html)

        let miniMax = try XCTUnwrap(models.first { $0.id == "minimax/minimax-m3" })
        XCTAssertEqual(miniMax.displayName, "MiniMax M3")
        XCTAssertEqual(miniMax.provider, "minimax")
        XCTAssertEqual(miniMax.category, "minimax")
        XCTAssertEqual(models.filter { $0.id == "minimax/minimax-m3" }.count, 1)
        XCTAssertTrue(models.contains { $0.id == "z-ai/glm-5.2" })
        XCTAssertFalse(models.contains { $0.id == "trustedrouter/synth" })
        XCTAssertFalse(models.contains { $0.id == "trustedrouter/synth-code" })
        XCTAssertFalse(models.contains { $0.id == "trustedrouter/fusion-code" })
    }

    func testCatalogFetchFallsBackToPublicTrustedRouterCatalogWhenJSONEndpointFails() async throws {
        ModelCatalogURLProtocol.handler = { request in
            if request.url?.host == "api.trustedrouter.test" {
                XCTAssertEqual(request.url?.path, "/v1/models")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"error":{"message":"route not found"}}"#.utf8)
                )
            }
            XCTAssertEqual(request.url?.absoluteString, "https://trustedrouter.com/models")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("""
                <script type="application/ld+json">
                {"@type":"ItemList","itemListElement":[
                {"url":"https://trustedrouter.com/models/minimax/minimax-m3","name":"MiniMax M3"},
                {"url":"https://trustedrouter.com/models/openai/gpt-5.5","name":"GPT 5.5"}
                ]}
                </script>
                """.utf8)
            )
        }
        let client = TrustedRouterModelCatalogClient(
            apiKey: "sk-test",
            baseURL: "https://api.trustedrouter.test/v1",
            urlSession: ModelCatalogURLProtocol.session()
        )

        let catalog = try await client.fetch()

        XCTAssertEqual(catalog.status.source, .publicTrustedRouter)
        XCTAssertTrue(catalog.status.failureMessage?.contains("Authenticated JSON catalog failed") == true)
        XCTAssertTrue(catalog.models.contains { $0.id == "minimax/minimax-m3" })
        XCTAssertTrue(catalog.models.contains { $0.id == "openai/gpt-5.5" })
        XCTAssertEqual(catalog.models.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
    }

    func testNormalizedCatalogBackfillsLiveCapabilitiesIntoBundledEntries() throws {
        // The bundled curated entries (empty capabilities) dedup-shadow same-canonical-ID live rows.
        // The live row's capabilities must be backfilled, or canonical models — including the default
        // session model — would never look priced to pricing-aware features like the aux selector.
        let liveFast = ModelInfo(
            id: TrustedRouterDefaults.fastModel,
            provider: "trustedrouter",
            displayName: "Live Fast Row",
            category: "trustedrouter",
            capabilities: ModelCapabilities(
                contextWindowTokens: 200_000,
                inputPricePerMillionTokens: 3,
                outputPricePerMillionTokens: 15
            )
        )

        let catalog = TrustedRouterModelCatalog(models: [liveFast])
        let fast = try XCTUnwrap(catalog.models.first { $0.id == TrustedRouterDefaults.fastModel })

        XCTAssertEqual(catalog.models.filter { $0.id == TrustedRouterDefaults.fastModel }.count, 1)
        // Curated identity wins; live capabilities fill the gaps.
        XCTAssertEqual(fast.displayName, TrustedRouterDefaults.fastModelDisplayName)
        XCTAssertEqual(fast.category, TrustedRouterDefaults.recommendedCategory)
        XCTAssertEqual(fast.capabilities.inputPricePerMillionTokens, 3)
        XCTAssertEqual(fast.capabilities.outputPricePerMillionTokens, 15)
        XCTAssertEqual(fast.capabilities.contextWindowTokens, 200_000)
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

    /// The live catalog nests `privacy_tier` under the `trustedrouter` object (the exact shape
    /// trustedrouter.com/v1/models serves). Reading only the top level decoded every model's
    /// privacyTier as nil, so the confidential picker never saw a tier-3 model and stayed locked
    /// to the aggregate E2E route. Top-level spelling stays supported; absent stays nil.
    func testPrivacyTierDecodesFromNestedTrustedRouterObject() throws {
        let json = #"""
        {"data":[
          {"id":"trustedrouter/socrates","name":"Socrates",
           "trustedrouter":{"provider":"trustedrouter","privacy_tier":3,"privacy_tier_label":"Confidential"}},
          {"id":"z-ai/glm-4.5","name":"GLM 4.5",
           "trustedrouter":{"provider":"zai","privacy_tier":0,"privacy_tier_label":"Standard"}},
          {"id":"acme/top-level","name":"Top Level","privacy_tier":2},
          {"id":"acme/no-tier","name":"No Tier"}
        ]}
        """#
        let response = try JSONDecoder().decode(
            TrustedRouterCatalogModelsResponse.self,
            from: Data(json.utf8)
        )
        let byID = Dictionary(uniqueKeysWithValues: response.data.map { ($0.id, $0.capabilities.privacyTier) })
        XCTAssertEqual(byID["trustedrouter/socrates"], 3, "nested tier must decode")
        XCTAssertEqual(byID["z-ai/glm-4.5"], 0, "nested tier 0 must decode as 0, not nil")
        XCTAssertEqual(byID["acme/top-level"], 2, "top-level spelling stays supported")
        XCTAssertEqual(byID["acme/no-tier"], .some(nil), "absent tier stays nil")
        // The whole point: a nested tier-3 model is E2E-eligible for confidential chats.
        let infos = response.data.map {
            ModelInfo(
                id: $0.id,
                provider: TrustedRouterModelCatalogClient.provider(from: $0.id),
                displayName: $0.displayName ?? $0.id,
                category: "Test",
                capabilities: $0.capabilities
            )
        }
        XCTAssertTrue(TrustedRouterDefaults.isE2EEligible("trustedrouter/socrates", catalog: infos))
        XCTAssertFalse(TrustedRouterDefaults.isE2EEligible("z-ai/glm-4.5", catalog: infos))
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
