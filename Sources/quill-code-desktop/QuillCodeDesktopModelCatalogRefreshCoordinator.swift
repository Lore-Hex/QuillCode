import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopModelCatalogRefreshCoordinator {
    private let bootstrap: QuillCodeWorkspaceBootstrap
    private let policy: WorkspaceModelCatalogRefreshPolicy
    private let tickIntervalNanoseconds: UInt64

    init(
        bootstrap: QuillCodeWorkspaceBootstrap,
        policy: WorkspaceModelCatalogRefreshPolicy = WorkspaceModelCatalogRefreshPolicy(),
        tickIntervalNanoseconds: UInt64 = 15 * 60 * 1_000_000_000
    ) {
        self.bootstrap = bootstrap
        self.policy = policy
        self.tickIntervalNanoseconds = tickIntervalNanoseconds
    }

    func startTicker(
        tasks: QuillCodeDesktopTaskCoordinator,
        triggerRefresh: @escaping @MainActor () -> Void
    ) {
        tasks.replace(.modelCatalogRefreshTicker) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                triggerRefresh()
            }
        }
    }

    func refreshIfNeeded(
        on model: QuillCodeWorkspaceModel,
        refresh: @escaping @MainActor () -> Void,
        now: Date = Date()
    ) async {
        guard policy.shouldRefresh(
            status: model.root.modelCatalogStatus,
            hasTrustedRouterAPIKey: bootstrap.hasTrustedRouterAPIKey(),
            now: now
        ) else { return }

        let catalog = await bootstrap.fetchModelCatalog(config: model.root.config)
        model.setModelCatalog(catalog)
        refresh()
    }
}
