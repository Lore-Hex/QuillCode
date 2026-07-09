import Foundation

public struct BrowserActionToolOutput: Codable, Sendable, Hashable {
    public var action: String
    public var selector: String
    public var summary: String
    public var submitted: Bool?

    public init(action: String, selector: String, summary: String, submitted: Bool? = nil) {
        self.action = action
        self.selector = selector
        self.summary = summary
        self.submitted = submitted
    }
}
