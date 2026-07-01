import Foundation
import QuillCodeCore

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
