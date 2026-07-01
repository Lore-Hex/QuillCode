import Foundation

public struct BrowserInspectionComment: Codable, Sendable, Hashable {
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(url: String, text: String, createdAt: Date) {
        self.url = url
        self.text = text
        self.createdAt = createdAt
    }
}

public enum BrowserInspectionDepth: String, Codable, Sendable, Hashable, CaseIterable {
    case metadataOnly = "metadata_only"
    case fileMetadata = "file_metadata"
    case staticHTMLSnapshot = "static_html_snapshot"
    case networkHTMLSnapshot = "network_html_snapshot"
    case liveDOMSnapshot = "live_dom_snapshot"

    public var label: String {
        switch self {
        case .metadataOnly:
            return "Metadata only"
        case .fileMetadata:
            return "File metadata"
        case .staticHTMLSnapshot:
            return "Static HTML snapshot"
        case .networkHTMLSnapshot:
            return "Network HTML snapshot"
        case .liveDOMSnapshot:
            return "Live DOM snapshot"
        }
    }
}

public struct BrowserInspectionToolOutput: Codable, Sendable, Hashable {
    public var url: String
    public var title: String
    public var status: String
    public var sourceLabel: String
    public var inspectionDepth: BrowserInspectionDepth
    public var summary: String
    public var details: [String]
    public var outline: [String]
    public var textSnippet: String?
    public var comments: [BrowserInspectionComment]

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case status
        case sourceLabel
        case inspectionDepth
        case summary
        case details
        case outline
        case textSnippet
        case comments
    }

    public init(
        url: String,
        title: String,
        status: String,
        sourceLabel: String,
        inspectionDepth: BrowserInspectionDepth = .metadataOnly,
        summary: String,
        details: [String],
        outline: [String] = [],
        textSnippet: String? = nil,
        comments: [BrowserInspectionComment] = []
    ) {
        self.url = url
        self.title = title
        self.status = status
        self.sourceLabel = sourceLabel
        self.inspectionDepth = inspectionDepth
        self.summary = summary
        self.details = details
        self.outline = outline
        self.textSnippet = textSnippet
        self.comments = comments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.title = try container.decode(String.self, forKey: .title)
        self.status = try container.decode(String.self, forKey: .status)
        self.sourceLabel = try container.decode(String.self, forKey: .sourceLabel)
        self.inspectionDepth = try container.decodeIfPresent(
            BrowserInspectionDepth.self,
            forKey: .inspectionDepth
        ) ?? .metadataOnly
        self.summary = try container.decode(String.self, forKey: .summary)
        self.details = try container.decode([String].self, forKey: .details)
        self.outline = try container.decodeIfPresent([String].self, forKey: .outline) ?? []
        self.textSnippet = try container.decodeIfPresent(String.self, forKey: .textSnippet)
        self.comments = try container.decodeIfPresent(
            [BrowserInspectionComment].self,
            forKey: .comments
        ) ?? []
    }
}
