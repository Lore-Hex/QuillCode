import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopTrustedRouterCreditsCoordinatorTests: XCTestCase {
    func testRefreshPublishesEagerAndCurrentStatesThenSkipsFreshBalance() async throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let fetchedAt = Date(timeIntervalSince1970: 100)
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 8.5,
            currency: "USD",
            fetchedAt: fetchedAt
        ))
        let recorder = CreditsFetchRecorder(results: [.success(snapshot)])
        let coordinator = QuillCodeDesktopTrustedRouterCreditsCoordinator(
            bootstrap: bootstrap(paths: paths, recorder: recorder),
            policy: WorkspaceTrustedRouterCreditsRefreshPolicy(staleAfter: 60, retryAfterFailure: 30)
        )
        let model = QuillCodeWorkspaceModel()
        var phases: [TrustedRouterCreditsPhase] = []

        await coordinator.refresh(
            on: model,
            refreshSurface: { phases.append(model.root.trustedRouterCredits.phase) },
            now: fetchedAt
        )

        XCTAssertEqual(phases, [.refreshing, .current])
        XCTAssertEqual(model.root.trustedRouterCredits.snapshot, snapshot)
        let firstFetchCount = await recorder.fetchCount()
        XCTAssertEqual(firstFetchCount, 1)

        await coordinator.refresh(
            on: model,
            refreshSurface: { phases.append(model.root.trustedRouterCredits.phase) },
            now: fetchedAt.addingTimeInterval(59)
        )

        let secondFetchCount = await recorder.fetchCount()
        XCTAssertEqual(secondFetchCount, 1)
        XCTAssertEqual(phases, [.refreshing, .current])
    }

    func testFailedForcedRefreshRetainsLastKnownBalanceAsStale() async throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 4,
            currency: "USD",
            fetchedAt: Date(timeIntervalSince1970: 100)
        ))
        let failureDate = Date(timeIntervalSince1970: 200)
        let recorder = CreditsFetchRecorder(results: [
            .failure(attemptedAt: failureDate, message: "Network unavailable.")
        ])
        let coordinator = QuillCodeDesktopTrustedRouterCreditsCoordinator(
            bootstrap: bootstrap(paths: paths, recorder: recorder)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            trustedRouterCredits: .current(snapshot)
        ))

        await coordinator.refresh(
            on: model,
            force: true,
            refreshSurface: {},
            now: failureDate
        )

        XCTAssertEqual(model.root.trustedRouterCredits.phase, .stale)
        XCTAssertEqual(model.root.trustedRouterCredits.snapshot, snapshot)
        XCTAssertEqual(model.root.trustedRouterCredits.failureMessage, "Network unavailable.")
    }

    func testMissingCredentialClearsBalanceWithoutNetworkRequest() async throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(balance: 4, currency: "USD"))
        let recorder = CreditsFetchRecorder(results: [])
        let bootstrap = QuillCodeWorkspaceBootstrap(
            paths: paths,
            runtimeFactory: QuillCodeRuntimeFactory(
                paths: paths,
                environment: [
                    "QUILLCODE_API_KEY_FILE": paths.home.appendingPathComponent("missing.key").path
                ]
            ),
            accountCreditsFetcher: { config in await recorder.fetch(config: config) }
        )
        let coordinator = QuillCodeDesktopTrustedRouterCreditsCoordinator(bootstrap: bootstrap)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            trustedRouterCredits: .current(snapshot)
        ))
        var refreshCount = 0

        await coordinator.refresh(on: model, refreshSurface: { refreshCount += 1 })

        XCTAssertEqual(model.root.trustedRouterCredits, .unavailable)
        XCTAssertEqual(refreshCount, 1)
        let fetchCount = await recorder.fetchCount()
        XCTAssertEqual(fetchCount, 0)
    }

    func testCancelledRefreshRestoresPreviousBalanceAndIgnoresLateResult() async throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let previousSnapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 4,
            currency: "USD",
            fetchedAt: Date(timeIntervalSince1970: 100)
        ))
        let lateSnapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 999,
            currency: "USD",
            fetchedAt: Date(timeIntervalSince1970: 200)
        ))
        let deferredFetch = DeferredCreditsFetch()
        let bootstrap = QuillCodeWorkspaceBootstrap(
            paths: paths,
            runtimeFactory: QuillCodeRuntimeFactory(
                paths: paths,
                environment: ["TRUSTEDROUTER_API_KEY": "sk-test"]
            ),
            accountCreditsFetcher: { config in await deferredFetch.fetch(config: config) }
        )
        let coordinator = QuillCodeDesktopTrustedRouterCreditsCoordinator(bootstrap: bootstrap)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            trustedRouterCredits: .current(previousSnapshot)
        ))
        let refreshTask = Task { @MainActor in
            await coordinator.refresh(on: model, force: true, refreshSurface: {})
        }

        await deferredFetch.waitUntilStarted()
        XCTAssertEqual(model.root.trustedRouterCredits.phase, .refreshing)
        refreshTask.cancel()
        await deferredFetch.resolve(.success(lateSnapshot))
        await refreshTask.value

        XCTAssertEqual(model.root.trustedRouterCredits, .current(previousSnapshot))
    }

    private func bootstrap(
        paths: QuillCodePaths,
        recorder: CreditsFetchRecorder
    ) -> QuillCodeWorkspaceBootstrap {
        QuillCodeWorkspaceBootstrap(
            paths: paths,
            runtimeFactory: QuillCodeRuntimeFactory(
                paths: paths,
                environment: ["TRUSTEDROUTER_API_KEY": "sk-test"]
            ),
            accountCreditsFetcher: { config in await recorder.fetch(config: config) }
        )
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeDesktopCreditsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private actor CreditsFetchRecorder {
    private var results: [TrustedRouterCreditsRefreshResult]
    private var count = 0

    init(results: [TrustedRouterCreditsRefreshResult]) {
        self.results = results
    }

    func fetch(config: AppConfig) -> TrustedRouterCreditsRefreshResult {
        count += 1
        guard !results.isEmpty else { return .unavailable }
        return results.removeFirst()
    }

    func fetchCount() -> Int { count }
}

private actor DeferredCreditsFetch {
    private var continuation: CheckedContinuation<TrustedRouterCreditsRefreshResult, Never>?

    func fetch(config: AppConfig) async -> TrustedRouterCreditsRefreshResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resolve(_ result: TrustedRouterCreditsRefreshResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
