import Foundation

enum WorkspaceBrowserRetentionPolicy {
    static let maximumTabCount = 20
    static let maximumHistoryEntryCount = 128
    static let maximumCommentCount = 100
    static let maximumCommentCharacters = 4_000
    static let maximumLocationCharacters = 16_384
    static let maximumTabTitleCharacters = 512
    static let maximumStatusCharacters = 512
    static let maximumSnapshotLabelCharacters = 256
    static let maximumSnapshotSummaryCharacters = 2_000
    static let maximumSnapshotDetailCount = 64
    static let maximumSnapshotDetailCharacters = 1_024
    static let maximumSnapshotOutlineCount = 48
    static let maximumSnapshotOutlineCharacters = 1_024
    static let maximumSnapshotTextCharacters = 12_000

    static let tabLimitStatus = "20-tab limit reached; close a browser tab to open another."

    static func normalizedTabs(
        _ tabs: [BrowserTabState],
        selectedTabID: UUID
    ) -> [BrowserTabState] {
        var retained = Array(tabs.prefix(maximumTabCount))
        if !retained.contains(where: { $0.id == selectedTabID }),
           let selected = tabs.first(where: { $0.id == selectedTabID }),
           !retained.isEmpty {
            retained[retained.count - 1] = selected
        }
        return retained.map(normalizedTab)
    }

    static func normalizedTab(_ tab: BrowserTabState) -> BrowserTabState {
        var tab = tab
        tab.addressDraft = bounded(
            tab.addressDraft,
            maximumCharacters: maximumLocationCharacters
        )
        tab.currentURL = tab.currentURL.map {
            bounded($0, maximumCharacters: maximumLocationCharacters)
        }
        tab.title = bounded(tab.title, maximumCharacters: maximumTabTitleCharacters)
        tab.status = bounded(tab.status, maximumCharacters: maximumStatusCharacters)
        let history = normalizedHistory(tab.history, selectedIndex: tab.historyIndex)
        tab.history = history.entries
        tab.historyIndex = history.selectedIndex
        tab.comments = normalizedComments(tab.comments)
        tab.snapshot = tab.snapshot.map(normalizedSnapshot)
        return tab
    }

    static func normalizedHistory(
        _ entries: [String],
        selectedIndex: Int?
    ) -> (entries: [String], selectedIndex: Int?) {
        guard !entries.isEmpty else { return ([], nil) }
        let selected = selectedIndex.flatMap { entries.indices.contains($0) ? $0 : nil }
            ?? entries.index(before: entries.endIndex)
        guard entries.count > maximumHistoryEntryCount else {
            return (
                entries.map { bounded($0, maximumCharacters: maximumLocationCharacters) },
                selected
            )
        }

        let latestStart = entries.count - maximumHistoryEntryCount
        let start = min(selected, latestStart)
        let end = start + maximumHistoryEntryCount
        let retained = entries[start..<end].map {
            bounded($0, maximumCharacters: maximumLocationCharacters)
        }
        return (retained, selected - start)
    }

    static func historyByAppending(
        _ url: String,
        to entries: [String],
        selectedIndex: Int?
    ) -> (entries: [String], selectedIndex: Int, didReleaseEntries: Bool) {
        let preserved: ArraySlice<String>
        if let selectedIndex, entries.indices.contains(selectedIndex) {
            preserved = entries.prefix(through: selectedIndex)
        } else {
            preserved = []
        }
        let appended = Array(preserved) + [
            bounded(url, maximumCharacters: maximumLocationCharacters)
        ]
        let didReleaseEntries = appended.count > maximumHistoryEntryCount
        let retained = Array(appended.suffix(maximumHistoryEntryCount))
        return (retained, retained.index(before: retained.endIndex), didReleaseEntries)
    }

    static func normalizedComments(_ comments: [BrowserCommentState]) -> [BrowserCommentState] {
        comments
            .suffix(maximumCommentCount)
            .map { comment in
                var comment = comment
                comment.url = bounded(
                    comment.url,
                    maximumCharacters: maximumLocationCharacters
                )
                comment.text = bounded(comment.text, maximumCharacters: maximumCommentCharacters)
                return comment
            }
    }

    static func normalizedSnapshot(_ snapshot: BrowserSnapshotState) -> BrowserSnapshotState {
        var snapshot = snapshot
        snapshot.sourceLabel = bounded(
            snapshot.sourceLabel,
            maximumCharacters: maximumSnapshotLabelCharacters
        )
        snapshot.summary = bounded(
            snapshot.summary,
            maximumCharacters: maximumSnapshotSummaryCharacters
        )
        snapshot.details = boundedLines(
            snapshot.details,
            maximumCount: maximumSnapshotDetailCount,
            maximumCharacters: maximumSnapshotDetailCharacters
        )
        snapshot.outline = boundedLines(
            snapshot.outline,
            maximumCount: maximumSnapshotOutlineCount,
            maximumCharacters: maximumSnapshotOutlineCharacters
        )
        snapshot.textSnippet = snapshot.textSnippet.map {
            bounded($0, maximumCharacters: maximumSnapshotTextCharacters)
        }
        return snapshot
    }

    static func replacingDiagnostic(
        prefix: String,
        message: String,
        in details: [String]
    ) -> [String] {
        let retained = details.filter { !$0.hasPrefix(prefix) }
        return boundedLines(
            retained + [prefix + message],
            maximumCount: maximumSnapshotDetailCount,
            maximumCharacters: maximumSnapshotDetailCharacters
        )
    }

    static func bounded(_ text: String, maximumCharacters: Int) -> String {
        guard let boundary = text.index(
            text.startIndex,
            offsetBy: maximumCharacters,
            limitedBy: text.endIndex
        ), boundary != text.endIndex else {
            return text
        }
        return String(text[..<boundary])
    }

    static func boundedURL(_ url: URL) -> URL {
        let absoluteString = url.absoluteString
        guard exceedsMaximumCharacters(
            absoluteString,
            maximumCharacters: maximumLocationCharacters
        ) else {
            return url
        }
        let retained = bounded(
            absoluteString,
            maximumCharacters: maximumLocationCharacters
        )
        return URL(string: retained) ?? URL(string: "about:blank")!
    }

    static func exceedsMaximumCharacters(_ text: String, maximumCharacters: Int) -> Bool {
        guard let boundary = text.index(
            text.startIndex,
            offsetBy: maximumCharacters,
            limitedBy: text.endIndex
        ) else {
            return false
        }
        return boundary != text.endIndex
    }

    static func boundedLines(
        _ lines: [String],
        maximumCount: Int,
        maximumCharacters: Int
    ) -> [String] {
        lines
            .suffix(maximumCount)
            .map { bounded($0, maximumCharacters: maximumCharacters) }
    }
}
