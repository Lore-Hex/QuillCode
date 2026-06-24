import Foundation

#if canImport(AppKit) && canImport(WebKit)
import AppKit
import WebKit

@MainActor
protocol DesktopBrowserSessionPresenting: AnyObject {
    func openSession(url: URL)
}

@MainActor
final class DesktopBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    private var sessions: [ObjectIdentifier: DesktopBrowserSessionWindowController] = [:]

    func openSession(url: URL) {
        let session = DesktopBrowserSessionWindowController(url: url)
        let sessionID = ObjectIdentifier(session)
        session.onClose = { [weak self] in
            self?.sessions.removeValue(forKey: sessionID)
        }
        sessions[sessionID] = session
        session.showWindow(nil)
        session.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class DesktopBrowserSessionWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    var onClose: (() -> Void)?

    private let webView: WKWebView

    init(url: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuillCode Browser Session"
        window.contentView = webView
        window.center()

        super.init(window: window)

        window.delegate = self
        webView.navigationDelegate = self
        load(url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        webView.navigationDelegate = nil
        onClose?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        if let title = webView.title, !title.isEmpty {
            window?.title = "QuillCode Browser Session - \(title)"
        } else {
            window?.title = "QuillCode Browser Session"
        }
    }

    private func load(_ url: URL) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }
}
#else
@MainActor
protocol DesktopBrowserSessionPresenting: AnyObject {
    func openSession(url: URL)
}

@MainActor
final class DesktopBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    func openSession(url: URL) {}
}
#endif
