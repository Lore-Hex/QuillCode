import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class TrustedRouterModelCatalogTests: XCTestCase {
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
}
