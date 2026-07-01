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
        self.tabs = tabs.isEmpty ? [
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
        ] : tabs
        self.selectedTabID = selectedTabID
        self.addressDraft = addressDraft
        self.currentURL = currentURL
        self.history = history
        self.historyIndex = historyIndex
        self.title = title
        self.status = status
        self.snapshot = snapshot
        self.comments = comments
    }
}
