import Foundation
import QuillCodeApp
import QuillCodeCore

extension QuillCodeDesktopController {
    /// Wires the agent's `host.browser.*` calls to the live visible-session executor. Kept out of
    /// the core controller file so that file stays focused on published state / bootstrap / refresh.
    ///
    /// `model` is captured weakly: the closure is stored ON the model, so a strong capture would
    /// retain it forever. The workspace root arrives per call from the agent session. The navigation
    /// context touches @MainActor state, so it is built on the main actor rather than in the
    /// nonisolated closure body.
    func installVisibleBrowserToolOverride(on model: QuillCodeWorkspaceModel) {
        let browserCoordinator = self.browserCoordinator
        model.visibleBrowserToolOverride = { [weak self, weak model] call, workspaceRoot in
            let context: QuillCodeDesktopVisibleBrowserToolExecutor.BrowserNavigationContext? =
                await MainActor.run {
                    guard let model else { return nil }
                    return QuillCodeDesktopVisibleBrowserToolExecutor.BrowserNavigationContext(
                        model: model,
                        workspaceRoot: workspaceRoot,
                        refresh: { [weak self] in self?.refresh() }
                    )
                }
            return await QuillCodeDesktopVisibleBrowserToolExecutor.execute(
                call,
                browserCoordinator: browserCoordinator,
                navigationContext: context
            )
        }
    }
}
