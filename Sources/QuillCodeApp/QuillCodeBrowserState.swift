import Foundation

public struct BrowserState: Sendable, Hashable {
    public static let defaultTitle = "Browser preview"

    public var isVisible: Bool
    public var tabs: [BrowserTabState]
    public var selectedTabID: UUID
    public var addressDraft: String
    public var currentURL: String?
    public var history: [String]
    public var historyIndex: Int?
    public var title: String
    public var status: String
    public var snapshot: BrowserSnapshotState?
    public var comments: [BrowserCommentState]

    public var canGoBack: Bool {
        guard let historyIndex else { return false }
        return history.indices.contains(historyIndex) && historyIndex > history.startIndex
    }

    public var canGoForward: Bool {
        guard let historyIndex else { return false }
        return history.indices.contains(historyIndex) && history.index(after: historyIndex) < history.endIndex
    }

    public var canReload: Bool {
        currentURL != nil
    }

    public var canCloseSelectedTab: Bool {
        tabs.count > 1
    }

    public var canCreateNewTab: Bool {
        tabs.count < WorkspaceBrowserRetentionPolicy.maximumTabCount
    }

    public init(
        isVisible: Bool = false,
        tabs: [BrowserTabState] = [],
        selectedTabID: UUID? = nil,
        addressDraft: String = "",
        currentURL: String? = nil,
        history: [String] = [],
        historyIndex: Int? = nil,
        title: String = BrowserState.defaultTitle,
        status: String = "Ready",
        snapshot: BrowserSnapshotState? = nil,
        comments: [BrowserCommentState] = []
    ) {
        self.isVisible = isVisible
        let selectedTabID = selectedTabID ?? tabs.first?.id ?? UUID()
        let initializedTabs = tabs.isEmpty ? [
            BrowserTabState(
                id: selectedTabID,
                addressDraft: addressDraft,
                currentURL: currentURL,
                history: history,
                historyIndex: historyIndex,
                title: title,
                status: status,
                snapshot: snapshot,
                comments: comments
            )
        ] : WorkspaceBrowserRetentionPolicy.normalizedTabs(
            tabs,
            selectedTabID: selectedTabID
        )
        self.tabs = initializedTabs
        self.selectedTabID = initializedTabs.contains { $0.id == selectedTabID }
            ? selectedTabID
            : initializedTabs[0].id
        self.addressDraft = WorkspaceBrowserRetentionPolicy.bounded(
            addressDraft,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumLocationCharacters
        )
        self.currentURL = currentURL.map {
            WorkspaceBrowserRetentionPolicy.bounded(
                $0,
                maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumLocationCharacters
            )
        }
        let retainedHistory = WorkspaceBrowserRetentionPolicy.normalizedHistory(
            history,
            selectedIndex: historyIndex
        )
        self.history = retainedHistory.entries
        self.historyIndex = retainedHistory.selectedIndex
        self.title = WorkspaceBrowserRetentionPolicy.bounded(
            title,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumTabTitleCharacters
        )
        self.status = WorkspaceBrowserRetentionPolicy.bounded(
            status,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumStatusCharacters
        )
        self.snapshot = snapshot.map(WorkspaceBrowserRetentionPolicy.normalizedSnapshot)
        self.comments = WorkspaceBrowserRetentionPolicy.normalizedComments(comments)
    }
}
