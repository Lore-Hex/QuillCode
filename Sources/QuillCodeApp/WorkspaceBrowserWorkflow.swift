import Foundation
import QuillCodeCore

struct WorkspaceBrowserSnapshotRequest: Sendable, Hashable {
    var tabID: UUID
    var currentURL: String
    var fetchURL: URL
}

struct WorkspaceBrowserLiveDOMRequest: Sendable, Hashable {
    var tabID: UUID
    var currentURL: String
    var captureURL: URL
}

enum WorkspaceBrowserWorkflow {
    static let invalidAddressError = "Enter an http, https, file, localhost, or project file URL."

    @discardableResult
    static func openPreview(
        _ input: String?,
        workspaceRoot: URL?,
        browser: inout BrowserState,
        lastError: inout String?,
        domainPolicy: BrowserDomainPolicy = .unrestricted
    ) -> Bool {
        let rawValue = input ?? browser.addressDraft
        guard let url = WorkspaceBrowserLocationResolver(workspaceRoot: workspaceRoot).resolve(rawValue) else {
            browser.isVisible = true
            browser.status = "Invalid address"
            lastError = invalidAddressError
            return false
        }

        guard markPolicyDecision(domainPolicy.decision(for: url), browser: &browser, lastError: &lastError) else {
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

    static func beginSnapshotFetch(
        browser: inout BrowserState,
        domainPolicy: BrowserDomainPolicy = .unrestricted
    ) -> WorkspaceBrowserSnapshotRequest? {
        guard let currentURL = browser.currentURL,
              let url = URL(string: currentURL),
              WorkspaceBrowserLocationResolver.canFetchSnapshot(for: url)
        else {
            return nil
        }
        guard markPolicyDecision(domainPolicy.decision(for: url), browser: &browser) else {
            return nil
        }

        browser.status = "Fetching snapshot"
        return WorkspaceBrowserSnapshotRequest(
            tabID: browser.selectedTabID,
            currentURL: currentURL,
            fetchURL: url
        )
    }

    static func beginLiveDOMCapture(
        browser: inout BrowserState,
        domainPolicy: BrowserDomainPolicy = .unrestricted
    ) -> WorkspaceBrowserLiveDOMRequest? {
        guard let currentURL = browser.currentURL,
              let url = URL(string: currentURL),
              !url.isFileURL
        else {
            return nil
        }
        guard markPolicyDecision(domainPolicy.decision(for: url), browser: &browser) else {
            return nil
        }

        browser.status = "Capturing DOM"
        return WorkspaceBrowserLiveDOMRequest(
            tabID: browser.selectedTabID,
            currentURL: currentURL,
            captureURL: url
        )
    }

    @discardableResult
    static func applySnapshotFetchSuccess(
        _ fetchedPage: BrowserFetchedPage,
        request: WorkspaceBrowserSnapshotRequest,
        browser: inout BrowserState,
        lastError: inout String?,
        domainPolicy: BrowserDomainPolicy = .unrestricted
    ) -> Bool {
        guard browser.selectedTabID == request.tabID,
              browser.currentURL == request.currentURL
        else { return false }
        guard markPolicyDecision(
            domainPolicy.decision(for: fetchedPage.finalURL),
            browser: &browser,
            lastError: &lastError
        ) else {
            return true
        }
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
        guard browser.selectedTabID == request.tabID,
              browser.currentURL == request.currentURL
        else { return false }
        WorkspaceBrowserEngine.markSnapshotFetchFailure(error, state: &browser)
        lastError = nil
        return true
    }

    @discardableResult
    static func applyLiveDOMCaptureSuccess(
        _ snapshot: BrowserLiveDOMSnapshot,
        request: WorkspaceBrowserLiveDOMRequest,
        browser: inout BrowserState,
        lastError: inout String?,
        domainPolicy: BrowserDomainPolicy = .unrestricted
    ) -> Bool {
        guard browser.selectedTabID == request.tabID,
              browser.currentURL == request.currentURL
        else { return false }
        guard markPolicyDecision(
            domainPolicy.decision(for: snapshot.finalURL),
            browser: &browser,
            lastError: &lastError
        ) else {
            return true
        }
        WorkspaceBrowserEngine.applyLiveDOMSnapshot(snapshot, originalURL: request.captureURL, state: &browser)
        lastError = nil
        return true
    }

    @discardableResult
    static func applyLiveDOMCaptureFailure(
        _ error: any Error,
        request: WorkspaceBrowserLiveDOMRequest,
        browser: inout BrowserState,
        lastError: inout String?
    ) -> Bool {
        guard browser.selectedTabID == request.tabID,
              browser.currentURL == request.currentURL
        else { return false }
        WorkspaceBrowserEngine.markLiveDOMCaptureFailure(error, state: &browser)
        lastError = nil
        return true
    }

    @discardableResult
    static func addComment(_ text: String, browser: inout BrowserState) -> Bool {
        WorkspaceBrowserEngine.addComment(text, state: &browser)
    }

    @discardableResult
    static func applySessionUpdate(
        _ update: BrowserSessionUpdate,
        browser: inout BrowserState,
        domainPolicy: BrowserDomainPolicy = .unrestricted
    ) -> Bool {
        let filteredUpdate = update.filtered(by: domainPolicy)
        let changed = WorkspaceBrowserEngine.applySessionUpdate(filteredUpdate, state: &browser)
        if filteredUpdate.tabs.count != update.tabs.count {
            browser.status = "Blocked browser session domain"
        }
        return changed
    }

    @discardableResult
    static func newTab(browser: inout BrowserState) -> UUID {
        WorkspaceBrowserEngine.newTab(state: &browser)
    }

    @discardableResult
    static func selectTab(id: UUID, browser: inout BrowserState) -> Bool {
        WorkspaceBrowserEngine.selectTab(id: id, state: &browser)
    }

    @discardableResult
    static func closeTab(id: UUID, browser: inout BrowserState) -> Bool {
        WorkspaceBrowserEngine.closeTab(id: id, state: &browser)
    }

    private static func markPolicyDecision(
        _ decision: BrowserDomainDecision,
        browser: inout BrowserState
    ) -> Bool {
        switch decision {
        case .allow:
            return true
        case .block:
            browser.isVisible = true
            browser.status = "Blocked by browser policy"
            return false
        }
    }

    private static func markPolicyDecision(
        _ decision: BrowserDomainDecision,
        browser: inout BrowserState,
        lastError: inout String?
    ) -> Bool {
        switch decision {
        case .allow:
            return true
        case .block(let reason):
            browser.isVisible = true
            browser.status = "Blocked by browser policy"
            lastError = reason
            return false
        }
    }
}

private extension BrowserSessionUpdate {
    func filtered(by policy: BrowserDomainPolicy) -> BrowserSessionUpdate {
        guard !policy.isUnrestricted else { return self }
        let allowedTabs = tabs.filter { policy.allows($0.url) }
        return BrowserSessionUpdate(
            tabs: allowedTabs,
            activeTabID: activeTabID.flatMap { activeID in
                allowedTabs.contains { $0.id == activeID } ? activeID : nil
            }
        )
    }
}
