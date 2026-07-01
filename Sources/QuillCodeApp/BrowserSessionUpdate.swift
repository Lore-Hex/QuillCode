import Foundation

public struct BrowserSessionTabUpdate: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var isActive: Bool

    public init(id: UUID, title: String, url: URL, isActive: Bool) {
        self.id = id
        self.title = title
        self.url = url
        self.isActive = isActive
    }
}

public struct BrowserSessionUpdate: Sendable, Hashable {
    public var tabs: [BrowserSessionTabUpdate]
    public var activeTabID: UUID?

    public var activeTab: BrowserSessionTabUpdate? {
        activeTabID.flatMap { id in tabs.first { $0.id == id } } ?? tabs.first
    }

    public var isEmpty: Bool {
        tabs.isEmpty
    }

    public init(tabs: [BrowserSessionTabUpdate], activeTabID: UUID?) {
        self.tabs = tabs
        let requestedActiveTabID = activeTabID ?? tabs.first { $0.isActive }?.id
        self.activeTabID = tabs.contains { $0.id == requestedActiveTabID } ? requestedActiveTabID : tabs.first?.id
    }
}
