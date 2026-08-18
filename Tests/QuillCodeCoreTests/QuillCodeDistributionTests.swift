import XCTest
@testable import QuillCodeCore

final class QuillCodeDistributionTests: XCTestCase {
    func testProductBrandingAndStorageAreEditionSpecific() {
        XCTAssertEqual(QuillCodeDistribution.standard.fullBrandName, "Quill Cowork by TrustedRouter")
        XCTAssertEqual(
            QuillCodeDistribution.confidential.fullBrandName,
            "Confidential Cowork by TrustedRouter"
        )
        XCTAssertEqual(QuillCodeDistribution.standard.applicationHomeDirectoryName, ".quillcode")
        XCTAssertEqual(
            QuillCodeDistribution.confidential.applicationHomeDirectoryName,
            ".confidential-cowork"
        )
        XCTAssertEqual(
            QuillCodeDistribution.standard.secretStorageService,
            "co.lorehex.QuillCowork.secrets"
        )
        XCTAssertEqual(
            QuillCodeDistribution.confidential.secretStorageService,
            "com.trustedrouter.ConfidentialCowork.secrets"
        )
        XCTAssertNotEqual(
            QuillCodeDistribution.standard.bundleIdentifier,
            QuillCodeDistribution.confidential.bundleIdentifier
        )
    }

    func testResolverPrefersEnvironmentOverBundleValue() {
        XCTAssertEqual(
            QuillCodeDistributionResolver.resolve(
                infoDictionaryEdition: "standard",
                environment: [QuillCodeDistributionResolver.environmentKey: " CONFIDENTIAL "]
            ),
            .confidential
        )
        XCTAssertEqual(
            QuillCodeDistributionResolver.resolve(
                infoDictionaryEdition: "confidential",
                environment: [:]
            ),
            .confidential
        )
        XCTAssertEqual(
            QuillCodeDistributionResolver.resolve(
                infoDictionaryEdition: "unknown",
                environment: [:]
            ),
            .standard
        )
    }

    func testConfidentialDistributionRemovesEveryWeakeningOverride() {
        let input = AppConfig(
            defaultModel: TrustedRouterDefaults.fastModel,
            apiBaseURL: "https://untrusted.example/v1",
            developerOverrideEnabled: true,
            favoriteModels: [
                TrustedRouterDefaults.fastModel,
                TrustedRouterDefaults.confidentialModel
            ],
            reviewModel: TrustedRouterDefaults.safetyPrimaryCatalogModel
        )

        let enforced = QuillCodeDistribution.confidential.enforcing(input)

        XCTAssertEqual(enforced.defaultModel, TrustedRouterDefaults.confidentialModel)
        XCTAssertEqual(enforced.reviewModel, TrustedRouterDefaults.confidentialModel)
        XCTAssertEqual(enforced.apiBaseURL, TrustedRouterDefaults.defaultAPIBaseURL)
        XCTAssertEqual(enforced.authMode, .oauth)
        XCTAssertFalse(enforced.developerOverrideEnabled)
        XCTAssertEqual(enforced.favoriteModels, [TrustedRouterDefaults.confidentialModel])
    }

    func testConfidentialDistributionAllowsCatalogModelsOnlyAtConfidentialTier() {
        let confidentialModel = ModelInfo(
            id: "private/secure-model",
            provider: "private",
            displayName: "Secure Model",
            category: "Private",
            capabilities: ModelCapabilities(
                privacyTier: TrustedRouterDefaults.confidentialPrivacyTier
            )
        )
        let ordinaryModel = ModelInfo(
            id: "public/ordinary-model",
            provider: "public",
            displayName: "Ordinary Model",
            category: "Public"
        )
        let catalog = [confidentialModel, ordinaryModel]

        XCTAssertTrue(QuillCodeDistribution.confidential.allowsModel(confidentialModel.id, catalog: catalog))
        XCTAssertFalse(QuillCodeDistribution.confidential.allowsModel(ordinaryModel.id, catalog: catalog))
        XCTAssertEqual(
            QuillCodeDistribution.confidential.enforcedModelID(ordinaryModel.id, catalog: catalog),
            TrustedRouterDefaults.confidentialModel
        )
    }
}
