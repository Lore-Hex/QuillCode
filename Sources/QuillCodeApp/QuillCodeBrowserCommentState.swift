import Foundation

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
