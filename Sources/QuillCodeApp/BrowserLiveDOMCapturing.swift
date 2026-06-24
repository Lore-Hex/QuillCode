import Foundation

public struct BrowserLiveDOMSnapshot: Sendable, Hashable {
    public var finalURL: URL
    public var title: String?
    public var visibleText: String?
    public var outline: [String]
    public var html: String?
    public var viewportDescription: String?

    public init(
        finalURL: URL,
        title: String? = nil,
        visibleText: String? = nil,
        outline: [String] = [],
        html: String? = nil,
        viewportDescription: String? = nil
    ) {
        self.finalURL = finalURL
        self.title = title
        self.visibleText = visibleText
        self.outline = outline
        self.html = html
        self.viewportDescription = viewportDescription
    }
}

public enum BrowserLiveDOMCaptureFailure: Error, Sendable, Hashable, CustomStringConvertible {
    case noRenderedSession
    case pageNotReady
    case transport(String)

    public var description: String {
        switch self {
        case .noRenderedSession:
            return "No rendered browser session is attached."
        case .pageNotReady:
            return "The rendered browser page is not ready for DOM capture."
        case .transport(let message):
            return message
        }
    }
}

public protocol BrowserLiveDOMCapturing: Sendable {
    func captureLiveDOM(for url: URL) async throws -> BrowserLiveDOMSnapshot
}
