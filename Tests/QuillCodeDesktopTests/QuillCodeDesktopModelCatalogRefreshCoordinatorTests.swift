import XCTest
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopModelCatalogRefreshCoordinatorTests: XCTestCase {
    func testProactiveRefreshAppliesCatalogOnceThenSkipsFreshState() async throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let recorder = CatalogFetchRecorder()
        let bootstrap = QuillCodeWorkspaceBootstrap(
            paths: paths,
            runtimeFactory: QuillCodeRuntimeFactory(
                paths: paths,
                environment: ["TRUSTEDROUTER_API_KEY": "sk-test"]
            ),
            modelCatalogFetcher: { config in
                await recorder.fetch(config: config)
            }
        )
        let coordinator = QuillCodeDesktopModelCatalogRefreshCoordinator(
            bootstrap: bootstrap,
            policy: WorkspaceModelCatalogRefreshPolicy(staleAfter: 60, retryAfterFailure: 30)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(apiBaseURL: "https://api.trustedrouter.test/v1"),
            modelCatalogStatus: .bundled
        ))
        var refreshCount = 0

        await coordinator.refreshIfNeeded(on: model, refresh: { refreshCount += 1 })

        let firstFetchCount = await recorder.fetchCount()
        XCTAssertEqual(firstFetchCount, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(model.root.modelCatalogStatus.source, .liveTrustedRouter)
        XCTAssertTrue(model.root.modelCatalog.contains { $0.id == "acme/proactive" })

        await coordinator.refreshIfNeeded(on: model, refresh: { refreshCount += 1 })

        let secondFetchCount = await recorder.fetchCount()
        XCTAssertEqual(secondFetchCount, 1)
        XCTAssertEqual(refreshCount, 1)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeDesktopCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private actor CatalogFetchRecorder {
    private(set) var count = 0

    func fetch(config: AppConfig) -> TrustedRouterModelCatalog {
        count += 1
        return TrustedRouterModelCatalog(
            models: [
                ModelInfo(
                    id: "acme/proactive",
                    provider: "acme",
                    displayName: "Proactive",
                    category: "Testing"
                )
            ],
            status: .liveTrustedRouter(fetchedAt: Date())
        )
    }

    func fetchCount() -> Int {
        count
    }
}
