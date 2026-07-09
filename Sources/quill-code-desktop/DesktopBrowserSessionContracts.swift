import Foundation
import QuillCodeApp

@MainActor
protocol DesktopBrowserSessionPresenting: AnyObject {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)? { get set }

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot)
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot)
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
