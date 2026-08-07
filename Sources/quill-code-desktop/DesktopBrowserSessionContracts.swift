import Foundation
import QuillCodeApp

@MainActor
protocol DesktopBrowserSessionPresenting: AnyObject {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)? { get set }

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot)
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot)
    /// Drive the selected tab to `url`, WAIT for the navigation to finish, and return the
    /// post-render DOM. This is what makes `host.browser.open` a real navigation for an agent:
    /// without it the tool only mutated in-memory state, so a follow-up `inspect` silently read
    /// whatever unrelated page the window happened to be showing.
    func navigateSelectedTab(to url: URL) async throws -> BrowserLiveDOMSnapshot
    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot)
    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot)
    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult
    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot
    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult
    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult
    func reloadSession()
}

struct DesktopBrowserSessionScriptResult: Sendable, Equatable {
    var title: String
    var url: URL
    var valueDescription: String
}

enum DesktopBrowserSessionScriptError: Error, Sendable, Equatable {
    case noOpenSession
    case noSelectedTab
    case emptySource
    /// A newer open replaced an in-flight navigation for the same visible tab.
    case navigationSuperseded
    /// The page failed to load (DNS, connection refused, TLS, blocked). Carries the platform
    /// message so the model is told what actually went wrong instead of getting a blank DOM.
    case navigationFailed(String)
}

struct DesktopBrowserSessionActionResult: Sendable, Equatable, Decodable {
    var ok: Bool
    var summary: String
    var error: String?
}

enum DesktopBrowserSessionActionError: Error, Sendable, Equatable {
    case noOpenSession
    case noSelectedTab
    case emptySelector
    case emptyText
    case encodingFailed
    case decodingFailed(String)
    case actionFailed(String)
}
