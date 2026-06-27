import Foundation
import QuillCodeCore

public struct BrowserCommentState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), url: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.url = url
        self.text = text
        self.createdAt = createdAt
    }
}

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
            return title == "Browser preview" ? host : title
        }
        return title == "Browser preview" ? "New tab" : title
    }

    public init(
        id: UUID = UUID(),
        addressDraft: String = "",
        currentURL: String? = nil,
        history: [String] = [],
        historyIndex: Int? = nil,
        title: String = "Browser preview",
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

public struct BrowserSnapshotState: Sendable, Hashable {
    public var sourceLabel: String
    public var inspectionDepth: BrowserInspectionDepth
    public var summary: String
    public var details: [String]
    public var outline: [String]
    public var textSnippet: String?

    public init(
        sourceLabel: String,
        inspectionDepth: BrowserInspectionDepth = .metadataOnly,
        summary: String,
        details: [String] = [],
        outline: [String] = [],
        textSnippet: String? = nil
    ) {
        self.sourceLabel = sourceLabel
        self.inspectionDepth = inspectionDepth
        self.summary = summary
        self.details = details
        self.outline = outline
        self.textSnippet = textSnippet
    }
}

public struct BrowserState: Sendable, Hashable {
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
        title: String = "Browser preview",
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

public struct BrowserSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var tabs: [BrowserTabSurface]
    public var activeTabID: UUID
    public var canCloseActiveTab: Bool
    public var addressDraft: String
    public var currentURL: String?
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var canReload: Bool
    public var title: String
    public var statusLabel: String
    public var snapshot: BrowserSnapshotSurface?
    public var comments: [BrowserCommentSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    public var canOpen: Bool {
        !addressDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        browser: BrowserState,
        emptyTitle: String = "Open a localhost, file, or web page inside QuillCode.",
        emptySubtitle: String = "Use browser comments to keep observations attached to the current page."
    ) {
        self.isVisible = browser.isVisible
        self.tabs = browser.tabs.map { BrowserTabSurface(tab: $0, isActive: $0.id == browser.selectedTabID) }
        self.activeTabID = browser.selectedTabID
        self.canCloseActiveTab = browser.canCloseSelectedTab
        self.addressDraft = browser.addressDraft
        self.currentURL = browser.currentURL
        self.canGoBack = browser.canGoBack
        self.canGoForward = browser.canGoForward
        self.canReload = browser.canReload
        self.title = browser.title
        self.statusLabel = browser.status
        self.snapshot = browser.snapshot.map(BrowserSnapshotSurface.init)
        self.comments = browser.comments.map(BrowserCommentSurface.init)
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
    }
}

public struct BrowserTabSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var urlLabel: String?
    public var isActive: Bool
    public var closeCommandID: String
    public var selectCommandID: String

    public init(tab: BrowserTabState, isActive: Bool) {
        self.id = tab.id
        self.title = tab.displayTitle
        self.urlLabel = tab.currentURL.flatMap { URL(string: $0)?.host } ?? tab.currentURL
        self.isActive = isActive
        self.closeCommandID = "browser-tab-close:\(tab.id.uuidString)"
        self.selectCommandID = "browser-tab-select:\(tab.id.uuidString)"
    }
}

public struct BrowserSnapshotSurface: Codable, Sendable, Hashable {
    public var sourceLabel: String
    public var inspectionDepth: BrowserInspectionDepth
    public var summary: String
    public var details: [String]
    public var outline: [String]
    public var textSnippet: String?

    public var inspectionDepthLabel: String {
        inspectionDepth.label
    }

    private enum CodingKeys: String, CodingKey {
        case sourceLabel
        case inspectionDepth
        case summary
        case details
        case outline
        case textSnippet
    }

    public init(snapshot: BrowserSnapshotState) {
        self.sourceLabel = snapshot.sourceLabel
        self.inspectionDepth = snapshot.inspectionDepth
        self.summary = snapshot.summary
        self.details = snapshot.details
        self.outline = snapshot.outline
        self.textSnippet = snapshot.textSnippet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceLabel = try container.decode(String.self, forKey: .sourceLabel)
        self.inspectionDepth = try container.decodeIfPresent(
            BrowserInspectionDepth.self,
            forKey: .inspectionDepth
        ) ?? .metadataOnly
        self.summary = try container.decode(String.self, forKey: .summary)
        self.details = try container.decodeIfPresent([String].self, forKey: .details) ?? []
        self.outline = try container.decodeIfPresent([String].self, forKey: .outline) ?? []
        self.textSnippet = try container.decodeIfPresent(String.self, forKey: .textSnippet)
    }
}

public struct BrowserCommentSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var url: String
    public var text: String

    public init(comment: BrowserCommentState) {
        self.id = comment.id
        self.url = comment.url
        self.text = comment.text
    }
}
