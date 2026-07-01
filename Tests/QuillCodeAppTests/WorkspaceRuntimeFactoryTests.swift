import XCTest
import QuillCodeCore
import QuillCodePersistence
@testable import QuillCodeApp

final class WorkspaceRuntimeFactoryTests: XCTestCase {
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

    func testModelCatalogFallsBackWithoutKey() async throws {
        let paths = QuillCodePaths(home: try makeQuillCodeTestDirectory())
        try paths.ensure()

        let catalog = await QuillCodeRuntimeFactory(paths: paths, environment: [:])
            .fetchModelCatalog(config: AppConfig())

        XCTAssertEqual(catalog.defaultModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(catalog.status.source, .bundled)
        XCTAssertTrue(catalog.models.contains { $0.id == "trustedrouter/fast" })
        XCTAssertTrue(catalog.models.contains { $0.id == TrustedRouterDefaults.synthModel })
        XCTAssertTrue(catalog.models.contains { $0.id == "z-ai/glm-5.2" })
    }
}
