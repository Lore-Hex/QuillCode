import Foundation

public struct BrowserTabState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var addressDraft: String
    public var currentURL: String?
    public var history: [String]
    public var historyIndex: Int?
    public var title: String
    public var status: String
    public var snapshot: BrowserSnapshotState?
    public var comments: [BrowserCommentState]

    public var displayTitle: String {
        if let currentURL,
           let url = URL(string: currentURL),
           let host = url.host,
           !host.isEmpty {
            return title == BrowserState.defaultTitle ? host : title
        }
        return title == BrowserState.defaultTitle ? "New tab" : title
    }

    public init(
        id: UUID = UUID(),
        addressDraft: String = "",
        currentURL: String? = nil,
        history: [String] = [],
        historyIndex: Int? = nil,
        title: String = BrowserState.defaultTitle,
        status: String = "Ready",
        snapshot: BrowserSnapshotState? = nil,
        comments: [BrowserCommentState] = []
    ) {
        self.id = id
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
