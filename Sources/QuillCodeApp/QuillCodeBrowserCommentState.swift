import Foundation

public struct BrowserCommentState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), url: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.url = WorkspaceBrowserRetentionPolicy.bounded(
            url,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumLocationCharacters
        )
        self.text = WorkspaceBrowserRetentionPolicy.bounded(
            text,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumCommentCharacters
        )
        self.createdAt = createdAt
    }
}
