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
