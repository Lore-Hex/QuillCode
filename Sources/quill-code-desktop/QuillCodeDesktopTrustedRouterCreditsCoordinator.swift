import Foundation
import QuillCodeApp
import QuillCodeCore

@MainActor
final class QuillCodeDesktopTrustedRouterCreditsCoordinator {
    private let bootstrap: QuillCodeWorkspaceBootstrap
    private let policy: WorkspaceTrustedRouterCreditsRefreshPolicy
    private let tickIntervalNanoseconds: UInt64
    private var currentAttemptID: UUID?

    init(
        bootstrap: QuillCodeWorkspaceBootstrap,
        policy: WorkspaceTrustedRouterCreditsRefreshPolicy = WorkspaceTrustedRouterCreditsRefreshPolicy(),
        tickIntervalNanoseconds: UInt64 = 5 * 60 * 1_000_000_000
    ) {
        self.bootstrap = bootstrap
        self.policy = policy
        self.tickIntervalNanoseconds = tickIntervalNanoseconds
    }

    func startTicker(
        tasks: QuillCodeDesktopTaskCoordinator,
        triggerRefresh: @escaping @MainActor () -> Void
    ) {
        tasks.replace(.trustedRouterCreditsRefreshTicker) {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self.tickIntervalNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                triggerRefresh()
            }
        }
    }

    func refresh(
        on model: QuillCodeWorkspaceModel,
        force: Bool = false,
        refreshSurface: @escaping @MainActor () -> Void,
        now: Date = Date()
    ) async {
        guard bootstrap.hasTrustedRouterAPIKey() else {
            currentAttemptID = nil
            guard model.root.trustedRouterCredits != .unavailable else { return }
            model.setTrustedRouterCredits(.unavailable)
            refreshSurface()
            return
        }
        guard force || policy.shouldRefresh(
            state: model.root.trustedRouterCredits,
            hasTrustedRouterAPIKey: true,
            now: now
        ) else { return }

        let attemptID = UUID()
        currentAttemptID = attemptID
        let previous = model.root.trustedRouterCredits
        model.setTrustedRouterCredits(.refreshing(previous: previous, attemptedAt: now))
        refreshSurface()

        let result = await bootstrap.fetchTrustedRouterCredits(config: model.root.config)
        guard currentAttemptID == attemptID else { return }
        if Task.isCancelled {
            currentAttemptID = nil
            model.setTrustedRouterCredits(previous)
            refreshSurface()
            return
        }
        currentAttemptID = nil
        model.applyTrustedRouterCreditsRefresh(result, previous: previous)
        refreshSurface()
    }
}
