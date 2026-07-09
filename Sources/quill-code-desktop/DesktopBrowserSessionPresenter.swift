import Foundation
import QuillCodeApp

#if canImport(AppKit) && canImport(WebKit)
import AppKit
import WebKit

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

    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {
        session?.goBackSelectedTab(fallback: snapshot)
    }

    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {
        session?.goForwardSelectedTab(fallback: snapshot)
    }

    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        guard let session else { throw DesktopBrowserSessionScriptError.noOpenSession }
        return try await session.evaluateJavaScriptInSelectedTab(source)
    }

    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot {
        guard let session else { throw DesktopBrowserSessionScriptError.noOpenSession }
        return try await session.captureLiveDOMSnapshotInSelectedTab()
    }

    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult {
        guard let session else { throw DesktopBrowserSessionActionError.noOpenSession }
        return try await session.clickInSelectedTab(selector: selector)
    }

    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult {
        guard let session else { throw DesktopBrowserSessionActionError.noOpenSession }
        return try await session.typeInSelectedTab(selector: selector, text: text, submit: submit)
    }

    func reloadSession() {
        session?.reloadSelectedTab()
    }
}

#else
@MainActor
final class DesktopBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult {
        throw DesktopBrowserSessionActionError.noOpenSession
    }
    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult {
        throw DesktopBrowserSessionActionError.noOpenSession
    }
    func reloadSession() {}
}
#endif
