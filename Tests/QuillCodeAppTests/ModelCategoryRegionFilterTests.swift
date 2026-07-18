import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ModelCategoryRegionFilterTests: XCTestCase {
    func testRegionOnlyTermsAreRecognizedInEveryAdvertisedSpelling() {
        for (token, expected) in [
            ("us-only", "us"), ("usa-only", "us"), ("usonly", "us"),
            ("eu-only", "eu"), ("europe-only", "eu"), ("euonly", "eu"),
            ("cn-only", "cn"), ("china-only", "cn"), ("chinaonly", "cn")
        ] {
            var terms = [token]
            XCTAssertEqual(
                ModelCategorySearchFilter.extractRegionOnlyConstraint(from: &terms),
                expected,
                token
            )
            XCTAssertTrue(terms.isEmpty, "the constraint token must not remain a text term: \(token)")
        }

        // Non-region tokens pass through untouched — "only" alone, or an unknown region.
        for token in ["only", "us", "mars-only", "zeusonly"] {
            var terms = [token]
            XCTAssertNil(ModelCategorySearchFilter.extractRegionOnlyConstraint(from: &terms), token)
            XCTAssertEqual(terms, [token])
        }

        // Multiple region tokens: the FIRST wins and ALL are consumed — a leftover "eu-only" text
        // term would poison the haystack match and guarantee empty results.
        var multiple = ["us-only", "nike", "eu-only"]
        XCTAssertEqual(ModelCategorySearchFilter.extractRegionOnlyConstraint(from: &multiple), "us")
        XCTAssertEqual(multiple, ["nike"])
    }

    func testRegionOnlyEnforcementFailsClosedAndRequiresExclusivity() {
        XCTAssertTrue(ModelCategorySearchFilter.isRegionOnly(option(regions: ["us"]), region: "us"))
        XCTAssertFalse(
            ModelCategorySearchFilter.isRegionOnly(option(regions: ["us", "eu"]), region: "us"),
            "a multi-region model is NOT us-only — enforcement means every route stays inside"
        )
        XCTAssertFalse(
            ModelCategorySearchFilter.isRegionOnly(option(regions: []), region: "us"),
            "unknown residency must fail closed, never count as everywhere"
        )
    }

    func testFilterAppliesRegionConstraintAloneAndCombinedWithText() {
        let categories = [
            ModelCategorySurface(category: "Recommended", models: [
                option(id: "trustedrouter/fast", displayName: "Nike 1.0", regions: ["us"]),
                option(id: "trustedrouter/fusion", displayName: "Prometheus 1.0", regions: ["us", "eu"]),
                option(id: "trustedrouter/plato", displayName: "Plato 1.0", regions: ["eu"])
            ]),
            ModelCategorySurface(category: "Safety", models: [
                option(id: "z-ai/glm-5.2", displayName: "GLM 5.2", regions: ["cn"]),
                option(id: "moonshotai/kimi-k2.6", displayName: "Kimi K2.6", regions: [])
            ])
        ]

        let usOnly = ModelCategorySearchFilter.filter(categories, matching: "us-only")
        XCTAssertEqual(usOnly.flatMap { $0.models.map(\.id) }, ["trustedrouter/fast"])

        let euOnly = ModelCategorySearchFilter.filter(categories, matching: "eu-only")
        XCTAssertEqual(euOnly.flatMap { $0.models.map(\.id) }, ["trustedrouter/plato"])

        let chinaOnly = ModelCategorySearchFilter.filter(categories, matching: "china-only")
        XCTAssertEqual(chinaOnly.flatMap { $0.models.map(\.id) }, ["z-ai/glm-5.2"])

        // Combined with a text term: the region constrains, the text still matches normally.
        let combined = ModelCategorySearchFilter.filter(categories, matching: "us-only nike")
        XCTAssertEqual(combined.flatMap { $0.models.map(\.id) }, ["trustedrouter/fast"])
        let combinedMiss = ModelCategorySearchFilter.filter(categories, matching: "us-only plato")
        XCTAssertTrue(combinedMiss.isEmpty, "text and region constraints must BOTH hold")
    }

    func testPlainRegionTextStillMatchesViaTheRegionMetadataRow() {
        let categories = [
            ModelCategorySurface(category: "Safety", models: [
                option(id: "z-ai/glm-5.2", displayName: "GLM 5.2", regions: ["cn"])
            ])
        ]
        // Without "-only" the token is ordinary text; the Region row ("CN") is in the haystack.
        let plain = ModelCategorySearchFilter.filter(categories, matching: "cn")
        XCTAssertEqual(plain.flatMap { $0.models.map(\.id) }, ["z-ai/glm-5.2"])
    }

    func testRegionsNormalizeSynonymsAndDeduplicate() {
        XCTAssertEqual(
            ModelCapabilities.normalizedRegions(["USA", "United States", "Europe", "china", "CN", "apac"]),
            ["us", "eu", "cn", "apac"]
        )
    }

    private func option(
        id: String = "trustedrouter/fast",
        displayName: String = "Nike 1.0",
        regions: [String]
    ) -> ModelOptionSurface {
        ModelOptionSurface(
            model: ModelInfo(
                id: id,
                provider: "trustedrouter",
                displayName: displayName,
                category: "Recommended",
                capabilities: ModelCapabilities(regions: regions)
            ),
            selectedModelID: "trustedrouter/fast"
        )
    }
}
