import Foundation
import QuillCodeApp

#if canImport(AppKit) && canImport(WebKit)
import AppKit
import WebKit

@MainActor
final class DesktopBrowserSessionWindowController: NSWindowController,
    NSWindowDelegate,
    NSTabViewDelegate,
    WKNavigationDelegate
{
    private struct SessionTab {
        var snapshot: BrowserSessionTabSnapshot
        var item: NSTabViewItem
        var webView: WKWebView
        var activeNavigation: WKNavigation?
    }

    var onClose: (() -> Void)?
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?

    private let tabView: NSTabView
    private var tabs: [UUID: SessionTab] = [:]
    private let navigationWaiters: DesktopBrowserNavigationWaitRegistry

    init(snapshot: BrowserSessionSyncSnapshot) {
        self.tabView = NSTabView()
        self.navigationWaiters = DesktopBrowserNavigationWaitRegistry(
            timeoutNanoseconds: UInt64(Self.navigationTimeoutSeconds * 1_000_000_000)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(QuillCodeProduct.displayName) Browser Session"
        window.contentView = tabView
        window.center()

        super.init(window: window)

        window.delegate = self
        tabView.delegate = self
        sync(snapshot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        navigationWaiters.finishAll(error: DesktopBrowserSessionScriptError.noOpenSession)
        tabs.values.forEach {
            $0.webView.stopLoading()
            $0.webView.navigationDelegate = nil
        }
        tabs.removeAll(keepingCapacity: false)
        onSessionUpdate = nil
        onClose?()
        onClose = nil
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        updateWindowTitle()
        emitSessionUpdate()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        guard let id = tabID(for: webView), let navigation else { return }
        if let activeNavigation = tabs[id]?.activeNavigation,
           activeNavigation !== navigation {
            navigationWaiters.finish(
                tabID: id,
                error: DesktopBrowserSessionScriptError.navigationSuperseded
            )
        }
        storeActiveNavigation(navigation, for: id, webView: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
        guard let id = tabID(for: webView),
              finishActiveNavigation(for: id, navigation: navigation)
        else {
            return
        }
        navigationWaiters.resolve(
            for: id,
            navigation: navigation,
            error: DesktopBrowserSessionScriptError.navigationFailed(error.localizedDescription)
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        guard let id = tabID(for: webView),
              finishActiveNavigation(for: id, navigation: navigation)
        else {
            return
        }
        navigationWaiters.resolve(
            for: id,
            navigation: navigation,
            error: DesktopBrowserSessionScriptError.navigationFailed(error.localizedDescription)
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard let id = tabID(for: webView),
              finishActiveNavigation(for: id, navigation: navigation),
              var tab = tabs[id]
        else {
            return
        }
        navigationWaiters.resolve(for: id, navigation: navigation, error: nil)
        let title = nonEmpty(webView.title) ?? tab.snapshot.title
        if let url = webView.url {
            tab.snapshot = BrowserSessionTabSnapshot(
                id: tab.snapshot.id,
                title: title,
                url: url,
                isActive: tab.snapshot.isActive
            )
        }
        tab.snapshot.title = title
        tab.item.label = title
        tabs[id] = tab
        updateWindowTitle()
        emitSessionUpdate()
        emitRenderedSessionUpdate(for: id, webView: webView)
    }

    func sync(_ snapshot: BrowserSessionSyncSnapshot) {
        removeTabs(excluding: Set(snapshot.tabs.map(\.id)))
        for tab in snapshot.tabs {
            sync(tab)
        }
        reorderTabs(snapshot.tabs.map(\.id))
        selectActiveTab(snapshot.activeTabID)
        updateWindowTitle()
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reloadSelectedTab() {
        guard let selectedID = selectedTabID(),
              let tab = tabs[selectedID]
        else {
            return
        }
        beginUserNavigation(tab.webView.reload(), for: selectedID, webView: tab.webView)
    }

    func goBackSelectedTab(fallback snapshot: BrowserSessionSyncSnapshot) {
        guard let selectedID = selectedTabID(),
              let tab = tabs[selectedID]
        else {
            return
        }
        guard tab.webView.canGoBack else {
            sync(snapshot)
            return
        }
        beginUserNavigation(tab.webView.goBack(), for: selectedID, webView: tab.webView)
    }

    func goForwardSelectedTab(fallback snapshot: BrowserSessionSyncSnapshot) {
        guard let selectedID = selectedTabID(),
              let tab = tabs[selectedID]
        else {
            return
        }
        guard tab.webView.canGoForward else {
            sync(snapshot)
            return
        }
        beginUserNavigation(tab.webView.goForward(), for: selectedID, webView: tab.webView)
    }

    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { throw DesktopBrowserSessionScriptError.emptySource }
        guard let selectedID = selectedTabID(),
              let tab = tabs[selectedID]
        else {
            throw DesktopBrowserSessionScriptError.noSelectedTab
        }
        let value = try await tab.webView.evaluateJavaScript(trimmedSource)
        emitSessionUpdate()
        emitRenderedSessionUpdate(for: selectedID, webView: tab.webView)
        return DesktopBrowserSessionScriptResult(
            title: nonEmpty(tab.webView.title) ?? tab.snapshot.title,
            url: tab.webView.url ?? tab.snapshot.url,
            valueDescription: DesktopBrowserSessionValueDescriber.boundedDescription(value)
        )
    }

    /// How long to wait for a navigation before giving up on `didFinish` and capturing whatever
    /// has rendered. A page that never fires `didFinish` (long-polling, a stalled subresource,
    /// a hung analytics beacon) must never wedge the agent loop — a partial DOM beats a hang.
    static let navigationTimeoutSeconds: Double = 25

    func navigateSelectedTab(to url: URL) async throws -> BrowserLiveDOMSnapshot {
        guard let selectedID = selectedTabID(),
              let tab = tabs[selectedID]
        else {
            throw DesktopBrowserSessionScriptError.noSelectedTab
        }

        // Already on this exact URL: the page is loaded, so capture it rather than forcing a
        // reload (a reload would also lose any state the user or a prior step established).
        if tab.webView.url?.absoluteString != url.absoluteString {
            try await navigationWaiters.wait(for: selectedID) {
                let navigation = navigate(tab.webView, to: url)
                storeActiveNavigation(navigation, for: selectedID, webView: tab.webView)
                return navigation
            }
        } else if tab.webView.isLoading {
            try await navigationWaiters.wait(for: selectedID) {
                tab.activeNavigation
            }
        }

        return try await captureLiveDOMSnapshot(in: selectedID)
    }

    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot {
        guard let selectedID = selectedTabID() else {
            throw DesktopBrowserSessionScriptError.noSelectedTab
        }
        return try await captureLiveDOMSnapshot(in: selectedID)
    }

    private func captureLiveDOMSnapshot(in tabID: UUID) async throws -> BrowserLiveDOMSnapshot {
        guard let tab = tabs[tabID] else { throw DesktopBrowserSessionScriptError.noSelectedTab }
        let webView = tab.webView
        let snapshot = try await DesktopBrowserLiveDOMSnapshotExtractor.snapshot(
            from: webView,
            fallbackURL: tab.snapshot.url
        )
        guard let currentTab = tabs[tabID], currentTab.webView === webView else {
            throw DesktopBrowserSessionScriptError.noSelectedTab
        }
        emitSessionUpdate(liveDOMSnapshots: [tabID: snapshot])
        return snapshot
    }

    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult {
        let selector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else { throw DesktopBrowserSessionActionError.emptySelector }
        return try await runActionInSelectedTab(
            source: try DesktopBrowserSessionJavaScript.clickScript(selector: selector)
        )
    }

    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult {
        let selector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selector.isEmpty else { throw DesktopBrowserSessionActionError.emptySelector }
        guard !text.isEmpty else { throw DesktopBrowserSessionActionError.emptyText }
        return try await runActionInSelectedTab(
            source: try DesktopBrowserSessionJavaScript.typeScript(
                selector: selector,
                text: text,
                submit: submit
            )
        )
    }

    private func runActionInSelectedTab(source: String) async throws -> DesktopBrowserSessionActionResult {
        guard let selectedID = selectedTabID(),
              let tab = tabs[selectedID]
        else {
            throw DesktopBrowserSessionActionError.noSelectedTab
        }
        let value = try await tab.webView.evaluateJavaScript(source)
        guard let payload = value as? String,
              let data = payload.data(using: .utf8)
        else {
            throw DesktopBrowserSessionActionError.decodingFailed(String(describing: value))
        }
        let result = try JSONDecoder().decode(DesktopBrowserSessionActionResult.self, from: data)
        guard result.ok else {
            throw DesktopBrowserSessionActionError.actionFailed(result.error ?? result.summary)
        }
        emitSessionUpdate()
        emitRenderedSessionUpdate(for: selectedID, webView: tab.webView)
        return result
    }

    private func sync(_ snapshot: BrowserSessionTabSnapshot) {
        if var tab = tabs[snapshot.id] {
            tab.snapshot = snapshot
            tab.item.label = snapshot.title
            if let navigation = navigate(tab.webView, to: snapshot.url) {
                navigationWaiters.finish(
                    tabID: snapshot.id,
                    error: DesktopBrowserSessionScriptError.navigationSuperseded
                )
                tab.activeNavigation = navigation
            }
            tabs[snapshot.id] = tab
            return
        }

        let webView = WKWebView(frame: .zero, configuration: Self.webViewConfiguration())
        webView.navigationDelegate = self
        let item = NSTabViewItem(identifier: snapshot.id.uuidString)
        item.label = snapshot.title
        item.view = webView
        tabView.addTabViewItem(item)
        tabs[snapshot.id] = SessionTab(
            snapshot: snapshot,
            item: item,
            webView: webView,
            activeNavigation: navigate(webView, to: snapshot.url)
        )
    }

    private func navigate(_ webView: WKWebView, to url: URL) -> WKNavigation? {
        guard webView.url?.absoluteString != url.absoluteString else { return nil }
        if url.isFileURL {
            return webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            return webView.load(URLRequest(url: url))
        }
    }

    private func removeTabs(excluding retainedIDs: Set<UUID>) {
        for id in tabs.keys where !retainedIDs.contains(id) {
            guard let tab = tabs.removeValue(forKey: id) else { continue }
            navigationWaiters.finish(tabID: id, error: DesktopBrowserSessionScriptError.noSelectedTab)
            tab.webView.stopLoading()
            tab.webView.navigationDelegate = nil
            tabView.removeTabViewItem(tab.item)
        }
    }

    private func storeActiveNavigation(_ navigation: WKNavigation?, for id: UUID, webView: WKWebView) {
        guard var tab = tabs[id], tab.webView === webView else { return }
        tab.activeNavigation = navigation
        tabs[id] = tab
    }

    private func beginUserNavigation(_ navigation: WKNavigation?, for id: UUID, webView: WKWebView) {
        guard let navigation else { return }
        navigationWaiters.finish(
            tabID: id,
            error: DesktopBrowserSessionScriptError.navigationSuperseded
        )
        storeActiveNavigation(navigation, for: id, webView: webView)
    }

    /// Returns false for a stale callback from a load that an active newer navigation replaced.
    private func finishActiveNavigation(for id: UUID, navigation: WKNavigation?) -> Bool {
        guard var tab = tabs[id] else { return false }
        if let navigation {
            guard let activeNavigation = tab.activeNavigation,
                  activeNavigation === navigation
            else {
                return false
            }
        }
        tab.activeNavigation = nil
        tabs[id] = tab
        return true
    }

    private func reorderTabs(_ orderedIDs: [UUID]) {
        for (index, id) in orderedIDs.enumerated() {
            guard let item = tabs[id]?.item else { continue }
            let currentIndex = tabView.indexOfTabViewItem(item)
            guard currentIndex != NSNotFound, currentIndex != index else { continue }
            tabView.removeTabViewItem(item)
            tabView.insertTabViewItem(item, at: index)
        }
    }

    private func selectActiveTab(_ activeTabID: UUID?) {
        guard let activeTabID,
              let item = tabs[activeTabID]?.item
        else {
            return
        }
        tabView.selectTabViewItem(item)
    }

    private func updateWindowTitle() {
        let selectedID = selectedTabID()
        let selectedTitle = selectedID.flatMap { tabs[$0]?.snapshot.title }
        if let selectedTitle = nonEmpty(selectedTitle) {
            window?.title = "\(QuillCodeProduct.displayName) Browser Session - \(selectedTitle)"
        } else {
            window?.title = "\(QuillCodeProduct.displayName) Browser Session"
        }
    }

    private func emitRenderedSessionUpdate(for id: UUID, webView: WKWebView) {
        Task { @MainActor [weak self, weak webView] in
            guard let self,
                  let webView,
                  let tab = tabs[id],
                  tab.webView === webView
            else {
                return
            }
            do {
                let snapshot = try await DesktopBrowserLiveDOMSnapshotExtractor.snapshot(
                    from: webView,
                    fallbackURL: tab.snapshot.url
                )
                guard let currentTab = tabs[id],
                      currentTab.webView === webView
                else {
                    return
                }
                emitSessionUpdate(liveDOMSnapshots: [id: snapshot])
            } catch {
                // URL/title sync above is still useful; rendered DOM is best-effort for visible sessions.
            }
        }
    }

    private func emitSessionUpdate(liveDOMSnapshots: [UUID: BrowserLiveDOMSnapshot] = [:]) {
        let activeID = selectedTabID()
        let updates = tabView.tabViewItems.compactMap { item -> BrowserSessionTabUpdate? in
            guard let id = tabID(for: item),
                  let tab = tabs[id]
            else { return nil }
            let url = tab.webView.url ?? tab.snapshot.url
            let title = nonEmpty(tab.webView.title) ?? tab.snapshot.title
            return BrowserSessionTabUpdate(
                id: id,
                title: title,
                url: url,
                isActive: id == activeID,
                liveDOMSnapshot: liveDOMSnapshots[id]
            )
        }
        guard !updates.isEmpty else { return }
        onSessionUpdate?(BrowserSessionUpdate(tabs: updates, activeTabID: activeID))
    }

    private func selectedTabID() -> UUID? {
        guard let selectedItem = tabView.selectedTabViewItem else { return nil }
        return tabs.first { $0.value.item === selectedItem }?.key
    }

    private func tabID(for item: NSTabViewItem) -> UUID? {
        tabs.first { $0.value.item === item }?.key
    }

    private func tabID(for webView: WKWebView) -> UUID? {
        tabs.first { $0.value.webView === webView }?.key
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func webViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }
}
#endif
