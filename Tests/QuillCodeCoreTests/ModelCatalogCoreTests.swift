import Foundation
import XCTest
@testable import QuillCodeCore

final class ModelCatalogCoreTests: XCTestCase {
    func testModelInfoDecodesOlderPayloadWithoutCapabilities() throws {
        let json = """
        {
          "id": "trustedrouter/fast",
          "provider": "trustedrouter",
          "displayName": "Nike 1.0",
          "category": "Recommended"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let model = try JSONDecoder().decode(ModelInfo.self, from: data)

        XCTAssertEqual(model.id, TrustedRouterDefaults.fastModel)
        XCTAssertTrue(model.capabilities.isEmpty)
    }

    func testModelCapabilitiesNormalizeCatalogMetadata() {
        let capabilities = ModelCapabilities(
            contextWindowTokens: -1,
            inputPricePerMillionTokens: -0.5,
            outputPricePerMillionTokens: 1.25,
            inputModalities: [" text ", "image", "text", ""],
            outputModalities: [" tool-call ", "tool_call"],
            capabilityTags: [" JSON-mode ", "json mode", "vision"],
            status: " available ",
            summary: " "
        )

        XCTAssertEqual(capabilities.contextWindowTokens, 0)
        XCTAssertEqual(capabilities.inputPricePerMillionTokens, 0)
        XCTAssertEqual(capabilities.outputPricePerMillionTokens, 1.25)
        XCTAssertEqual(capabilities.inputModalities, ["text", "image"])
        XCTAssertEqual(capabilities.outputModalities, ["tool call"])
        XCTAssertEqual(capabilities.capabilityTags, ["JSON mode", "vision"])
        XCTAssertEqual(capabilities.status, "available")
        XCTAssertNil(capabilities.summary)
        XCTAssertFalse(capabilities.isEmpty)
    }

    func testModelProviderHealthSummaryAggregatesProviderStatuses() throws {
        let summary = ModelProviderHealthSummary.summarize([
            ModelInfo(
                id: "acme/code-pro",
                provider: "acme",
                displayName: "Code Pro",
                category: "Coding",
                capabilities: ModelCapabilities(status: "available")
            ),
            ModelInfo(
                id: "acme/code-lite",
                provider: "acme",
                displayName: "Code Lite",
                category: "Coding",
                capabilities: ModelCapabilities(status: "rate_limited")
            ),
            ModelInfo(
                id: "z-ai/glm-5.2",
                provider: "z-ai",
                displayName: "GLM 5.2",
                category: "Safety",
                capabilities: ModelCapabilities(status: "online")
            ),
            ModelInfo(
                id: "moonshotai/kimi-k2.6",
                provider: "moonshotai",
                displayName: "Kimi K2.6",
                category: "Safety"
            )
        ])

        XCTAssertEqual(summary.label, "Provider health: 1 provider needs attention")
        XCTAssertTrue(summary.detail.contains("Provider statuses needing attention"))
        XCTAssertEqual(summary.rows.map(\.provider), ["acme", "z-ai"])

        let acme = try XCTUnwrap(summary.rows.first { $0.provider == "acme" })
        XCTAssertEqual(acme.statusLabel, "rate limited")
        XCTAssertEqual(acme.statusTone, "warning")
        XCTAssertEqual(acme.modelCount, 2)
        XCTAssertEqual(acme.statusBreakdown, ["rate limited (1 model)", "available (1 model)"])
    }

    func testModelProviderHealthSummaryHandlesMissingStatusMetadata() {
        let summary = ModelProviderHealthSummary.summarize([
            ModelInfo(
                id: "acme/code-pro",
                provider: "acme",
                displayName: "Code Pro",
                category: "Coding"
            )
        ])

        XCTAssertEqual(summary.label, "Provider health unavailable")
        XCTAssertEqual(summary.detail, "TrustedRouter catalog did not include live provider status metadata.")
        XCTAssertTrue(summary.rows.isEmpty)
    }

    func testTrustedRouterDefaults() {
        XCTAssertEqual(TrustedRouterDefaults.fastModel, "trustedrouter/fast")
        XCTAssertEqual(TrustedRouterDefaults.synthModel, "tr/synth")
        XCTAssertEqual(TrustedRouterDefaults.synthCodeModel, "tr/synth-code")
        XCTAssertEqual(TrustedRouterDefaults.synthSlashAlias, "/synth")
        XCTAssertEqual(TrustedRouterDefaults.synthCodeSlashAlias, "/synth-code")
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.fastModel), "Nike 1.0")
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.synthModel), "Synth")
        XCTAssertEqual(
            TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.synthCodeModel),
            "Synth Code"
        )
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.synthModel), "/synth")
        XCTAssertEqual(
            TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.synthCodeModel),
            "/synth-code"
        )
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID("trustedrouter/fusion"), "/synth")
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID("trustedrouter/fusion-code"), "/synth-code")
        XCTAssertEqual(
            TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.fastModel),
            "trustedrouter/fast"
        )
        XCTAssertEqual(TrustedRouterDefaults.defaultModel, TrustedRouterDefaults.fastModel)
        XCTAssertEqual(
            TrustedRouterDefaults.recommendedModelIDs,
            [
                TrustedRouterDefaults.socratesModel,
                TrustedRouterDefaults.fastModel,
                TrustedRouterDefaults.synthModel,
                TrustedRouterDefaults.synthCodeModel
            ]
        )
        XCTAssertEqual(
            TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.socratesModel),
            "Socrates 1.1"
        )
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.socratesModel), "/socrates")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("socrates-1.1"), TrustedRouterDefaults.socratesModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/socrates"), TrustedRouterDefaults.socratesModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalProvider("tr"), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalProvider(" TR "), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Nike 1.0"), TrustedRouterDefaults.fastModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/fast"), TrustedRouterDefaults.fastModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/synth"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Synth"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/synth"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(
            TrustedRouterDefaults.canonicalModelID(TrustedRouterDefaults.synthSlashAlias),
            TrustedRouterDefaults.synthModel
        )
        XCTAssertEqual(
            TrustedRouterDefaults.provider(fromModelID: TrustedRouterDefaults.synthSlashAlias),
            TrustedRouterDefaults.trustedRouterProvider
        )
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/fusion"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("FUSION"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/fusion"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/fusion"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/synth-code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Synth Code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(
            TrustedRouterDefaults.canonicalModelID("trustedrouter/synth-code"),
            TrustedRouterDefaults.synthCodeModel
        )
        XCTAssertEqual(
            TrustedRouterDefaults.canonicalModelID(TrustedRouterDefaults.synthCodeSlashAlias),
            TrustedRouterDefaults.synthCodeModel
        )
        XCTAssertEqual(
            TrustedRouterDefaults.provider(fromModelID: TrustedRouterDefaults.synthCodeSlashAlias),
            TrustedRouterDefaults.trustedRouterProvider
        )
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/fusion-code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(
            TrustedRouterDefaults.canonicalModelID("trustedrouter/fusion-code"),
            TrustedRouterDefaults.synthCodeModel
        )
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/fusion-code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.safetyPrimaryModel, "glm-5.2")
        XCTAssertEqual(TrustedRouterDefaults.safetyFallbackModel, "kimi-k2.6")
        XCTAssertLessThan(
            TrustedRouterDefaults.modelSortKey(
                id: TrustedRouterDefaults.fastModel,
                provider: "trustedrouter",
                displayName: "Nike 1.0"
            ),
            TrustedRouterDefaults.modelSortKey(
                id: TrustedRouterDefaults.synthModel,
                provider: "tr",
                displayName: "Synth"
            )
        )
        XCTAssertLessThan(
            TrustedRouterDefaults.modelCategoryRank(TrustedRouterDefaults.recommendedCategory),
            TrustedRouterDefaults.modelCategoryRank(TrustedRouterDefaults.safetyCategory)
        )
    }

    func testModelCatalogNormalizationDeduplicatesAliasesAndSortsDefaultsFirst() {
        let catalog = TrustedRouterDefaults.normalizedModelCatalog([
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "/synth", provider: "trustedrouter", displayName: "Synth Alias", category: "Recommended"),
            .init(id: "trustedrouter/fusion", provider: "trustedrouter", displayName: "Legacy Fusion", category: "Recommended"),
            .init(id: "/synth-code", provider: "trustedrouter", displayName: "Synth Code Alias", category: "Recommended"),
            .init(id: "/fusion-code", provider: "trustedrouter", displayName: "Legacy Fusion Code", category: "Recommended"),
            .init(id: "tr/fast", provider: "tr", displayName: "Fast Alias", category: "Recommended")
        ])

        XCTAssertEqual(
            catalog.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id),
            TrustedRouterDefaults.recommendedModelIDs
        )
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.socratesModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.fastModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.synthModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.synthCodeModel }.count, 1)
        XCTAssertFalse(catalog.contains { $0.id.contains("fusion") })
        XCTAssertFalse(catalog.contains { $0.displayName.contains("Fusion") })
        XCTAssertTrue(catalog.contains { $0.id == "acme/code-pro" })
    }

    func testModelCatalogStatusLabelsFreshStaleAndFallbackStates() {
        let now = Date(timeIntervalSince1970: 10_000)
        let immediate = ModelCatalogStatus.liveTrustedRouter(fetchedAt: now.addingTimeInterval(-30))
        let fresh = ModelCatalogStatus.liveTrustedRouter(fetchedAt: now.addingTimeInterval(-120))
        let stale = ModelCatalogStatus.liveTrustedRouter(fetchedAt: now.addingTimeInterval(-7_200))
        let fallback = ModelCatalogStatus.fallbackAfterFailure(
            "  HTTP 500\nprovider down  ",
            fetchedAt: now
        )

        XCTAssertEqual(immediate.statusLabel(now: now), "Live TrustedRouter catalog · just now")
        XCTAssertEqual(fresh.statusLabel(now: now), "Live TrustedRouter catalog · 2m ago")
        XCTAssertEqual(stale.statusLabel(now: now), "Live TrustedRouter catalog · stale 2h ago")
        XCTAssertEqual(fallback.statusLabel(now: now), "Bundled fallback · refresh failed")
        XCTAssertEqual(
            fallback.detailLabel(now: now),
            "The latest TrustedRouter model refresh failed: HTTP 500 provider down"
        )
        XCTAssertEqual(ModelCatalogStatus.bundled.statusLabel(now: now), "Bundled catalog")
    }
}
