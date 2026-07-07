import Foundation
import QuillCodeApp

#if canImport(AppKit) && canImport(WebKit)
import AppKit
import WebKit

@MainActor
protocol DesktopBrowserSessionPresenting: AnyObject {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)? { get set }

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot)
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot)
    func reloadSession()
}

@MainActor
final class DesktopBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?

    private var session: DesktopBrowserSessionWindowController?

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {
        guard !snapshot.isEmpty else { return }
        if let session {
            session.sync(snapshot)
            session.present()
            return
        }

        let session = DesktopBrowserSessionWindowController(snapshot: snapshot)
        session.onSessionUpdate = { [weak self] update in
            self?.onSessionUpdate?(update)
        }
        session.onClose = { [weak self, weak session] in
            guard let session, self?.session === session else { return }
            self?.session = nil
        }
        self.session = session
        session.present()
    }

    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {
        guard let session, !snapshot.isEmpty else { return }
        session.sync(snapshot)
    }

    func reloadSession() {
        session?.reloadSelectedTab()
    }
}

@MainActor
private final class DesktopBrowserSessionWindowController: NSWindowController, NSWindowDelegate, NSTabViewDelegate, WKNavigationDelegate {
    private struct SessionTab {
        var snapshot: BrowserSessionTabSnapshot
        var item: NSTabViewItem
        var webView: WKWebView
    }

    var onClose: (() -> Void)?
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?

    private let tabView: NSTabView
    private var tabs: [UUID: SessionTab] = [:]

    init(snapshot: BrowserSessionSyncSnapshot) {
        self.tabView = NSTabView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuillCode Browser Session"
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
        tabs.values.forEach { $0.webView.navigationDelegate = nil }
        onClose?()
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        updateWindowTitle()
        emitSessionUpdate()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard let id = tabID(for: webView),
              var tab = tabs[id]
        else {
            return
        }
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
        tab.webView.reload()
    }

    private func sync(_ snapshot: BrowserSessionTabSnapshot) {
        if var tab = tabs[snapshot.id] {
            tab.snapshot = snapshot
            tab.item.label = snapshot.title
            navigate(tab.webView, to: snapshot.url)
            tabs[snapshot.id] = tab
            return
        }

        let webView = WKWebView(frame: .zero, configuration: Self.webViewConfiguration())
        webView.navigationDelegate = self
        let item = NSTabViewItem(identifier: snapshot.id.uuidString)
        item.label = snapshot.title
        item.view = webView
        tabView.addTabViewItem(item)
        tabs[snapshot.id] = SessionTab(snapshot: snapshot, item: item, webView: webView)
        navigate(webView, to: snapshot.url)
    }

    private func navigate(_ webView: WKWebView, to url: URL) {
        guard webView.url?.absoluteString != url.absoluteString else { return }
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    private func removeTabs(excluding retainedIDs: Set<UUID>) {
        for id in tabs.keys where !retainedIDs.contains(id) {
            guard let tab = tabs.removeValue(forKey: id) else { continue }
            tab.webView.navigationDelegate = nil
            tabView.removeTabViewItem(tab.item)
        }
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
            window?.title = "QuillCode Browser Session - \(selectedTitle)"
        } else {
            window?.title = "QuillCode Browser Session"
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
#else
@MainActor
protocol DesktopBrowserSessionPresenting: AnyObject {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)? { get set }

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot)
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot)
    func reloadSession()
}

@MainActor
final class DesktopBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func reloadSession() {}
}
#endif
