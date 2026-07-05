import XCTest

final class ParityModelGateTests: QuillCodeParityTestCase {
    func testTrustedRouterModelCatalogLivesOutsideGeneralDomainModels() throws {
        Self.assertLegacyGeneralModelsFileIsRetired()
        let modelsText = try Self.generalDomainModelsText()
        let modelInfoText = try Self.coreSourceText(named: "ModelInfo.swift")
        let defaultsText = try Self.coreSourceText(named: "TrustedRouterDefaults.swift")

        XCTAssertTrue(modelInfoText.contains("public struct ModelInfo"), "Model catalog records should live in a focused core file.")
        XCTAssertTrue(modelInfoText.contains("public struct ModelSortKey"), "Model sort policy inputs should live beside model catalog records.")
        XCTAssertTrue(defaultsText.contains("public enum TrustedRouterDefaults"), "TrustedRouter defaults should live in their own named core file.")
        XCTAssertTrue(defaultsText.contains("Nike 1.0"), "User-facing default model branding should stay with TrustedRouter defaults.")
        ["Zeus 1.0", "Prometheus 1.0", "Socrates 1.0", "Aristotle 1.0", "Plato 1.0"].forEach {
            XCTAssertTrue(defaultsText.contains($0), "\($0) branding should stay with TrustedRouter defaults.")
        }
        XCTAssertTrue(defaultsText.contains("normalizedModelCatalog"), "Model catalog normalization should stay with TrustedRouter defaults.")
        XCTAssertFalse(modelsText.contains("public struct ModelInfo"), "General domain models should not own model catalog records.")
        XCTAssertFalse(modelsText.contains("public struct ModelSortKey"), "General domain models should not own model sort records.")
        XCTAssertFalse(modelsText.contains("public enum TrustedRouterDefaults"), "General domain models should not own TrustedRouter defaults.")
        XCTAssertFalse(modelsText.contains("Nike 1.0"), "General domain models should not own model branding copy.")
        XCTAssertFalse(modelsText.contains("Prometheus 1.0"), "General domain models should not own model branding copy.")
    }

    func testTrustedRouterRecommendedModelsKeepCapabilityTaxonomy() throws {
        let defaultsText = try Self.coreSourceText(named: "TrustedRouterDefaults.swift")

        XCTAssertTrue(
            defaultsText.contains("public static let recommendedCapabilities"),
            "Recommended model capability taxonomy should stay beside TrustedRouter defaults."
        )
        [
            "fastModel: ModelCapabilities",
            "zeusModel: ModelCapabilities",
            "prometheusModel: ModelCapabilities",
            "socratesModel: ModelCapabilities",
            "aristotleModel: ModelCapabilities",
            "platoModel: ModelCapabilities"
        ].forEach {
            XCTAssertTrue(defaultsText.contains($0), "\($0) should keep a bundled capability profile.")
        }
        [
            #""shell""#,
            #""file editing""#,
            #""deep research""#,
            #""coding agent""#,
            #""general agent""#,
            #""OSS""#
        ].forEach {
            XCTAssertTrue(defaultsText.contains($0), "\($0) should remain searchable taxonomy copy.")
        }
        XCTAssertTrue(
            defaultsText.contains("mergeCapabilities"),
            "Live catalog duplicates should merge with, not replace, branded capability taxonomy."
        )
        XCTAssertTrue(
            defaultsText.contains("contextWindowTokens: override.contextWindowTokens ?? base.contextWindowTokens"),
            "Live catalog metadata should backfill concrete capability fields."
        )
        XCTAssertTrue(
            defaultsText.contains("capabilityTags: mergedList(base.capabilityTags, override.capabilityTags)"),
            "Live provider tags should compose with curated branded tags."
        )
    }

    func testRemovedSynthAliasesDoNotReturn() throws {
        let defaultsText = try Self.coreSourceText(named: "TrustedRouterDefaults.swift")
        for removedAlias in ["tr/synth", "/synth", "trustedrouter/synth", "synth-code", "fusion-code"] {
            XCTAssertFalse(defaultsText.contains(#""\#(removedAlias)""#), "\(removedAlias) should not be a hidden model alias.")
        }
    }

    func testAppConfigLivesOutsideGeneralDomainModels() throws {
        Self.assertLegacyGeneralModelsFileIsRetired()
        let modelsText = try Self.generalDomainModelsText()
        let configText = try Self.coreSourceText(named: "AppConfig.swift")

        XCTAssertTrue(configText.contains("public struct AppConfig"), "App config should live in a focused core file.")
        XCTAssertTrue(configText.contains("public enum TrustedRouterAuthMode"), "TrustedRouter auth mode belongs with app config.")
        XCTAssertTrue(configText.contains("public struct TrustedRouterAccountProfile"), "Signed-in account metadata belongs with app config.")
        XCTAssertTrue(configText.contains("normalizedModelIDs"), "Favorite/default model normalization should stay with app config.")
        XCTAssertTrue(configText.contains("developerOverrideEnabled ? .developerOverride"), "Developer override compatibility should stay with app config.")
        XCTAssertFalse(modelsText.contains("public struct AppConfig"), "General domain models should not own app configuration.")
        XCTAssertFalse(modelsText.contains("public enum TrustedRouterAuthMode"), "General domain models should not own TrustedRouter auth mode.")
        XCTAssertFalse(modelsText.contains("public struct TrustedRouterAccountProfile"), "General domain models should not own account profile metadata.")
        XCTAssertFalse(modelsText.contains("developerOverrideEnabled ? .developerOverride"), "General domain models should not own settings compatibility rules.")
    }

    func testModelArchitectureGatesStayOutOfBroadSuite() throws {
        let broadSuiteURL = Self.packageRoot()
            .appendingPathComponent("Tests/QuillCodeParityTests/ParityGateTests.swift")
        let broadSuiteText = try String(contentsOf: broadSuiteURL, encoding: .utf8)
        let broadSuiteLines = Set(broadSuiteText.components(separatedBy: .newlines))

        XCTAssertFalse(
            broadSuiteLines.contains("    func testTrustedRouterModelCatalogLivesOutsideGeneralDomainModels() throws {"),
            "TrustedRouter model architecture gates should stay in ParityModelGateTests."
        )
        XCTAssertFalse(
            broadSuiteLines.contains("    func testTrustedRouterRecommendedModelsKeepCapabilityTaxonomy() throws {"),
            "TrustedRouter capability taxonomy gates should stay in ParityModelGateTests."
        )
        XCTAssertFalse(
            broadSuiteLines.contains("    func testAppConfigLivesOutsideGeneralDomainModels() throws {"),
            "App config architecture gates should stay in ParityModelGateTests."
        )
    }
}
