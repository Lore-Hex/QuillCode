import Foundation

struct WorkspaceBrowserEngine {
    static func newTab(state: inout BrowserState) -> UUID? {
        storeSelectedTab(in: &state)
        guard state.canCreateNewTab else {
            state.status = WorkspaceBrowserRetentionPolicy.tabLimitStatus
            storeSelectedTab(in: &state)
            return nil
        }
        let tab = BrowserTabState()
        state.tabs.append(tab)
        state.selectedTabID = tab.id
        loadSelectedTab(into: &state)
        state.isVisible = true
        state.status = "New tab"
        storeSelectedTab(in: &state)
        return tab.id
    }

    @discardableResult
    static func selectTab(id: UUID, state: inout BrowserState) -> Bool {
        guard state.tabs.contains(where: { $0.id == id }) else { return false }
        storeSelectedTab(in: &state)
        state.selectedTabID = id
        loadSelectedTab(into: &state)
        state.isVisible = true
        return true
    }

    @discardableResult
    static func closeTab(id: UUID, state: inout BrowserState) -> Bool {
        guard state.tabs.count > 1,
              let closedIndex = state.tabs.firstIndex(where: { $0.id == id })
        else {
            return false
        }

        let wasSelected = state.selectedTabID == id
        state.tabs.remove(at: closedIndex)
        if wasSelected {
            let replacementIndex = min(closedIndex, state.tabs.count - 1)
            state.selectedTabID = state.tabs[replacementIndex].id
            loadSelectedTab(into: &state)
        }
        return true
    }

    static func openPage(
        _ url: URL,
        state: inout BrowserState,
        updateHistory: Bool,
        inspectLocalFileContents: Bool = true
    ) {
        state.isVisible = true
        state.currentURL = url.absoluteString
        state.addressDraft = url.absoluteString
        state.snapshot = BrowserInspector.snapshot(
            for: url,
            inspectLocalFileContents: inspectLocalFileContents
        )
        state.title = BrowserInspector.title(for: state.snapshot, fallbackURL: url)
        state.status = "Preview ready"
        if updateHistory {
            if appendHistory(url.absoluteString, state: &state) {
                state.status = "Preview ready; older browser history released."
            }
        }
        storeSelectedTab(in: &state)
    }

    @discardableResult
    static func goBack(state: inout BrowserState) -> Bool {
        guard state.canGoBack,
              let historyIndex = state.historyIndex
        else {
            return false
        }
        return openHistoryEntry(at: historyIndex - 1, state: &state)
    }

    @discardableResult
    static func goForward(state: inout BrowserState) -> Bool {
        guard state.canGoForward,
              let historyIndex = state.historyIndex
        else {
            return false
        }
        return openHistoryEntry(at: historyIndex + 1, state: &state)
    }

    @discardableResult
    static func reload(state: inout BrowserState) -> Bool {
        guard let currentURL = state.currentURL,
              let url = URL(string: currentURL)
        else {
            return false
        }
        openPage(url, state: &state, updateHistory: false)
        state.status = "Reloaded"
        return true
    }

    static func applyFetchedPage(
        _ fetchedPage: BrowserFetchedPage,
        originalURL: URL,
        state: inout BrowserState
    ) {
        state.currentURL = fetchedPage.finalURL.absoluteString
        state.addressDraft = fetchedPage.finalURL.absoluteString
        replaceCurrentHistory(with: fetchedPage.finalURL.absoluteString, state: &state)
        state.snapshot = BrowserInspector.snapshot(for: fetchedPage, originalURL: originalURL)
        state.title = BrowserInspector.title(for: state.snapshot, fallbackURL: fetchedPage.finalURL)
        state.status = "Preview ready"
        storeSelectedTab(in: &state)
    }

    static func applyLiveDOMSnapshot(
        _ liveDOMSnapshot: BrowserLiveDOMSnapshot,
        originalURL: URL,
        state: inout BrowserState
    ) {
        state.currentURL = liveDOMSnapshot.finalURL.absoluteString
        state.addressDraft = liveDOMSnapshot.finalURL.absoluteString
        replaceCurrentHistory(with: liveDOMSnapshot.finalURL.absoluteString, state: &state)
        state.snapshot = BrowserInspector.snapshot(for: liveDOMSnapshot, originalURL: originalURL)
        state.title = BrowserInspector.title(for: state.snapshot, fallbackURL: liveDOMSnapshot.finalURL)
        state.status = "Preview ready"
        storeSelectedTab(in: &state)
    }

    @discardableResult
    static func applySessionUpdate(_ update: BrowserSessionUpdate, state: inout BrowserState) -> Bool {
        guard !update.isEmpty else { return false }
        storeSelectedTab(in: &state)

        var changed = false
        var rejectedNewTab = false
        for tabUpdate in update.tabs {
            if !state.tabs.contains(where: { $0.id == tabUpdate.id }),
               !state.canCreateNewTab {
                rejectedNewTab = true
                continue
            }
            changed = apply(tabUpdate, state: &state) || changed
        }

        if let activeTabID = update.activeTabID,
           state.tabs.contains(where: { $0.id == activeTabID }),
           state.selectedTabID != activeTabID {
            state.selectedTabID = activeTabID
            changed = true
        }

        loadSelectedTab(into: &state)
        state.isVisible = true
        if rejectedNewTab {
            state.status = WorkspaceBrowserRetentionPolicy.tabLimitStatus
            storeSelectedTab(in: &state)
            changed = true
        }
        return changed
    }

    static func markSnapshotFetchFailure(_ error: any Error, state: inout BrowserState) {
        if var snapshot = state.snapshot {
            let message = WorkspaceBrowserLocationResolver.snapshotFetchMessage(for: error)
            snapshot.details = WorkspaceBrowserRetentionPolicy.replacingDiagnostic(
                prefix: "Snapshot fetch: ",
                message: message,
                in: snapshot.details
            )
            state.snapshot = snapshot
        }
        state.status = "Preview ready"
        storeSelectedTab(in: &state)
    }

    static func markLiveDOMCaptureFailure(_ error: any Error, state: inout BrowserState) {
        if var snapshot = state.snapshot {
            snapshot.details = WorkspaceBrowserRetentionPolicy.replacingDiagnostic(
                prefix: "Live DOM capture: ",
                message: liveDOMCaptureMessage(for: error),
                in: snapshot.details
            )
            state.snapshot = snapshot
        }
        state.status = "Preview ready"
        storeSelectedTab(in: &state)
    }

    @discardableResult
    static func addComment(_ text: String, state: inout BrowserState) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = state.currentURL else {
            return false
        }
        let shortenedComment = WorkspaceBrowserRetentionPolicy.exceedsMaximumCharacters(
            trimmed,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumCommentCharacters
        )
        let boundedText = WorkspaceBrowserRetentionPolicy.bounded(
            trimmed,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumCommentCharacters
        )
        state.comments.append(BrowserCommentState(url: url, text: boundedText))
        let releasedComment = state.comments.count > WorkspaceBrowserRetentionPolicy.maximumCommentCount
        state.comments = WorkspaceBrowserRetentionPolicy.normalizedComments(state.comments)
        switch (shortenedComment, releasedComment) {
        case (true, true):
            state.status = "Comment shortened; oldest browser comment released."
        case (true, false):
            state.status = "Comment shortened to 4,000 characters."
        case (false, true):
            state.status = "Comment added; oldest browser comment released."
        case (false, false):
            state.status = "Comment added"
        }
        storeSelectedTab(in: &state)
        return true
    }

    private static func storeSelectedTab(in state: inout BrowserState) {
        ensureSelectedTab(in: &state)
        guard let index = state.tabs.firstIndex(where: { $0.id == state.selectedTabID }) else { return }
        let retained = BrowserTabState(
            id: state.selectedTabID,
            addressDraft: state.addressDraft,
            currentURL: state.currentURL,
            history: state.history,
            historyIndex: state.historyIndex,
            title: state.title,
            status: state.status,
            snapshot: state.snapshot,
            comments: state.comments
        )
        state.tabs[index] = retained
        state.addressDraft = retained.addressDraft
        state.currentURL = retained.currentURL
        state.history = retained.history
        state.historyIndex = retained.historyIndex
        state.title = retained.title
        state.status = retained.status
        state.snapshot = retained.snapshot
        state.comments = retained.comments
    }

    @discardableResult
    private static func apply(_ update: BrowserSessionTabUpdate, state: inout BrowserState) -> Bool {
        let index: Int
        if let existingIndex = state.tabs.firstIndex(where: { $0.id == update.id }) {
            index = existingIndex
        } else {
            state.tabs.append(BrowserTabState(id: update.id))
            index = state.tabs.count - 1
        }

        var tab = state.tabs[index]
        var changed = false
        var releasedHistory = false
        let displayURL = update.liveDOMSnapshot?.finalURL ?? update.url
        let urlString = displayURL.absoluteString
        if tab.currentURL != urlString {
            tab.currentURL = urlString
            tab.addressDraft = urlString
            tab.snapshot = snapshot(for: update, displayURL: displayURL)
            releasedHistory = appendHistory(
                urlString,
                history: &tab.history,
                historyIndex: &tab.historyIndex
            )
            changed = true
        } else if update.liveDOMSnapshot != nil {
            tab.snapshot = snapshot(for: update, displayURL: displayURL)
            changed = true
        }

        let title: String
        if update.liveDOMSnapshot != nil, let snapshot = tab.snapshot {
            title = BrowserInspector.title(for: snapshot, fallbackURL: displayURL)
        } else {
            title = sessionTitle(update.title, fallbackURL: displayURL)
        }
        if tab.title != title {
            tab.title = title
            changed = true
        }

        if changed {
            tab.status = releasedHistory
                ? "Synced from browser session; older history released."
                : "Synced from browser session"
            state.tabs[index] = WorkspaceBrowserRetentionPolicy.normalizedTab(tab)
        }
        return changed
    }

    private static func snapshot(
        for update: BrowserSessionTabUpdate,
        displayURL: URL
    ) -> BrowserSnapshotState {
        if let liveDOMSnapshot = update.liveDOMSnapshot {
            return BrowserInspector.snapshot(for: liveDOMSnapshot, originalURL: update.url)
        }
        return BrowserInspector.snapshot(for: displayURL)
    }

    private static func loadSelectedTab(into state: inout BrowserState) {
        ensureSelectedTab(in: &state)
        guard let index = state.tabs.firstIndex(where: { $0.id == state.selectedTabID }) else { return }
        let tab = WorkspaceBrowserRetentionPolicy.normalizedTab(state.tabs[index])
        state.tabs[index] = tab
        state.addressDraft = tab.addressDraft
        state.currentURL = tab.currentURL
        state.history = tab.history
        state.historyIndex = tab.historyIndex
        state.title = tab.title
        state.status = tab.status
        state.snapshot = tab.snapshot
        state.comments = tab.comments
    }

    private static func ensureSelectedTab(in state: inout BrowserState) {
        if state.tabs.contains(where: { $0.id == state.selectedTabID }) {
            return
        }
        if let first = state.tabs.first {
            state.selectedTabID = first.id
            return
        }
        let tab = BrowserTabState(id: state.selectedTabID)
        state.tabs = [tab]
    }

    private static func openHistoryEntry(at index: Int, state: inout BrowserState) -> Bool {
        guard state.history.indices.contains(index),
              let url = URL(string: state.history[index])
        else {
            return false
        }
        state.historyIndex = index
        openPage(url, state: &state, updateHistory: false)
        return true
    }

    @discardableResult
    private static func appendHistory(_ url: String, state: inout BrowserState) -> Bool {
        appendHistory(url, history: &state.history, historyIndex: &state.historyIndex)
    }

    @discardableResult
    private static func appendHistory(
        _ url: String,
        history: inout [String],
        historyIndex: inout Int?
    ) -> Bool {
        if let historyIndex,
           history.indices.contains(historyIndex),
           history[historyIndex] == url {
            return false
        }
        let appended = WorkspaceBrowserRetentionPolicy.historyByAppending(
            url,
            to: history,
            selectedIndex: historyIndex
        )
        history = appended.entries
        historyIndex = appended.selectedIndex
        return appended.didReleaseEntries
    }

    private static func replaceCurrentHistory(with url: String, state: inout BrowserState) {
        guard let historyIndex = state.historyIndex,
              state.history.indices.contains(historyIndex)
        else {
            appendHistory(url, state: &state)
            return
        }
        state.history[historyIndex] = url
    }

    private static func sessionTitle(_ title: String, fallbackURL url: URL) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? BrowserInspector.title(for: url) : trimmed
    }

    private static func liveDOMCaptureMessage(for error: any Error) -> String {
        if let failure = error as? BrowserLiveDOMCaptureFailure {
            return failure.description
        }
        return error.localizedDescription
    }
}
