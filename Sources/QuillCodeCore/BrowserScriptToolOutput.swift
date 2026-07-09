import Foundation

public struct BrowserScriptToolOutput: Codable, Sendable, Hashable {
    public var title: String
    public var url: String
    public var value: String

    public init(title: String, url: String, value: String) {
        self.title = title
        self.url = url
        self.value = value
    }
}
