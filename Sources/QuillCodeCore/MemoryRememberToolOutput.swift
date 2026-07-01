import Foundation

public struct MemoryRememberToolOutput: Codable, Sendable, Hashable {
    public var title: String
    public var relativePath: String
    public var content: String

    public init(title: String, relativePath: String, content: String) {
        self.title = title
        self.relativePath = relativePath
        self.content = content
    }
}
