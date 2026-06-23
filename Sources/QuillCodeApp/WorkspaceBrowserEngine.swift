import Foundation

struct WorkspaceBrowserEngine {
    static func openPage(_ url: URL, state: inout BrowserState, updateHistory: Bool) {
        state.isVisible = true
        state.currentURL = url.absoluteString
        state.addressDraft = url.absoluteString
        state.snapshot = BrowserInspector.snapshot(for: url)
        state.title = title(from: state.snapshot, fallbackURL: url)
        state.status = "Preview ready"
        if updateHistory {
            appendHistory(url.absoluteString, state: &state)
        }
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
        state.title = title(from: state.snapshot, fallbackURL: fetchedPage.finalURL)
        state.status = "Preview ready"
    }

    static func markSnapshotFetchFailure(_ error: any Error, state: inout BrowserState) {
        if var snapshot = state.snapshot {
            snapshot.details.append("Snapshot fetch: \(WorkspaceBrowserLocationResolver.snapshotFetchMessage(for: error))")
            state.snapshot = snapshot
        }
        state.status = "Preview ready"
    }

    @discardableResult
    static func addComment(_ text: String, state: inout BrowserState) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = state.currentURL else {
            return false
        }
        state.comments.append(BrowserCommentState(url: url, text: trimmed))
        state.status = "Comment added"
        return true
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

    private static func appendHistory(_ url: String, state: inout BrowserState) {
        if let historyIndex = state.historyIndex,
           state.history.indices.contains(historyIndex),
           state.history[historyIndex] == url {
            return
        }

        let preservedHistory: ArraySlice<String>
        if let historyIndex = state.historyIndex,
           state.history.indices.contains(historyIndex) {
            preservedHistory = state.history.prefix(through: historyIndex)
        } else {
            preservedHistory = []
        }

        state.history = Array(preservedHistory) + [url]
        state.historyIndex = state.history.indices.last
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

    private static func title(from snapshot: BrowserSnapshotState?, fallbackURL url: URL) -> String {
        snapshot?.details
            .first { $0.hasPrefix("Title: ") }
            .map { String($0.dropFirst("Title: ".count)) }
            ?? BrowserInspector.title(for: url)
    }
}
