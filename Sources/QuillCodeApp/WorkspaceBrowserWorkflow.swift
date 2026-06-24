import Foundation

struct WorkspaceBrowserSnapshotRequest: Sendable, Hashable {
    var currentURL: String
    var fetchURL: URL
}

enum WorkspaceBrowserWorkflow {
    static let invalidAddressError = "Enter an http, https, file, localhost, or project file URL."

    @discardableResult
    static func openPreview(
        _ input: String?,
        workspaceRoot: URL?,
        browser: inout BrowserState,
        lastError: inout String?
    ) -> Bool {
        let rawValue = input ?? browser.addressDraft
        guard let url = WorkspaceBrowserLocationResolver(workspaceRoot: workspaceRoot).resolve(rawValue) else {
            browser.isVisible = true
            browser.status = "Invalid address"
            lastError = invalidAddressError
            return false
        }

        WorkspaceBrowserEngine.openPage(url, state: &browser, updateHistory: true)
        lastError = nil
        return true
    }

    @discardableResult
    static func goBack(browser: inout BrowserState, lastError: inout String?) -> Bool {
        guard WorkspaceBrowserEngine.goBack(state: &browser) else { return false }
        lastError = nil
        return true
    }

    @discardableResult
    static func goForward(browser: inout BrowserState, lastError: inout String?) -> Bool {
        guard WorkspaceBrowserEngine.goForward(state: &browser) else { return false }
        lastError = nil
        return true
    }

    @discardableResult
    static func reload(browser: inout BrowserState, lastError: inout String?) -> Bool {
        guard WorkspaceBrowserEngine.reload(state: &browser) else { return false }
        lastError = nil
        return true
    }

    static func beginSnapshotFetch(browser: inout BrowserState) -> WorkspaceBrowserSnapshotRequest? {
        guard let currentURL = browser.currentURL,
              let url = URL(string: currentURL),
              WorkspaceBrowserLocationResolver.canFetchSnapshot(for: url)
        else {
            return nil
        }

        browser.status = "Fetching snapshot"
        return WorkspaceBrowserSnapshotRequest(currentURL: currentURL, fetchURL: url)
    }

    @discardableResult
    static func applySnapshotFetchSuccess(
        _ fetchedPage: BrowserFetchedPage,
        request: WorkspaceBrowserSnapshotRequest,
        browser: inout BrowserState,
        lastError: inout String?
    ) -> Bool {
        guard browser.currentURL == request.currentURL else { return false }
        WorkspaceBrowserEngine.applyFetchedPage(fetchedPage, originalURL: request.fetchURL, state: &browser)
        lastError = nil
        return true
    }

    @discardableResult
    static func applySnapshotFetchFailure(
        _ error: any Error,
        request: WorkspaceBrowserSnapshotRequest,
        browser: inout BrowserState,
        lastError: inout String?
    ) -> Bool {
        guard browser.currentURL == request.currentURL else { return false }
        WorkspaceBrowserEngine.markSnapshotFetchFailure(error, state: &browser)
        lastError = nil
        return true
    }

    @discardableResult
    static func addComment(_ text: String, browser: inout BrowserState) -> Bool {
        WorkspaceBrowserEngine.addComment(text, state: &browser)
    }
}
