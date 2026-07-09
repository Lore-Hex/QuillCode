import Foundation
import QuillCodeApp
import QuillCodeCore

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

    func inspectLiveDOMSnapshotInOpenSession() async -> ToolResult? {
        do {
            let snapshot = try await captureLiveDOMSnapshotInOpenSession()
            return ToolResult(
                ok: true,
                stdout: (try? JSONHelpers.encodePretty(inspectionOutput(from: snapshot))) ?? "{}"
            )
        } catch DesktopBrowserSessionScriptError.noOpenSession,
                DesktopBrowserSessionScriptError.noSelectedTab {
            return nil
        } catch {
            return nil
        }
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

    private func inspectionOutput(from snapshot: BrowserLiveDOMSnapshot) -> BrowserInspectionToolOutput {
        let url = snapshot.finalURL
        let title = nonEmpty(snapshot.title) ?? BrowserInspectorTitle.title(for: url)
        var details = baseInspectionDetails(for: snapshot)
        if let viewport = nonEmpty(snapshot.viewportDescription) {
            details.append("Viewport: \(viewport)")
        }
        return BrowserInspectionToolOutput(
            url: url.absoluteString,
            title: title,
            status: "Live visible browser session",
            sourceLabel: sourceLabel(for: url),
            inspectionDepth: .liveDOMSnapshot,
            summary: "Captured a live DOM snapshot from the visible browser session.",
            details: details,
            outline: Array(snapshot.outline.prefix(Self.outlineLimit)),
            textSnippet: snapshot.visibleText.map(Self.textSnippet)
        )
    }

    private func baseInspectionDetails(for snapshot: BrowserLiveDOMSnapshot) -> [String] {
        let url = snapshot.finalURL
        let host = url.host ?? url.absoluteString
        let path = url.path.isEmpty ? "/" : url.path
        return [
            "Host: \(host)",
            "Scheme: \((url.scheme ?? "https").uppercased())",
            "Path: \(path)"
        ]
    }

    private func sourceLabel(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return ["localhost", "127.0.0.1", "::1"].contains(host) ? "Local web app" : "Web page"
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let outlineLimit = 24
    private static let textSnippetLimit = 800

    private static func textSnippet(_ text: String) -> String {
        let compact = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard compact.count > textSnippetLimit else { return compact }
        return String(compact.prefix(textSnippetLimit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private enum BrowserInspectorTitle {
    static func title(for url: URL) -> String {
        if url.isFileURL {
            return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        }
        return url.host ?? url.absoluteString
    }
}
