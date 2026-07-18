public enum ToolArtifactKind: String, Codable, Sendable, Hashable {
    case file
    case url
    case path
}

public enum ToolArtifactDocumentKind: String, Codable, Sendable, Hashable {
    case appshot
    case pdf
    case markdown
    case document
    case spreadsheet
    case presentation
    case audio
    case video
    case archive

    public var label: String {
        switch self {
        case .appshot:
            return "Appshot"
        case .pdf:
            return "PDF"
        case .markdown:
            return "Markdown"
        case .document:
            return "Document"
        case .spreadsheet:
            return "Spreadsheet"
        case .presentation:
            return "Presentation"
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .archive:
            return "Archive"
        }
    }

    public var systemImage: String {
        switch self {
        case .appshot:
            return "camera.viewfinder"
        case .pdf:
            return "doc.richtext"
        case .markdown:
            return "text.document"
        case .document:
            return "doc.text"
        case .spreadsheet:
            return "tablecells"
        case .presentation:
            return "rectangle.on.rectangle"
        case .audio:
            return "waveform"
        case .video:
            return "play.rectangle"
        case .archive:
            return "archivebox"
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
    public var actionCount: Int?
    public var frameCount: Int?
    public var eventCount: Int?
    public var screenshotURL: String?

    public var metadataLines: [String] {
        [
            appLabel.map { "App: \($0)" },
            viewportLabel.map { "Viewport: \($0)" },
            windowCount.map { "\($0) window\($0 == 1 ? "" : "s")" },
            actionCount.map { "\($0) action\($0 == 1 ? "" : "s")" },
            frameCount.map { "\($0) frame\($0 == 1 ? "" : "s")" },
            eventCount.map { "\($0) event\($0 == 1 ? "" : "s")" },
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
            || actionCount != nil
            || frameCount != nil
            || eventCount != nil
            || screenshotURL != nil
    }

    public init(
        title: String? = nil,
        appLabel: String? = nil,
        summary: String? = nil,
        capturedAt: String? = nil,
        viewportLabel: String? = nil,
        windowCount: Int? = nil,
        actionCount: Int? = nil,
        frameCount: Int? = nil,
        eventCount: Int? = nil,
        screenshotURL: String? = nil
    ) {
        self.title = title
        self.appLabel = appLabel
        self.summary = summary
        self.capturedAt = capturedAt
        self.viewportLabel = viewportLabel
        self.windowCount = windowCount
        self.actionCount = actionCount
        self.frameCount = frameCount
        self.eventCount = eventCount
        self.screenshotURL = screenshotURL
    }
}

public struct ToolArtifactPDFPreview: Codable, Sendable, Hashable {
    public var title: String?
    public var versionLabel: String?
    public var pageCount: Int?
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            versionLabel.map { "Version: \($0)" },
            pageCount.map { "\($0) page\($0 == 1 ? "" : "s")" },
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview: first 512 KB scanned" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        title != nil
            || versionLabel != nil
            || pageCount != nil
            || byteSizeLabel != nil
            || isTruncated
    }

    public init(
        title: String? = nil,
        versionLabel: String? = nil,
        pageCount: Int? = nil,
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.title = title
        self.versionLabel = versionLabel
        self.pageCount = pageCount
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
    }
}

public struct ToolArtifactMarkdownPreview: Codable, Sendable, Hashable {
    public var title: String?
    public var headingCount: Int
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            headingCount > 0 ? "\(headingCount) heading\(headingCount == 1 ? "" : "s")" : nil,
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview: first 64 KB scanned" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        title != nil || !metadataLines.isEmpty
    }

    public init(
        title: String? = nil,
        headingCount: Int = 0,
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.title = title
        self.headingCount = headingCount
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
    }
}

public struct ToolArtifactOfficePreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var entryCount: Int?
    public var worksheetCount: Int?
    public var slideCount: Int?
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            entryCount.map { "\($0) package entr\($0 == 1 ? "y" : "ies")" },
            worksheetCount.map { "\($0) sheet\($0 == 1 ? "" : "s")" },
            slideCount.map { "\($0) slide\($0 == 1 ? "" : "s")" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty
    }

    public init(
        formatLabel: String,
        entryCount: Int? = nil,
        worksheetCount: Int? = nil,
        slideCount: Int? = nil,
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.entryCount = entryCount
        self.worksheetCount = worksheetCount
        self.slideCount = slideCount
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactTablePreview: Codable, Sendable, Hashable {
    public var delimiterLabel: String
    public var rowCountLabel: String
    public var columnCount: Int
    public var headers: [String]
    public var rows: [[String]]
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            "Format: \(delimiterLabel)",
            "\(rowCountLabel), \(columnCount) column\(columnCount == 1 ? "" : "s")",
            isTruncated ? "Preview: first \(rows.count) rows" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !headers.isEmpty || !rows.isEmpty
    }

    public init(
        delimiterLabel: String,
        rowCountLabel: String,
        columnCount: Int,
        headers: [String],
        rows: [[String]],
        isTruncated: Bool = false
    ) {
        self.delimiterLabel = delimiterLabel
        self.rowCountLabel = rowCountLabel
        self.columnCount = columnCount
        self.headers = headers
        self.rows = rows
        self.isTruncated = isTruncated
    }
}

public struct ToolArtifactArchivePreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var entryCount: Int?
    public var topLevelCount: Int?
    public var entryPreviewLabel: String?
    public var uncompressedByteSizeLabel: String?
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            entryCount.map { "\($0) entr\($0 == 1 ? "y" : "ies")" },
            topLevelCount.map { "\($0) top-level item\($0 == 1 ? "" : "s")" },
            entryPreviewLabel.map { "Entries: \($0)" },
            uncompressedByteSizeLabel.map { "Uncompressed: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty
    }

    public init(
        formatLabel: String,
        entryCount: Int? = nil,
        topLevelCount: Int? = nil,
        entryPreviewLabel: String? = nil,
        uncompressedByteSizeLabel: String? = nil,
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.entryCount = entryCount
        self.topLevelCount = topLevelCount
        self.entryPreviewLabel = entryPreviewLabel
        self.uncompressedByteSizeLabel = uncompressedByteSizeLabel
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactMediaPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var title: String?
    public var artist: String?
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            artist.map { "Artist: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        title != nil || !metadataLines.isEmpty
    }

    public init(
        formatLabel: String,
        title: String? = nil,
        artist: String? = nil,
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.title = title
        self.artist = artist
        self.byteSizeLabel = byteSizeLabel
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
    public var pdfPreview: ToolArtifactPDFPreview? {
        ToolArtifactPDFPreviewBuilder.pdfPreview(for: value, kind: kind)
    }
    public var markdownPreview: ToolArtifactMarkdownPreview? {
        ToolArtifactMarkdownPreviewBuilder.markdownPreview(for: value, kind: kind)
    }
    public var officePreview: ToolArtifactOfficePreview? {
        ToolArtifactOfficePreviewBuilder.officePreview(for: value, kind: kind)
    }
    public var tablePreview: ToolArtifactTablePreview? {
        ToolArtifactTablePreviewBuilder.tablePreview(for: value, kind: kind)
    }
    public var archivePreview: ToolArtifactArchivePreview? {
        ToolArtifactArchivePreviewBuilder.archivePreview(for: value, kind: kind)
    }
    public var mediaPreview: ToolArtifactMediaPreview? {
        ToolArtifactMediaPreviewBuilder.mediaPreview(for: value, kind: kind)
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
