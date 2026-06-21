import Foundation

public struct BrowserFetchedPage: Sendable, Hashable {
    public static let defaultMaxHTMLBytes = 512_000

    public var finalURL: URL
    public var statusCode: Int?
    public var contentType: String?
    public var html: String
    public var byteCount: Int
    public var wasTruncated: Bool

    public init(
        finalURL: URL,
        statusCode: Int? = nil,
        contentType: String? = nil,
        html: String,
        byteCount: Int? = nil,
        wasTruncated: Bool = false
    ) {
        self.finalURL = finalURL
        self.statusCode = statusCode
        self.contentType = contentType
        self.html = html
        self.byteCount = byteCount ?? html.utf8.count
        self.wasTruncated = wasTruncated
    }
}

public enum BrowserPageFetchFailure: Error, Sendable, Hashable, CustomStringConvertible {
    case unsupportedScheme(String?)
    case invalidResponse
    case httpStatus(Int)
    case nonHTMLContentType(String?)
    case undecodableText
    case transport(String)

    public var description: String {
        switch self {
        case .unsupportedScheme(let scheme):
            return "Browser snapshots support http and https pages, not \(scheme ?? "missing") URLs."
        case .invalidResponse:
            return "The page did not return an HTTP response."
        case .httpStatus(let statusCode):
            return "The page returned HTTP \(statusCode)."
        case .nonHTMLContentType(let contentType):
            return "The page returned \(contentType ?? "a non-HTML response")."
        case .undecodableText:
            return "The page HTML could not be decoded as text."
        case .transport(let message):
            return message
        }
    }
}

public protocol BrowserPageFetching: Sendable {
    func fetchHTML(from url: URL) async throws -> BrowserFetchedPage
}
