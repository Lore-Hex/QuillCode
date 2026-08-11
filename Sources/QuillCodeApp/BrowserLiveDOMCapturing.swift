import Foundation

public struct BrowserLiveDOMSnapshot: Sendable, Hashable {
    public static let maximumURLCharacters = 16_384
    public static let maximumTitleCharacters = 512
    public static let maximumVisibleTextCharacters = 12_000
    public static let maximumOutlineCount = 48
    public static let maximumOutlineCharacters = 512
    public static let maximumHTMLCharacters = 512_000
    public static let maximumViewportCharacters = 128

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
        self.finalURL = WorkspaceBrowserRetentionPolicy.boundedURL(finalURL)
        self.title = title.map {
            WorkspaceBrowserRetentionPolicy.bounded(
                $0,
                maximumCharacters: Self.maximumTitleCharacters
            )
        }
        self.visibleText = visibleText.map {
            WorkspaceBrowserRetentionPolicy.bounded(
                $0,
                maximumCharacters: Self.maximumVisibleTextCharacters
            )
        }
        self.outline = outline.prefix(Self.maximumOutlineCount).map {
            WorkspaceBrowserRetentionPolicy.bounded(
                $0,
                maximumCharacters: Self.maximumOutlineCharacters
            )
        }
        self.html = html.map {
            WorkspaceBrowserRetentionPolicy.bounded(
                $0,
                maximumCharacters: Self.maximumHTMLCharacters
            )
        }
        self.viewportDescription = viewportDescription.map {
            WorkspaceBrowserRetentionPolicy.bounded(
                $0,
                maximumCharacters: Self.maximumViewportCharacters
            )
        }
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
