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
        XCTAssertTrue(defaultsText.contains("Synth"), "User-facing fallback model branding should stay with TrustedRouter defaults.")
        XCTAssertTrue(defaultsText.contains("normalizedModelCatalog"), "Model catalog normalization should stay with TrustedRouter defaults.")
        XCTAssertFalse(modelsText.contains("public struct ModelInfo"), "General domain models should not own model catalog records.")
        XCTAssertFalse(modelsText.contains("public struct ModelSortKey"), "General domain models should not own model sort records.")
        XCTAssertFalse(modelsText.contains("public enum TrustedRouterDefaults"), "General domain models should not own TrustedRouter defaults.")
        XCTAssertFalse(modelsText.contains("Nike 1.0"), "General domain models should not own model branding copy.")
        XCTAssertFalse(modelsText.contains("Synth"), "General domain models should not own model branding copy.")
    }

    func testSynthBrandingIsPreferredOutsideTrustedRouterAliasBoundary() throws {
        let sourceRoot = Self.packageRoot().appendingPathComponent("Sources")
        let allowedAliasFile = "TrustedRouterDefaults.swift"
        let sourceFiles = try FileManager.default
            .subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }

        let leakingFiles = try sourceFiles.compactMap { relativePath -> String? in
            guard !relativePath.hasSuffix(allowedAliasFile) else { return nil }
            let source = try String(contentsOf: sourceRoot.appendingPathComponent(relativePath), encoding: .utf8)
            return source.contains("Fusion") || source.contains("fusion") ? relativePath : nil
        }

        XCTAssertTrue(
            leakingFiles.isEmpty,
            "Fusion should stay a hidden legacy alias in \(allowedAliasFile); app surfaces should prefer Synth. Leaks: \(leakingFiles.joined(separator: ", "))"
        )
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
            broadSuiteLines.contains("    func testAppConfigLivesOutsideGeneralDomainModels() throws {"),
            "App config architecture gates should stay in ParityModelGateTests."
        )
    }
}
