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
        XCTAssertEqual(TrustedRouterDefaults.zeusModel, "trustedrouter/zeus")
        XCTAssertEqual(TrustedRouterDefaults.prometheusModel, "trustedrouter/fusion")
        XCTAssertEqual(TrustedRouterDefaults.socratesModel, "trustedrouter/socrates")
        XCTAssertEqual(TrustedRouterDefaults.aristotleModel, "trustedrouter/aristotle")
        XCTAssertEqual(TrustedRouterDefaults.platoModel, "trustedrouter/plato")
        XCTAssertEqual(TrustedRouterDefaults.prometheusSlashAlias, "/prometheus")
        XCTAssertEqual(TrustedRouterDefaults.platoSlashAlias, "/plato")
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.fastModel), "Nike 1.0")
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.zeusModel), "Zeus 1.0")
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.prometheusModel), "Prometheus 1.0")
        XCTAssertEqual(
            TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.platoModel),
            "Plato 1.0"
        )
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.prometheusModel), "/prometheus")
        XCTAssertEqual(
            TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.platoModel),
            "/plato"
        )
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID("trustedrouter/fusion"), "/prometheus")
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID("trustedrouter/plato"), "/plato")
        XCTAssertEqual(
            TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.fastModel),
            "trustedrouter/fast"
        )
        XCTAssertEqual(TrustedRouterDefaults.defaultModel, TrustedRouterDefaults.fastModel)
        XCTAssertEqual(
            TrustedRouterDefaults.recommendedModelIDs,
            [
                TrustedRouterDefaults.fastModel,
                TrustedRouterDefaults.zeusModel,
                TrustedRouterDefaults.prometheusModel,
                TrustedRouterDefaults.socratesModel,
                TrustedRouterDefaults.aristotleModel,
                TrustedRouterDefaults.platoModel
            ]
        )
        XCTAssertEqual(
            TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.socratesModel),
            "Socrates 1.0"
        )
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.socratesModel), "/socrates")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("socrates-1.0"), TrustedRouterDefaults.socratesModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/socrates"), TrustedRouterDefaults.socratesModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalProvider("tr"), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalProvider(" TR "), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Nike 1.0"), TrustedRouterDefaults.fastModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/fast"), TrustedRouterDefaults.fastModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Deep Research"), TrustedRouterDefaults.zeusModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/zeus"), TrustedRouterDefaults.zeusModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/prometheus"), TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Prometheus 1.0"), TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/prometheus"), TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/prometheus"), TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(TrustedRouterDefaults.provider(fromModelID: "/prometheus"), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/fusion"), TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("FUSION"), "FUSION")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/fusion"), TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/fusion"), "/fusion")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("synth"), "synth")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/synth"), "/synth")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/synth"), "tr/synth")
        XCTAssertTrue(TrustedRouterDefaults.isRetiredRawModelID("synth"))
        XCTAssertTrue(TrustedRouterDefaults.isRetiredRawModelID("tr/synth"))
        XCTAssertEqual(TrustedRouterDefaults.normalizedDefaultModelID("synth"), TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(TrustedRouterDefaults.normalizedDefaultModelID("tr/synth"), TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/plato"), TrustedRouterDefaults.platoModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Plato 1.0"), TrustedRouterDefaults.platoModel)
        XCTAssertEqual(
            TrustedRouterDefaults.canonicalModelID("trustedrouter/plato"),
            TrustedRouterDefaults.platoModel
        )
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/plato"), TrustedRouterDefaults.platoModel)
        XCTAssertEqual(TrustedRouterDefaults.provider(fromModelID: "/plato"), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/plato"), TrustedRouterDefaults.platoModel)
        XCTAssertEqual(
            TrustedRouterDefaults.canonicalModelID("trustedrouter/plato"),
            TrustedRouterDefaults.platoModel
        )
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/plato"), TrustedRouterDefaults.platoModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("synth-code"), "synth-code")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("fusion-code"), "fusion-code")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Aristotle"), TrustedRouterDefaults.aristotleModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("smart"), TrustedRouterDefaults.aristotleModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Plato"), TrustedRouterDefaults.platoModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("oss coding"), TrustedRouterDefaults.platoModel)
        XCTAssertEqual(TrustedRouterDefaults.safetyPrimaryModel, "glm-5.2")
        XCTAssertEqual(TrustedRouterDefaults.safetyFallbackModel, "kimi-k2.6")
        XCTAssertEqual(TrustedRouterDefaults.minimaxM3Model, "minimax/minimax-m3")
        XCTAssertLessThan(
            TrustedRouterDefaults.modelSortKey(
                id: TrustedRouterDefaults.fastModel,
                provider: "trustedrouter",
                displayName: "Nike 1.0"
            ),
            TrustedRouterDefaults.modelSortKey(
                id: TrustedRouterDefaults.prometheusModel,
                provider: "tr",
                displayName: "Prometheus 1.0"
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
            .init(id: "/prometheus", provider: "trustedrouter", displayName: "Prometheus 1.0 Alias", category: "Recommended"),
            .init(id: "trustedrouter/fusion", provider: "trustedrouter", displayName: "Legacy Fusion", category: "Recommended"),
            .init(id: "/plato", provider: "trustedrouter", displayName: "Plato 1.0 Alias", category: "Recommended"),
            .init(id: "tr/plato", provider: "trustedrouter", displayName: "Plato Alias", category: "Recommended"),
            .init(id: "tr/fast", provider: "tr", displayName: "Fast Alias", category: "Recommended")
        ])

        XCTAssertEqual(
            catalog.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id),
            TrustedRouterDefaults.recommendedModelIDs
        )
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.socratesModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.fastModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.prometheusModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.platoModel }.count, 1)
        XCTAssertFalse(catalog.contains { ["/prometheus", "tr/prometheus", "tr/fusion", "/plato", "tr/plato"].contains($0.id) })
        XCTAssertFalse(catalog.contains { $0.displayName.contains("Fusion") })
        XCTAssertTrue(catalog.contains { $0.id == "acme/code-pro" })
    }

    func testBundledRecommendedModelsCarryStableCapabilityTaxonomy() throws {
        let catalog = TrustedRouterDefaults.normalizedModelCatalog([])

        let nike = try XCTUnwrap(catalog.first { $0.id == TrustedRouterDefaults.fastModel })
        XCTAssertEqual(nike.capabilities.summary, "Fast everyday agent")
        XCTAssertEqual(nike.capabilities.inputModalities, ["text"])
        XCTAssertEqual(nike.capabilities.outputModalities, ["text", "tool call"])
        XCTAssertEqual(nike.capabilities.capabilityTags, ["fast", "coding", "shell", "file editing"])

        let plato = try XCTUnwrap(catalog.first { $0.id == TrustedRouterDefaults.platoModel })
        XCTAssertEqual(plato.capabilities.capabilityTags, ["freedom", "OSS", "coding agent"])
    }

    func testBundledCatalogIncludesUnbrandedProviderDiscoveryRows() throws {
        let catalog = TrustedRouterDefaults.normalizedModelCatalog([])
        let minimax = try XCTUnwrap(catalog.first { $0.id == TrustedRouterDefaults.minimaxM3Model })

        XCTAssertEqual(minimax.provider, "minimax")
        XCTAssertEqual(minimax.displayName, "MiniMax M3")
        XCTAssertEqual(minimax.category, "minimax")
        XCTAssertNil(TrustedRouterDefaults.recommendedRank(for: minimax.id))
    }

    func testLiveRecommendedModelCapabilitiesBackfillCuratedTaxonomy() throws {
        let catalog = TrustedRouterDefaults.normalizedModelCatalog([
            .init(
                id: "tr/fast",
                provider: "tr",
                displayName: "Fast",
                category: "Recommended",
                capabilities: ModelCapabilities(
                    contextWindowTokens: 256_000,
                    inputPricePerMillionTokens: 0.05,
                    outputPricePerMillionTokens: 0.2,
                    inputModalities: ["audio"],
                    outputModalities: ["json"],
                    capabilityTags: ["low latency"],
                    status: "available",
                    summary: "Live fast model"
                )
            )
        ])

        let nike = try XCTUnwrap(catalog.first { $0.id == TrustedRouterDefaults.fastModel })
        XCTAssertEqual(nike.displayName, TrustedRouterDefaults.fastModelDisplayName)
        XCTAssertEqual(nike.capabilities.summary, "Live fast model")
        XCTAssertEqual(nike.capabilities.contextWindowTokens, 256_000)
        XCTAssertEqual(nike.capabilities.inputPricePerMillionTokens, 0.05)
        XCTAssertEqual(nike.capabilities.outputPricePerMillionTokens, 0.2)
        XCTAssertEqual(nike.capabilities.inputModalities, ["text", "audio"])
        XCTAssertEqual(nike.capabilities.outputModalities, ["text", "tool call", "json"])
        XCTAssertEqual(
            nike.capabilities.capabilityTags,
            ["fast", "coding", "shell", "file editing", "low latency"]
        )
        XCTAssertEqual(nike.capabilities.status, "available")
    }

    func testModelCatalogStatusLabelsFreshStaleAndFallbackStates() {
        let now = Date(timeIntervalSince1970: 10_000)
        let immediate = ModelCatalogStatus.liveTrustedRouter(fetchedAt: now.addingTimeInterval(-30))
        let fresh = ModelCatalogStatus.liveTrustedRouter(fetchedAt: now.addingTimeInterval(-120))
        let stale = ModelCatalogStatus.liveTrustedRouter(fetchedAt: now.addingTimeInterval(-7_200))
        let publicCatalog = ModelCatalogStatus.publicTrustedRouter(
            fetchedAt: now.addingTimeInterval(-120),
            note: "Authenticated JSON catalog failed."
        )
        let fallback = ModelCatalogStatus.fallbackAfterFailure(
            "  HTTP 500\nprovider down  ",
            fetchedAt: now
        )

        XCTAssertEqual(immediate.statusLabel(now: now), "Live TrustedRouter catalog · just now")
        XCTAssertEqual(fresh.statusLabel(now: now), "Live TrustedRouter catalog · 2m ago")
        XCTAssertEqual(stale.statusLabel(now: now), "Live TrustedRouter catalog · stale 2h ago")
        XCTAssertEqual(publicCatalog.statusLabel(now: now), "Public TrustedRouter catalog · 2m ago")
        XCTAssertEqual(
            publicCatalog.detailLabel(now: now),
            "Loaded the public TrustedRouter model catalog 2m ago. Authenticated JSON catalog failed."
        )
        XCTAssertEqual(fallback.statusLabel(now: now), "Bundled fallback · refresh failed")
        XCTAssertEqual(
            fallback.detailLabel(now: now),
            "The latest TrustedRouter model refresh failed: HTTP 500 provider down"
        )
        XCTAssertEqual(ModelCatalogStatus.bundled.statusLabel(now: now), "Bundled catalog")
    }
}
