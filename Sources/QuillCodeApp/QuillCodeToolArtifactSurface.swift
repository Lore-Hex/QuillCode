public enum ToolArtifactKind: String, Codable, Sendable, Hashable {
    case file
    case url
    case path
}

public enum ToolArtifactDocumentKind: String, Codable, Sendable, Hashable {
    case appshot
    case pdf
    case document
    case spreadsheet
    case presentation

    public var label: String {
        switch self {
        case .appshot:
            return "Appshot"
        case .pdf:
            return "PDF"
        case .document:
            return "Document"
        case .spreadsheet:
            return "Spreadsheet"
        case .presentation:
            return "Presentation"
        }
    }

    public var systemImage: String {
        switch self {
        case .appshot:
            return "camera.viewfinder"
        case .pdf:
            return "doc.richtext"
        case .document:
            return "doc.text"
        case .spreadsheet:
            return "tablecells"
        case .presentation:
            return "rectangle.on.rectangle"
        }
    }
}

public struct ToolArtifactDocumentPreview: Codable, Sendable, Hashable {
    public var kind: ToolArtifactDocumentKind
    public var typeLabel: String
    public var extensionLabel: String
    public var detail: String
    public var systemImage: String { kind.systemImage }

    public init(kind: ToolArtifactDocumentKind, extensionLabel: String, detail: String) {
        self.kind = kind
        self.typeLabel = kind.label
        self.extensionLabel = extensionLabel
        self.detail = detail
    }
}

public struct ToolArtifactAppshotPreview: Codable, Sendable, Hashable {
    public var title: String?
    public var appLabel: String?
    public var summary: String?
    public var capturedAt: String?
    public var viewportLabel: String?
    public var windowCount: Int?
    public var screenshotURL: String?

    public var metadataLines: [String] {
        [
            appLabel.map { "App: \($0)" },
            viewportLabel.map { "Viewport: \($0)" },
            windowCount.map { "\($0) window\($0 == 1 ? "" : "s")" },
            capturedAt.map { "Captured: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        title != nil
            || appLabel != nil
            || summary != nil
            || capturedAt != nil
            || viewportLabel != nil
            || windowCount != nil
            || screenshotURL != nil
    }

    public init(
        title: String? = nil,
        appLabel: String? = nil,
        summary: String? = nil,
        capturedAt: String? = nil,
        viewportLabel: String? = nil,
        windowCount: Int? = nil,
        screenshotURL: String? = nil
    ) {
        self.title = title
        self.appLabel = appLabel
        self.summary = summary
        self.capturedAt = capturedAt
        self.viewportLabel = viewportLabel
        self.windowCount = windowCount
        self.screenshotURL = screenshotURL
    }
}

public struct ToolArtifactImagePreview: Codable, Sendable, Hashable {
    public var typeLabel: String
    public var extensionLabel: String
    public var dimensionsLabel: String?
    public var detail: String
    public var systemImage: String { "photo" }
    public var typeLine: String {
        [typeLabel, extensionLabel, dimensionsLabel]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    public init(extensionLabel: String, detail: String, dimensionsLabel: String? = nil) {
        self.typeLabel = "Image"
        self.extensionLabel = extensionLabel
        self.dimensionsLabel = dimensionsLabel
        self.detail = detail
    }
}

public struct ToolArtifactState: Codable, Sendable, Hashable, Identifiable {
    public var id: String { value }
    public var value: String
    public var label: String
    public var kind: ToolArtifactKind
    public var textPreview: String?
    public var detail: String { ToolArtifactValueClassifier.detail(for: value, kind: kind) }
    public var href: String? { ToolArtifactValueClassifier.href(for: value, kind: kind) }
    public var isImagePreview: Bool { ToolArtifactImagePreviewBuilder.isImagePreview(for: value, kind: kind) }
    public var previewURL: String? { ToolArtifactImagePreviewBuilder.previewURL(for: value, kind: kind) }
    public var imagePreview: ToolArtifactImagePreview? {
        ToolArtifactImagePreviewBuilder.imagePreview(for: value, kind: kind)
    }
    public var documentPreview: ToolArtifactDocumentPreview? {
        ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind)
    }
    public var appshotPreview: ToolArtifactAppshotPreview? {
        ToolArtifactAppshotPreviewBuilder.appshotPreview(for: value, kind: kind)
    }
    public var isDocumentPreview: Bool { documentPreview != nil }
    public var hasTextPreview: Bool {
        guard let textPreview else { return false }
        return !textPreview.isEmpty
    }

    public init(value: String, textPreview: String? = nil) {
        self.value = value
        self.label = ToolArtifactValueClassifier.label(for: value)
        self.kind = ToolArtifactValueClassifier.kind(for: value)
        self.textPreview = textPreview
    }
}
