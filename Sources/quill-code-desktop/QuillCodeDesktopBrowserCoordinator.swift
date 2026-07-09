import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopBrowserCoordinator {
    private let pageFetcher: any BrowserPageFetching
    private let liveDOMCapturer: (any BrowserLiveDOMCapturing)?
    private let sessionPresenter: any DesktopBrowserSessionPresenting

    init(
        pageFetcher: any BrowserPageFetching,
        liveDOMCapturer: (any BrowserLiveDOMCapturing)?,
        sessionPresenter: any DesktopBrowserSessionPresenting
    ) {
        self.pageFetcher = pageFetcher
        self.liveDOMCapturer = liveDOMCapturer
        self.sessionPresenter = sessionPresenter
    }

    func installSessionUpdateHandler(
        model: QuillCodeWorkspaceModel,
        refresh: @escaping @MainActor () -> Void
    ) {
        sessionPresenter.onSessionUpdate = { update in
            guard model.applyBrowserSessionUpdate(update) else { return }
            refresh()
        }
    }

    func openPreview(
        model: QuillCodeWorkspaceModel,
        addressDraft: String,
        workspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        model.setBrowserAddressDraft(addressDraft)
        _ = model.openBrowserPreview(workspaceRoot: activeWorkspaceRoot(for: model, fallback: workspaceRoot))
        refresh()
        syncOpenSession(model: model)

        tasks.replace(.browserPreview) {
            _ = await model.refreshBrowserSnapshot(pageFetcher: pageFetcher)
            if let liveDOMCapturer {
                _ = await model.refreshRenderedBrowserSnapshot(capturer: liveDOMCapturer)
            }
        } onFinish: {
            syncOpenSession(model: model)
            refresh()
        }
    }

    func openSession(
        model: QuillCodeWorkspaceModel,
        addressDraft: String,
        workspaceRoot: URL,
        refresh: @escaping @MainActor () -> Void
    ) {
        let root = activeWorkspaceRoot(for: model, fallback: workspaceRoot)
        let targetAddress = sessionTargetAddress(
            addressDraft: addressDraft,
            fallbackAddress: model.browser.currentURL ?? model.browser.addressDraft
        )

        guard let url = WorkspaceBrowserLocationResolver(workspaceRoot: root).resolve(targetAddress) else {
            model.setBrowserAddressDraft(targetAddress)
            _ = model.openBrowserPreview(workspaceRoot: root)
            refresh()
            return
        }

        model.setBrowserAddressDraft(url.absoluteString)
        guard model.openBrowserPreview(workspaceRoot: root) else {
            refresh()
            return
        }
        let snapshot = BrowserSessionSyncSnapshot(browser: model.browser)
        guard !snapshot.isEmpty else {
            refresh()
            return
        }
        sessionPresenter.presentSession(snapshot)
        refresh()
    }

    func syncOpenSession(model: QuillCodeWorkspaceModel) {
        let snapshot = BrowserSessionSyncSnapshot(browser: model.browser)
        guard !snapshot.isEmpty else { return }
        sessionPresenter.syncSession(snapshot)
    }

    func goBackOpenSession(model: QuillCodeWorkspaceModel) {
        let snapshot = BrowserSessionSyncSnapshot(browser: model.browser)
        guard !snapshot.isEmpty else { return }
        sessionPresenter.goBackSession(fallback: snapshot)
    }

    func goForwardOpenSession(model: QuillCodeWorkspaceModel) {
        let snapshot = BrowserSessionSyncSnapshot(browser: model.browser)
        guard !snapshot.isEmpty else { return }
        sessionPresenter.goForwardSession(fallback: snapshot)
    }

    func reloadOpenSession() {
        sessionPresenter.reloadSession()
    }

    func evaluateJavaScriptInOpenSession(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        try await sessionPresenter.evaluateJavaScriptInSelectedTab(source)
    }

    func captureLiveDOMSnapshotInOpenSession() async throws -> BrowserLiveDOMSnapshot {
        try await sessionPresenter.captureLiveDOMSnapshotInSelectedTab()
    }

    private func activeWorkspaceRoot(
        for model: QuillCodeWorkspaceModel,
        fallback workspaceRoot: URL
    ) -> URL {
        model.activeWorkspaceRoot ?? workspaceRoot
    }

    private func sessionTargetAddress(addressDraft: String, fallbackAddress: String) -> String {
        let rawAddress = addressDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawAddress.isEmpty ? fallbackAddress : rawAddress
    }
}
