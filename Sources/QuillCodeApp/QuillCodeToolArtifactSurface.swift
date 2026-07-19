public enum ToolArtifactKind: String, Codable, Sendable, Hashable {
    case file
    case url
    case path
}

public enum ToolArtifactDocumentKind: String, Codable, Sendable, Hashable {
    case appshot
    case pdf
    case markdown
    case data
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
        case .data:
            return "Data"
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
        case .data:
            return "curlybraces"
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
    public var actionLabels: [String]
    public var frameLabels: [String]
    public var eventLabels: [String]

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
            || !actionLabels.isEmpty
            || !frameLabels.isEmpty
            || !eventLabels.isEmpty
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
        screenshotURL: String? = nil,
        actionLabels: [String] = [],
        frameLabels: [String] = [],
        eventLabels: [String] = []
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
        self.actionLabels = actionLabels
        self.frameLabels = frameLabels
        self.eventLabels = eventLabels
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
    public var contentPreviewLabels: [String]

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
        !metadataLines.isEmpty || !contentPreviewLabels.isEmpty
    }

    public init(
        formatLabel: String,
        entryCount: Int? = nil,
        worksheetCount: Int? = nil,
        slideCount: Int? = nil,
        byteSizeLabel: String? = nil,
        contentPreviewLabels: [String] = []
    ) {
        self.formatLabel = formatLabel
        self.entryCount = entryCount
        self.worksheetCount = worksheetCount
        self.slideCount = slideCount
        self.byteSizeLabel = byteSizeLabel
        self.contentPreviewLabels = contentPreviewLabels
    }
}

public struct ToolArtifactRTFPreview: Codable, Sendable, Hashable {
    public var title: String?
    public var formatLabel: String
    public var encodingLabel: String?
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            encodingLabel.map { "Encoding: \($0)" },
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview: first 64 KB scanned" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        title != nil || !metadataLines.isEmpty
    }

    public init(
        title: String? = nil,
        formatLabel: String = "RTF",
        encodingLabel: String? = nil,
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.title = title
        self.formatLabel = formatLabel
        self.encodingLabel = encodingLabel
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
    }
}

public struct ToolArtifactHTMLPreview: Codable, Sendable, Hashable {
    public var title: String?
    public var heading: String?
    public var linkCount: Int
    public var scriptCount: Int
    public var styleCount: Int
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            "Format: HTML",
            linkCount > 0 ? "\(linkCount) link\(linkCount == 1 ? "" : "s")" : nil,
            scriptCount > 0 ? "\(scriptCount) script\(scriptCount == 1 ? "" : "s")" : nil,
            styleCount > 0 ? "\(styleCount) style block\(styleCount == 1 ? "" : "s")" : nil,
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview: first 64 KB scanned" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        title != nil || heading != nil || !metadataLines.isEmpty
    }

    public init(
        title: String? = nil,
        heading: String? = nil,
        linkCount: Int = 0,
        scriptCount: Int = 0,
        styleCount: Int = 0,
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.title = title
        self.heading = heading
        self.linkCount = linkCount
        self.scriptCount = scriptCount
        self.styleCount = styleCount
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
    }
}

public struct ToolArtifactDiffPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var fileCount: Int
    public var hunkCount: Int
    public var additionCount: Int
    public var deletionCount: Int
    public var changedFileLabels: [String]
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            "\(fileCount) file\(fileCount == 1 ? "" : "s")",
            "\(hunkCount) hunk\(hunkCount == 1 ? "" : "s")",
            "+\(additionCount) / -\(deletionCount)",
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview: first 128 KB scanned" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        fileCount > 0 || hunkCount > 0 || additionCount > 0 || deletionCount > 0 || !changedFileLabels.isEmpty
    }

    public init(
        formatLabel: String = "Unified diff",
        fileCount: Int = 0,
        hunkCount: Int = 0,
        additionCount: Int = 0,
        deletionCount: Int = 0,
        changedFileLabels: [String] = [],
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.formatLabel = formatLabel
        self.fileCount = fileCount
        self.hunkCount = hunkCount
        self.additionCount = additionCount
        self.deletionCount = deletionCount
        self.changedFileLabels = changedFileLabels
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
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

public struct ToolArtifactJSONPreview: Codable, Sendable, Hashable {
    public var rootLabel: String
    public var itemCount: Int?
    public var keyCount: Int?
    public var keyPreviewLabel: String?
    public var keyPreviewLabels: [String]
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Root: \(rootLabel)",
            keyCount.map { "\($0) key\($0 == 1 ? "" : "s")" },
            itemCount.map { "\($0) item\($0 == 1 ? "" : "s")" },
            keyPreviewLabel.map { "Keys: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty || !keyPreviewLabels.isEmpty
    }

    public init(
        rootLabel: String,
        itemCount: Int? = nil,
        keyCount: Int? = nil,
        keyPreviewLabel: String? = nil,
        keyPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil
    ) {
        self.rootLabel = rootLabel
        self.itemCount = itemCount
        self.keyCount = keyCount
        self.keyPreviewLabel = keyPreviewLabel
        self.keyPreviewLabels = keyPreviewLabels
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactIstanbulPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var sourceFileCount: Int
    public var statementCoveredCount: Int?
    public var statementTotalCount: Int?
    public var branchCoveredCount: Int?
    public var branchTotalCount: Int?
    public var functionCoveredCount: Int?
    public var functionTotalCount: Int?
    public var lineCoveredCount: Int?
    public var lineTotalCount: Int?
    public var byteSizeLabel: String?
    public var filePreviewLabels: [String]

    public var statementCoverageLabel: String? {
        coverageLabel(covered: statementCoveredCount, total: statementTotalCount)
    }

    public var branchCoverageLabel: String? {
        coverageLabel(covered: branchCoveredCount, total: branchTotalCount)
    }

    public var functionCoverageLabel: String? {
        coverageLabel(covered: functionCoveredCount, total: functionTotalCount)
    }

    public var lineCoverageLabel: String? {
        coverageLabel(covered: lineCoveredCount, total: lineTotalCount)
    }

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            "\(sourceFileCount) source file\(sourceFileCount == 1 ? "" : "s")",
            lineCoverageLabel.map { "Lines: \($0)" },
            statementCoverageLabel.map { "Statements: \($0)" },
            branchCoverageLabel.map { "Branches: \($0)" },
            functionCoverageLabel.map { "Functions: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        sourceFileCount > 0
            || lineCoverageLabel != nil
            || statementCoverageLabel != nil
            || branchCoverageLabel != nil
            || functionCoverageLabel != nil
            || byteSizeLabel != nil
            || !filePreviewLabels.isEmpty
    }

    public init(
        formatLabel: String = "Istanbul JSON",
        sourceFileCount: Int,
        statementCoveredCount: Int? = nil,
        statementTotalCount: Int? = nil,
        branchCoveredCount: Int? = nil,
        branchTotalCount: Int? = nil,
        functionCoveredCount: Int? = nil,
        functionTotalCount: Int? = nil,
        lineCoveredCount: Int? = nil,
        lineTotalCount: Int? = nil,
        byteSizeLabel: String? = nil,
        filePreviewLabels: [String] = []
    ) {
        self.formatLabel = formatLabel
        self.sourceFileCount = sourceFileCount
        self.statementCoveredCount = statementCoveredCount
        self.statementTotalCount = statementTotalCount
        self.branchCoveredCount = branchCoveredCount
        self.branchTotalCount = branchTotalCount
        self.functionCoveredCount = functionCoveredCount
        self.functionTotalCount = functionTotalCount
        self.lineCoveredCount = lineCoveredCount
        self.lineTotalCount = lineTotalCount
        self.byteSizeLabel = byteSizeLabel
        self.filePreviewLabels = filePreviewLabels
    }

    private func coverageLabel(covered: Int?, total: Int?) -> String? {
        guard let covered, let total, total > 0 else { return nil }
        let percent = (Double(covered) / Double(total)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : String(format: "%.1f%%", rounded)
        return "\(percentLabel) (\(covered)/\(total))"
    }
}

public struct ToolArtifactCoveragePyPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var versionLabel: String?
    public var sourceFileCount: Int
    public var lineCoveredCount: Int?
    public var lineTotalCount: Int?
    public var branchCoveredCount: Int?
    public var branchTotalCount: Int?
    public var byteSizeLabel: String?
    public var filePreviewLabels: [String]

    public var lineCoverageLabel: String? {
        coverageLabel(covered: lineCoveredCount, total: lineTotalCount)
    }

    public var branchCoverageLabel: String? {
        coverageLabel(covered: branchCoveredCount, total: branchTotalCount)
    }

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            versionLabel.map { "Version: \($0)" },
            "\(sourceFileCount) source file\(sourceFileCount == 1 ? "" : "s")",
            lineCoverageLabel.map { "Lines: \($0)" },
            branchCoverageLabel.map { "Branches: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        sourceFileCount > 0
            || lineCoverageLabel != nil
            || branchCoverageLabel != nil
            || byteSizeLabel != nil
            || !filePreviewLabels.isEmpty
    }

    public init(
        formatLabel: String = "coverage.py JSON",
        versionLabel: String? = nil,
        sourceFileCount: Int,
        lineCoveredCount: Int? = nil,
        lineTotalCount: Int? = nil,
        branchCoveredCount: Int? = nil,
        branchTotalCount: Int? = nil,
        byteSizeLabel: String? = nil,
        filePreviewLabels: [String] = []
    ) {
        self.formatLabel = formatLabel
        self.versionLabel = versionLabel
        self.sourceFileCount = sourceFileCount
        self.lineCoveredCount = lineCoveredCount
        self.lineTotalCount = lineTotalCount
        self.branchCoveredCount = branchCoveredCount
        self.branchTotalCount = branchTotalCount
        self.byteSizeLabel = byteSizeLabel
        self.filePreviewLabels = filePreviewLabels
    }

    private func coverageLabel(covered: Int?, total: Int?) -> String? {
        guard let covered, let total, total > 0 else { return nil }
        let percent = (Double(covered) / Double(total)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : String(format: "%.1f%%", rounded)
        return "\(percentLabel) (\(covered)/\(total))"
    }
}

public struct ToolArtifactHARPreview: Codable, Sendable, Hashable {
    public var versionLabel: String?
    public var creatorLabel: String?
    public var entryCount: Int
    public var methodLabels: [String]
    public var statusGroupLabels: [String]
    public var hostPreviewLabels: [String]
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: HAR",
            versionLabel.map { "Version: \($0)" },
            creatorLabel.map { "Creator: \($0)" },
            "\(entryCount) entr\(entryCount == 1 ? "y" : "ies")",
            methodLabels.isEmpty ? nil : "Methods: \(methodLabels.joined(separator: ", "))",
            statusGroupLabels.isEmpty ? nil : "Statuses: \(statusGroupLabels.joined(separator: ", "))",
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        entryCount > 0 || !metadataLines.isEmpty || !hostPreviewLabels.isEmpty
    }

    public init(
        versionLabel: String? = nil,
        creatorLabel: String? = nil,
        entryCount: Int,
        methodLabels: [String] = [],
        statusGroupLabels: [String] = [],
        hostPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil
    ) {
        self.versionLabel = versionLabel
        self.creatorLabel = creatorLabel
        self.entryCount = entryCount
        self.methodLabels = methodLabels
        self.statusGroupLabels = statusGroupLabels
        self.hostPreviewLabels = hostPreviewLabels
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactLCOVPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var sourceFileCount: Int
    public var lineHitCount: Int?
    public var lineFoundCount: Int?
    public var branchHitCount: Int?
    public var branchFoundCount: Int?
    public var functionHitCount: Int?
    public var functionFoundCount: Int?
    public var byteSizeLabel: String?
    public var isTruncated: Bool
    public var sourcePreviewLabels: [String]

    public var lineCoverageLabel: String? {
        coverageLabel(hit: lineHitCount, found: lineFoundCount)
    }

    public var branchCoverageLabel: String? {
        coverageLabel(hit: branchHitCount, found: branchFoundCount)
    }

    public var functionCoverageLabel: String? {
        coverageLabel(hit: functionHitCount, found: functionFoundCount)
    }

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            "\(sourceFileCount) source file\(sourceFileCount == 1 ? "" : "s")",
            lineCoverageLabel.map { "Lines: \($0)" },
            branchCoverageLabel.map { "Branches: \($0)" },
            functionCoverageLabel.map { "Functions: \($0)" },
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview: first 512 KB scanned" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        sourceFileCount > 0
            || lineCoverageLabel != nil
            || branchCoverageLabel != nil
            || functionCoverageLabel != nil
            || byteSizeLabel != nil
            || isTruncated
            || !sourcePreviewLabels.isEmpty
    }

    public init(
        formatLabel: String = "LCOV",
        sourceFileCount: Int,
        lineHitCount: Int? = nil,
        lineFoundCount: Int? = nil,
        branchHitCount: Int? = nil,
        branchFoundCount: Int? = nil,
        functionHitCount: Int? = nil,
        functionFoundCount: Int? = nil,
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false,
        sourcePreviewLabels: [String] = []
    ) {
        self.formatLabel = formatLabel
        self.sourceFileCount = sourceFileCount
        self.lineHitCount = lineHitCount
        self.lineFoundCount = lineFoundCount
        self.branchHitCount = branchHitCount
        self.branchFoundCount = branchFoundCount
        self.functionHitCount = functionHitCount
        self.functionFoundCount = functionFoundCount
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
        self.sourcePreviewLabels = sourcePreviewLabels
    }

    private func coverageLabel(hit: Int?, found: Int?) -> String? {
        guard let hit, let found, found > 0 else { return nil }
        let percent = (Double(hit) / Double(found)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : String(format: "%.1f%%", rounded)
        return "\(percentLabel) (\(hit)/\(found))"
    }
}

public struct ToolArtifactGoCoveragePreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var modeLabel: String?
    public var sourceFileCount: Int
    public var blockCount: Int
    public var statementCoveredCount: Int
    public var statementTotalCount: Int
    public var byteSizeLabel: String?
    public var isTruncated: Bool
    public var sourcePreviewLabels: [String]

    public var statementCoverageLabel: String? {
        coverageLabel(covered: statementCoveredCount, total: statementTotalCount)
    }

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            modeLabel.map { "Mode: \($0)" },
            "\(sourceFileCount) source file\(sourceFileCount == 1 ? "" : "s")",
            "\(blockCount) block\(blockCount == 1 ? "" : "s")",
            statementCoverageLabel.map { "Statements: \($0)" },
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview: first 512 KB scanned" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        sourceFileCount > 0
            || blockCount > 0
            || statementCoverageLabel != nil
            || byteSizeLabel != nil
            || isTruncated
            || !sourcePreviewLabels.isEmpty
    }

    public init(
        formatLabel: String = "Go coverage",
        modeLabel: String? = nil,
        sourceFileCount: Int,
        blockCount: Int,
        statementCoveredCount: Int,
        statementTotalCount: Int,
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false,
        sourcePreviewLabels: [String] = []
    ) {
        self.formatLabel = formatLabel
        self.modeLabel = modeLabel
        self.sourceFileCount = sourceFileCount
        self.blockCount = blockCount
        self.statementCoveredCount = statementCoveredCount
        self.statementTotalCount = statementTotalCount
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
        self.sourcePreviewLabels = sourcePreviewLabels
    }

    private func coverageLabel(covered: Int, total: Int) -> String? {
        guard total > 0 else { return nil }
        let percent = (Double(covered) / Double(total)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : String(format: "%.1f%%", rounded)
        return "\(percentLabel) (\(covered)/\(total))"
    }
}

public struct ToolArtifactSARIFPreview: Codable, Sendable, Hashable {
    public var versionLabel: String?
    public var runCount: Int
    public var resultCount: Int
    public var errorCount: Int
    public var warningCount: Int
    public var noteCount: Int
    public var noneCount: Int
    public var byteSizeLabel: String?
    public var toolPreviewLabels: [String]
    public var rulePreviewLabels: [String]

    public var metadataLines: [String] {
        [
            "Format: SARIF",
            versionLabel.map { "Version: \($0)" },
            "\(runCount) run\(runCount == 1 ? "" : "s")",
            "\(resultCount) result\(resultCount == 1 ? "" : "s")",
            errorCount > 0 ? "Errors: \(errorCount)" : nil,
            warningCount > 0 ? "Warnings: \(warningCount)" : nil,
            noteCount > 0 ? "Notes: \(noteCount)" : nil,
            noneCount > 0 ? "None: \(noneCount)" : nil,
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        runCount > 0
            || resultCount > 0
            || !metadataLines.isEmpty
            || !toolPreviewLabels.isEmpty
            || !rulePreviewLabels.isEmpty
    }

    public init(
        versionLabel: String? = nil,
        runCount: Int,
        resultCount: Int,
        errorCount: Int = 0,
        warningCount: Int = 0,
        noteCount: Int = 0,
        noneCount: Int = 0,
        byteSizeLabel: String? = nil,
        toolPreviewLabels: [String] = [],
        rulePreviewLabels: [String] = []
    ) {
        self.versionLabel = versionLabel
        self.runCount = runCount
        self.resultCount = resultCount
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.noteCount = noteCount
        self.noneCount = noneCount
        self.byteSizeLabel = byteSizeLabel
        self.toolPreviewLabels = toolPreviewLabels
        self.rulePreviewLabels = rulePreviewLabels
    }
}

public struct ToolArtifactNotebookPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var notebookVersionLabel: String?
    public var languageLabel: String?
    public var codeCellCount: Int
    public var markdownCellCount: Int
    public var rawCellCount: Int
    public var byteSizeLabel: String?

    public var cellCount: Int {
        codeCellCount + markdownCellCount + rawCellCount
    }

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            notebookVersionLabel.map { "Version: \($0)" },
            languageLabel.map { "Language: \($0)" },
            "\(cellCount) cell\(cellCount == 1 ? "" : "s")",
            codeCellCount > 0 ? "\(codeCellCount) code" : nil,
            markdownCellCount > 0 ? "\(markdownCellCount) markdown" : nil,
            rawCellCount > 0 ? "\(rawCellCount) raw" : nil,
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty
    }

    public init(
        formatLabel: String = "Jupyter Notebook",
        notebookVersionLabel: String? = nil,
        languageLabel: String? = nil,
        codeCellCount: Int = 0,
        markdownCellCount: Int = 0,
        rawCellCount: Int = 0,
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.notebookVersionLabel = notebookVersionLabel
        self.languageLabel = languageLabel
        self.codeCellCount = codeCellCount
        self.markdownCellCount = markdownCellCount
        self.rawCellCount = rawCellCount
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactJSONLinesPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var recordCountLabel: String
    public var keyPreviewLabel: String?
    public var keyPreviewLabels: [String]
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            recordCountLabel,
            keyPreviewLabel.map { "Keys: \($0)" },
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview: first 64 KB scanned" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty || !keyPreviewLabels.isEmpty
    }

    public init(
        formatLabel: String,
        recordCountLabel: String,
        keyPreviewLabel: String? = nil,
        keyPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.formatLabel = formatLabel
        self.recordCountLabel = recordCountLabel
        self.keyPreviewLabel = keyPreviewLabel
        self.keyPreviewLabels = keyPreviewLabels
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
    }
}

public struct ToolArtifactTOMLPreview: Codable, Sendable, Hashable {
    public var topLevelKeyCount: Int
    public var tableCount: Int
    public var arrayCount: Int
    public var scalarCount: Int
    public var keyPreviewLabel: String?
    public var keyPreviewLabels: [String]
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: TOML",
            "\(topLevelKeyCount) top-level key\(topLevelKeyCount == 1 ? "" : "s")",
            tableCount > 0 ? "\(tableCount) table\(tableCount == 1 ? "" : "s")" : nil,
            arrayCount > 0 ? "\(arrayCount) array\(arrayCount == 1 ? "" : "s")" : nil,
            scalarCount > 0 ? "\(scalarCount) value\(scalarCount == 1 ? "" : "s")" : nil,
            keyPreviewLabel.map { "Keys: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty || !keyPreviewLabels.isEmpty
    }

    public init(
        topLevelKeyCount: Int,
        tableCount: Int = 0,
        arrayCount: Int = 0,
        scalarCount: Int = 0,
        keyPreviewLabel: String? = nil,
        keyPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil
    ) {
        self.topLevelKeyCount = topLevelKeyCount
        self.tableCount = tableCount
        self.arrayCount = arrayCount
        self.scalarCount = scalarCount
        self.keyPreviewLabel = keyPreviewLabel
        self.keyPreviewLabels = keyPreviewLabels
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactINIPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var sectionCount: Int
    public var keyCount: Int
    public var sectionPreviewLabel: String?
    public var sectionPreviewLabels: [String]
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            "\(sectionCount) section\(sectionCount == 1 ? "" : "s")",
            "\(keyCount) key\(keyCount == 1 ? "" : "s")",
            sectionPreviewLabel.map { "Sections: \($0)" },
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview truncated" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty || !sectionPreviewLabels.isEmpty
    }

    public init(
        formatLabel: String,
        sectionCount: Int,
        keyCount: Int,
        sectionPreviewLabel: String? = nil,
        sectionPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.formatLabel = formatLabel
        self.sectionCount = sectionCount
        self.keyCount = keyCount
        self.sectionPreviewLabel = sectionPreviewLabel
        self.sectionPreviewLabels = sectionPreviewLabels
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
    }
}

public struct ToolArtifactDotenvPreview: Codable, Sendable, Hashable {
    public var variableCount: Int
    public var exportedVariableCount: Int
    public var keyPreviewLabel: String?
    public var keyPreviewLabels: [String]
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            "Format: DOTENV",
            "\(variableCount) variable\(variableCount == 1 ? "" : "s")",
            exportedVariableCount > 0 ? "\(exportedVariableCount) exported" : nil,
            keyPreviewLabel.map { "Keys: \($0)" },
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview truncated" : nil
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty || !keyPreviewLabels.isEmpty
    }

    public init(
        variableCount: Int,
        exportedVariableCount: Int = 0,
        keyPreviewLabel: String? = nil,
        keyPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.variableCount = variableCount
        self.exportedVariableCount = exportedVariableCount
        self.keyPreviewLabel = keyPreviewLabel
        self.keyPreviewLabels = keyPreviewLabels
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
    }
}

public struct ToolArtifactYAMLPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var rootLabel: String
    public var keyCount: Int?
    public var itemCount: Int?
    public var mappingCount: Int
    public var sequenceCount: Int
    public var scalarCount: Int
    public var keyPreviewLabel: String?
    public var keyPreviewLabels: [String]
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            "Root: \(rootLabel)",
            keyCount.map { "\($0) key\($0 == 1 ? "" : "s")" },
            itemCount.map { "\($0) item\($0 == 1 ? "" : "s")" },
            mappingCount > 0 ? "\(mappingCount) mapping\(mappingCount == 1 ? "" : "s")" : nil,
            sequenceCount > 0 ? "\(sequenceCount) sequence\(sequenceCount == 1 ? "" : "s")" : nil,
            scalarCount > 0 ? "\(scalarCount) value\(scalarCount == 1 ? "" : "s")" : nil,
            keyPreviewLabel.map { "Keys: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty || !keyPreviewLabels.isEmpty
    }

    public init(
        formatLabel: String,
        rootLabel: String,
        keyCount: Int? = nil,
        itemCount: Int? = nil,
        mappingCount: Int = 0,
        sequenceCount: Int = 0,
        scalarCount: Int = 0,
        keyPreviewLabel: String? = nil,
        keyPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.rootLabel = rootLabel
        self.keyCount = keyCount
        self.itemCount = itemCount
        self.mappingCount = mappingCount
        self.sequenceCount = sequenceCount
        self.scalarCount = scalarCount
        self.keyPreviewLabel = keyPreviewLabel
        self.keyPreviewLabels = keyPreviewLabels
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactXMLPreview: Codable, Sendable, Hashable {
    public var rootElementLabel: String
    public var elementCount: Int
    public var attributeCount: Int
    public var namespaceCount: Int
    public var childPreviewLabel: String?
    public var childPreviewLabels: [String]
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: XML",
            "Root: \(rootElementLabel)",
            "\(elementCount) element\(elementCount == 1 ? "" : "s")",
            attributeCount > 0 ? "\(attributeCount) attribute\(attributeCount == 1 ? "" : "s")" : nil,
            namespaceCount > 0 ? "\(namespaceCount) namespace\(namespaceCount == 1 ? "" : "s")" : nil,
            childPreviewLabel.map { "Children: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty || !childPreviewLabels.isEmpty
    }

    public init(
        rootElementLabel: String,
        elementCount: Int,
        attributeCount: Int = 0,
        namespaceCount: Int = 0,
        childPreviewLabel: String? = nil,
        childPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil
    ) {
        self.rootElementLabel = rootElementLabel
        self.elementCount = elementCount
        self.attributeCount = attributeCount
        self.namespaceCount = namespaceCount
        self.childPreviewLabel = childPreviewLabel
        self.childPreviewLabels = childPreviewLabels
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactJUnitPreview: Codable, Sendable, Hashable {
    public var suiteCount: Int
    public var testCount: Int
    public var failureCount: Int
    public var errorCount: Int
    public var skippedCount: Int
    public var durationLabel: String?
    public var byteSizeLabel: String?
    public var suitePreviewLabels: [String]
    public var failurePreviewLabels: [String]

    public var metadataLines: [String] {
        [
            "Format: JUnit XML",
            "\(suiteCount) suite\(suiteCount == 1 ? "" : "s")",
            "\(testCount) test\(testCount == 1 ? "" : "s")",
            failureCount > 0 ? "Failures: \(failureCount)" : nil,
            errorCount > 0 ? "Errors: \(errorCount)" : nil,
            skippedCount > 0 ? "Skipped: \(skippedCount)" : nil,
            durationLabel.map { "Duration: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        suiteCount > 0
            || testCount > 0
            || !metadataLines.isEmpty
            || !suitePreviewLabels.isEmpty
            || !failurePreviewLabels.isEmpty
    }

    public init(
        suiteCount: Int,
        testCount: Int,
        failureCount: Int = 0,
        errorCount: Int = 0,
        skippedCount: Int = 0,
        durationLabel: String? = nil,
        byteSizeLabel: String? = nil,
        suitePreviewLabels: [String] = [],
        failurePreviewLabels: [String] = []
    ) {
        self.suiteCount = suiteCount
        self.testCount = testCount
        self.failureCount = failureCount
        self.errorCount = errorCount
        self.skippedCount = skippedCount
        self.durationLabel = durationLabel
        self.byteSizeLabel = byteSizeLabel
        self.suitePreviewLabels = suitePreviewLabels
        self.failurePreviewLabels = failurePreviewLabels
    }
}

public struct ToolArtifactCoberturaPreview: Codable, Sendable, Hashable {
    public var versionLabel: String?
    public var packageCount: Int
    public var classCount: Int
    public var lineCoveredCount: Int?
    public var lineValidCount: Int?
    public var branchCoveredCount: Int?
    public var branchValidCount: Int?
    public var lineRateLabel: String?
    public var branchRateLabel: String?
    public var byteSizeLabel: String?
    public var packagePreviewLabels: [String]
    public var classPreviewLabels: [String]

    public var lineCoverageLabel: String? {
        coverageLabel(covered: lineCoveredCount, valid: lineValidCount) ?? lineRateLabel
    }

    public var branchCoverageLabel: String? {
        coverageLabel(covered: branchCoveredCount, valid: branchValidCount) ?? branchRateLabel
    }

    public var metadataLines: [String] {
        [
            "Format: Cobertura XML",
            versionLabel.map { "Version: \($0)" },
            "\(packageCount) package\(packageCount == 1 ? "" : "s")",
            "\(classCount) class\(classCount == 1 ? "" : "es")",
            lineCoverageLabel.map { "Lines: \($0)" },
            branchCoverageLabel.map { "Branches: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        packageCount > 0
            || classCount > 0
            || lineCoverageLabel != nil
            || branchCoverageLabel != nil
            || byteSizeLabel != nil
            || !packagePreviewLabels.isEmpty
            || !classPreviewLabels.isEmpty
    }

    public init(
        versionLabel: String? = nil,
        packageCount: Int,
        classCount: Int,
        lineCoveredCount: Int? = nil,
        lineValidCount: Int? = nil,
        branchCoveredCount: Int? = nil,
        branchValidCount: Int? = nil,
        lineRateLabel: String? = nil,
        branchRateLabel: String? = nil,
        byteSizeLabel: String? = nil,
        packagePreviewLabels: [String] = [],
        classPreviewLabels: [String] = []
    ) {
        self.versionLabel = versionLabel
        self.packageCount = packageCount
        self.classCount = classCount
        self.lineCoveredCount = lineCoveredCount
        self.lineValidCount = lineValidCount
        self.branchCoveredCount = branchCoveredCount
        self.branchValidCount = branchValidCount
        self.lineRateLabel = lineRateLabel
        self.branchRateLabel = branchRateLabel
        self.byteSizeLabel = byteSizeLabel
        self.packagePreviewLabels = packagePreviewLabels
        self.classPreviewLabels = classPreviewLabels
    }

    private func coverageLabel(covered: Int?, valid: Int?) -> String? {
        guard let covered, let valid, valid > 0 else { return nil }
        let percent = (Double(covered) / Double(valid)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : "\(rounded)%"
        return "\(percentLabel) (\(covered)/\(valid))"
    }
}

public struct ToolArtifactCloverPreview: Codable, Sendable, Hashable {
    public var packageCount: Int?
    public var fileCount: Int?
    public var classCount: Int?
    public var methodCoveredCount: Int?
    public var methodCount: Int?
    public var statementCoveredCount: Int?
    public var statementCount: Int?
    public var conditionalCoveredCount: Int?
    public var conditionalCount: Int?
    public var elementCoveredCount: Int?
    public var elementCount: Int?
    public var byteSizeLabel: String?
    public var projectPreviewLabels: [String]
    public var filePreviewLabels: [String]

    public var elementCoverageLabel: String? {
        coverageLabel(covered: elementCoveredCount, total: elementCount)
    }

    public var methodCoverageLabel: String? {
        coverageLabel(covered: methodCoveredCount, total: methodCount)
    }

    public var statementCoverageLabel: String? {
        coverageLabel(covered: statementCoveredCount, total: statementCount)
    }

    public var conditionalCoverageLabel: String? {
        coverageLabel(covered: conditionalCoveredCount, total: conditionalCount)
    }

    public var metadataLines: [String] {
        [
            "Format: Clover XML",
            packageCount.map { "\($0) package\($0 == 1 ? "" : "s")" },
            fileCount.map { "\($0) file\($0 == 1 ? "" : "s")" },
            classCount.map { "\($0) class\($0 == 1 ? "" : "es")" },
            elementCoverageLabel.map { "Elements: \($0)" },
            methodCoverageLabel.map { "Methods: \($0)" },
            statementCoverageLabel.map { "Statements: \($0)" },
            conditionalCoverageLabel.map { "Conditionals: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        packageCount != nil
            || fileCount != nil
            || classCount != nil
            || elementCoverageLabel != nil
            || methodCoverageLabel != nil
            || statementCoverageLabel != nil
            || conditionalCoverageLabel != nil
            || byteSizeLabel != nil
            || !projectPreviewLabels.isEmpty
            || !filePreviewLabels.isEmpty
    }

    public init(
        packageCount: Int? = nil,
        fileCount: Int? = nil,
        classCount: Int? = nil,
        methodCoveredCount: Int? = nil,
        methodCount: Int? = nil,
        statementCoveredCount: Int? = nil,
        statementCount: Int? = nil,
        conditionalCoveredCount: Int? = nil,
        conditionalCount: Int? = nil,
        elementCoveredCount: Int? = nil,
        elementCount: Int? = nil,
        byteSizeLabel: String? = nil,
        projectPreviewLabels: [String] = [],
        filePreviewLabels: [String] = []
    ) {
        self.packageCount = packageCount
        self.fileCount = fileCount
        self.classCount = classCount
        self.methodCoveredCount = methodCoveredCount
        self.methodCount = methodCount
        self.statementCoveredCount = statementCoveredCount
        self.statementCount = statementCount
        self.conditionalCoveredCount = conditionalCoveredCount
        self.conditionalCount = conditionalCount
        self.elementCoveredCount = elementCoveredCount
        self.elementCount = elementCount
        self.byteSizeLabel = byteSizeLabel
        self.projectPreviewLabels = projectPreviewLabels
        self.filePreviewLabels = filePreviewLabels
    }

    private func coverageLabel(covered: Int?, total: Int?) -> String? {
        guard let covered, let total, total > 0 else { return nil }
        let percent = (Double(covered) / Double(total)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : "\(rounded)%"
        return "\(percentLabel) (\(covered)/\(total))"
    }
}

public struct ToolArtifactJaCoCoPreview: Codable, Sendable, Hashable {
    public var reportNameLabel: String?
    public var packageCount: Int
    public var sourceFileCount: Int
    public var classCount: Int
    public var lineCoveredCount: Int?
    public var lineMissedCount: Int?
    public var branchCoveredCount: Int?
    public var branchMissedCount: Int?
    public var methodCoveredCount: Int?
    public var methodMissedCount: Int?
    public var classCoveredCount: Int?
    public var classMissedCount: Int?
    public var byteSizeLabel: String?
    public var packagePreviewLabels: [String]
    public var sourceFilePreviewLabels: [String]

    public var lineCoverageLabel: String? {
        coverageLabel(covered: lineCoveredCount, missed: lineMissedCount)
    }

    public var branchCoverageLabel: String? {
        coverageLabel(covered: branchCoveredCount, missed: branchMissedCount)
    }

    public var methodCoverageLabel: String? {
        coverageLabel(covered: methodCoveredCount, missed: methodMissedCount)
    }

    public var classCoverageLabel: String? {
        coverageLabel(covered: classCoveredCount, missed: classMissedCount)
    }

    public var metadataLines: [String] {
        [
            "Format: JaCoCo XML",
            reportNameLabel.map { "Report: \($0)" },
            "\(packageCount) package\(packageCount == 1 ? "" : "s")",
            "\(sourceFileCount) source file\(sourceFileCount == 1 ? "" : "s")",
            "\(classCount) class\(classCount == 1 ? "" : "es")",
            lineCoverageLabel.map { "Lines: \($0)" },
            branchCoverageLabel.map { "Branches: \($0)" },
            methodCoverageLabel.map { "Methods: \($0)" },
            classCoverageLabel.map { "Classes: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        packageCount > 0
            || sourceFileCount > 0
            || classCount > 0
            || lineCoverageLabel != nil
            || branchCoverageLabel != nil
            || methodCoverageLabel != nil
            || classCoverageLabel != nil
            || byteSizeLabel != nil
            || !packagePreviewLabels.isEmpty
            || !sourceFilePreviewLabels.isEmpty
    }

    public init(
        reportNameLabel: String? = nil,
        packageCount: Int,
        sourceFileCount: Int,
        classCount: Int,
        lineCoveredCount: Int? = nil,
        lineMissedCount: Int? = nil,
        branchCoveredCount: Int? = nil,
        branchMissedCount: Int? = nil,
        methodCoveredCount: Int? = nil,
        methodMissedCount: Int? = nil,
        classCoveredCount: Int? = nil,
        classMissedCount: Int? = nil,
        byteSizeLabel: String? = nil,
        packagePreviewLabels: [String] = [],
        sourceFilePreviewLabels: [String] = []
    ) {
        self.reportNameLabel = reportNameLabel
        self.packageCount = packageCount
        self.sourceFileCount = sourceFileCount
        self.classCount = classCount
        self.lineCoveredCount = lineCoveredCount
        self.lineMissedCount = lineMissedCount
        self.branchCoveredCount = branchCoveredCount
        self.branchMissedCount = branchMissedCount
        self.methodCoveredCount = methodCoveredCount
        self.methodMissedCount = methodMissedCount
        self.classCoveredCount = classCoveredCount
        self.classMissedCount = classMissedCount
        self.byteSizeLabel = byteSizeLabel
        self.packagePreviewLabels = packagePreviewLabels
        self.sourceFilePreviewLabels = sourceFilePreviewLabels
    }

    private func coverageLabel(covered: Int?, missed: Int?) -> String? {
        guard let covered, let missed else { return nil }
        let total = covered + missed
        guard total > 0 else { return nil }
        let percent = (Double(covered) / Double(total)) * 100
        let rounded = (percent * 10).rounded() / 10
        let percentLabel = rounded == rounded.rounded()
            ? "\(Int(rounded))%"
            : "\(rounded)%"
        return "\(percentLabel) (\(covered)/\(total))"
    }
}

public struct ToolArtifactPropertyListPreview: Codable, Sendable, Hashable {
    public var rootLabel: String
    public var formatLabel: String?
    public var keyCount: Int?
    public var itemCount: Int?
    public var dictionaryCount: Int
    public var arrayCount: Int
    public var scalarCount: Int
    public var keyPreviewLabel: String?
    public var keyPreviewLabels: [String]
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel ?? "PLIST")",
            "Root: \(rootLabel)",
            keyCount.map { "\($0) key\($0 == 1 ? "" : "s")" },
            itemCount.map { "\($0) item\($0 == 1 ? "" : "s")" },
            dictionaryCount > 0 ? "\(dictionaryCount) dictionar\(dictionaryCount == 1 ? "y" : "ies")" : nil,
            arrayCount > 0 ? "\(arrayCount) array\(arrayCount == 1 ? "" : "s")" : nil,
            scalarCount > 0 ? "\(scalarCount) value\(scalarCount == 1 ? "" : "s")" : nil,
            keyPreviewLabel.map { "Keys: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty || !keyPreviewLabels.isEmpty
    }

    public init(
        rootLabel: String,
        formatLabel: String? = nil,
        keyCount: Int? = nil,
        itemCount: Int? = nil,
        dictionaryCount: Int = 0,
        arrayCount: Int = 0,
        scalarCount: Int = 0,
        keyPreviewLabel: String? = nil,
        keyPreviewLabels: [String] = [],
        byteSizeLabel: String? = nil
    ) {
        self.rootLabel = rootLabel
        self.formatLabel = formatLabel
        self.keyCount = keyCount
        self.itemCount = itemCount
        self.dictionaryCount = dictionaryCount
        self.arrayCount = arrayCount
        self.scalarCount = scalarCount
        self.keyPreviewLabel = keyPreviewLabel
        self.keyPreviewLabels = keyPreviewLabels
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactSQLitePreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var pageSize: Int?
    public var pageCount: Int?
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            pageSize.map { "Page size: \($0) bytes" },
            pageCount.map { "\($0) page\($0 == 1 ? "" : "s")" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty
    }

    public init(
        formatLabel: String = "SQLite",
        pageSize: Int? = nil,
        pageCount: Int? = nil,
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.pageSize = pageSize
        self.pageCount = pageCount
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactWebAssemblyPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var version: UInt32?
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            version.map { "Version: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty
    }

    public init(
        formatLabel: String = "WebAssembly",
        version: UInt32? = nil,
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.version = version
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactFontPreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var flavorLabel: String?
    public var tableCount: Int?
    public var byteSizeLabel: String?
    public var declaredByteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            flavorLabel.map { "Flavor: \($0)" },
            tableCount.map { "\($0) table\($0 == 1 ? "" : "s")" },
            declaredByteSizeLabel.map { "Declared size: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty
    }

    public init(
        formatLabel: String,
        flavorLabel: String? = nil,
        tableCount: Int? = nil,
        byteSizeLabel: String? = nil,
        declaredByteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.flavorLabel = flavorLabel
        self.tableCount = tableCount
        self.byteSizeLabel = byteSizeLabel
        self.declaredByteSizeLabel = declaredByteSizeLabel
    }
}

public struct ToolArtifactExecutablePreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var architectureLabel: String?
    public var bitnessLabel: String?
    public var endianLabel: String?
    public var byteSizeLabel: String?

    public var metadataLines: [String] {
        [
            "Format: \(formatLabel)",
            architectureLabel.map { "Architecture: \($0)" },
            bitnessLabel.map { "Class: \($0)" },
            endianLabel.map { "Endian: \($0)" },
            byteSizeLabel.map { "Size: \($0)" }
        ].compactMap { $0 }
    }

    public var hasDisplayContent: Bool {
        !metadataLines.isEmpty
    }

    public init(
        formatLabel: String,
        architectureLabel: String? = nil,
        bitnessLabel: String? = nil,
        endianLabel: String? = nil,
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.architectureLabel = architectureLabel
        self.bitnessLabel = bitnessLabel
        self.endianLabel = endianLabel
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactArchivePreview: Codable, Sendable, Hashable {
    public var formatLabel: String
    public var entryCount: Int?
    public var topLevelCount: Int?
    public var entryPreviewLabel: String?
    public var entryPreviewLabels: [String]
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
        !metadataLines.isEmpty || !entryPreviewLabels.isEmpty
    }

    public init(
        formatLabel: String,
        entryCount: Int? = nil,
        topLevelCount: Int? = nil,
        entryPreviewLabel: String? = nil,
        entryPreviewLabels: [String] = [],
        uncompressedByteSizeLabel: String? = nil,
        byteSizeLabel: String? = nil
    ) {
        self.formatLabel = formatLabel
        self.entryCount = entryCount
        self.topLevelCount = topLevelCount
        self.entryPreviewLabel = entryPreviewLabel
        self.entryPreviewLabels = entryPreviewLabels
        self.uncompressedByteSizeLabel = uncompressedByteSizeLabel
        self.byteSizeLabel = byteSizeLabel
    }
}

public struct ToolArtifactMediaPreview: Codable, Sendable, Hashable {
    public var kind: ToolArtifactDocumentKind?
    public var formatLabel: String
    public var title: String?
    public var artist: String?
    public var byteSizeLabel: String?
    public var playbackURL: String?

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
        kind: ToolArtifactDocumentKind? = nil,
        formatLabel: String,
        title: String? = nil,
        artist: String? = nil,
        byteSizeLabel: String? = nil,
        playbackURL: String? = nil
    ) {
        self.kind = kind
        self.formatLabel = formatLabel
        self.title = title
        self.artist = artist
        self.byteSizeLabel = byteSizeLabel
        self.playbackURL = playbackURL
    }
}

public struct ToolArtifactSourceTextPreview: Codable, Sendable, Hashable {
    public var typeLabel: String
    public var lineCountLabel: String
    public var byteSizeLabel: String?
    public var isTruncated: Bool

    public var metadataLines: [String] {
        [
            "Type: \(typeLabel)",
            lineCountLabel,
            byteSizeLabel.map { "Size: \($0)" },
            isTruncated ? "Preview truncated" : nil
        ].compactMap { $0 }
    }

    public init(
        typeLabel: String,
        lineCountLabel: String,
        byteSizeLabel: String? = nil,
        isTruncated: Bool = false
    ) {
        self.typeLabel = typeLabel
        self.lineCountLabel = lineCountLabel
        self.byteSizeLabel = byteSizeLabel
        self.isTruncated = isTruncated
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
    public var rtfPreview: ToolArtifactRTFPreview? {
        ToolArtifactRTFPreviewBuilder.rtfPreview(for: value, kind: kind)
    }
    public var htmlPreview: ToolArtifactHTMLPreview? {
        ToolArtifactHTMLPreviewBuilder.htmlPreview(for: value, kind: kind)
    }
    public var diffPreview: ToolArtifactDiffPreview? {
        ToolArtifactDiffPreviewBuilder.diffPreview(for: value, kind: kind)
    }
    public var tablePreview: ToolArtifactTablePreview? {
        ToolArtifactTablePreviewBuilder.tablePreview(for: value, kind: kind)
    }
    public var jsonPreview: ToolArtifactJSONPreview? {
        ToolArtifactJSONPreviewBuilder.jsonPreview(for: value, kind: kind)
    }
    public var istanbulPreview: ToolArtifactIstanbulPreview? {
        ToolArtifactIstanbulPreviewBuilder.istanbulPreview(for: value, kind: kind)
    }
    public var coveragePyPreview: ToolArtifactCoveragePyPreview? {
        ToolArtifactCoveragePyPreviewBuilder.coveragePyPreview(for: value, kind: kind)
    }
    public var harPreview: ToolArtifactHARPreview? {
        ToolArtifactHARPreviewBuilder.harPreview(for: value, kind: kind)
    }
    public var lcovPreview: ToolArtifactLCOVPreview? {
        ToolArtifactLCOVPreviewBuilder.lcovPreview(for: value, kind: kind)
    }
    public var goCoveragePreview: ToolArtifactGoCoveragePreview? {
        ToolArtifactGoCoveragePreviewBuilder.goCoveragePreview(for: value, kind: kind)
    }
    public var sarifPreview: ToolArtifactSARIFPreview? {
        ToolArtifactSARIFPreviewBuilder.sarifPreview(for: value, kind: kind)
    }
    public var notebookPreview: ToolArtifactNotebookPreview? {
        ToolArtifactNotebookPreviewBuilder.notebookPreview(for: value, kind: kind)
    }
    public var jsonLinesPreview: ToolArtifactJSONLinesPreview? {
        ToolArtifactJSONLinesPreviewBuilder.jsonLinesPreview(for: value, kind: kind)
    }
    public var tomlPreview: ToolArtifactTOMLPreview? {
        ToolArtifactTOMLPreviewBuilder.tomlPreview(for: value, kind: kind)
    }
    public var iniPreview: ToolArtifactINIPreview? {
        ToolArtifactINIPreviewBuilder.iniPreview(for: value, kind: kind)
    }
    public var dotenvPreview: ToolArtifactDotenvPreview? {
        ToolArtifactDotenvPreviewBuilder.dotenvPreview(for: value, kind: kind)
    }
    public var yamlPreview: ToolArtifactYAMLPreview? {
        ToolArtifactYAMLPreviewBuilder.yamlPreview(for: value, kind: kind)
    }
    public var junitPreview: ToolArtifactJUnitPreview? {
        ToolArtifactJUnitPreviewBuilder.junitPreview(for: value, kind: kind)
    }
    public var coberturaPreview: ToolArtifactCoberturaPreview? {
        ToolArtifactCoberturaPreviewBuilder.coberturaPreview(for: value, kind: kind)
    }
    public var cloverPreview: ToolArtifactCloverPreview? {
        ToolArtifactCloverPreviewBuilder.cloverPreview(for: value, kind: kind)
    }
    public var jaCoCoPreview: ToolArtifactJaCoCoPreview? {
        ToolArtifactJaCoCoPreviewBuilder.jaCoCoPreview(for: value, kind: kind)
    }
    public var xmlPreview: ToolArtifactXMLPreview? {
        ToolArtifactXMLPreviewBuilder.xmlPreview(for: value, kind: kind)
    }
    public var propertyListPreview: ToolArtifactPropertyListPreview? {
        ToolArtifactPropertyListPreviewBuilder.propertyListPreview(for: value, kind: kind)
    }
    public var sqlitePreview: ToolArtifactSQLitePreview? {
        ToolArtifactSQLitePreviewBuilder.sqlitePreview(for: value, kind: kind)
    }
    public var webAssemblyPreview: ToolArtifactWebAssemblyPreview? {
        ToolArtifactWebAssemblyPreviewBuilder.webAssemblyPreview(for: value, kind: kind)
    }
    public var fontPreview: ToolArtifactFontPreview? {
        ToolArtifactFontPreviewBuilder.fontPreview(for: value, kind: kind)
    }
    public var executablePreview: ToolArtifactExecutablePreview? {
        ToolArtifactExecutablePreviewBuilder.executablePreview(for: value, kind: kind)
    }
    public var archivePreview: ToolArtifactArchivePreview? {
        ToolArtifactArchivePreviewBuilder.archivePreview(for: value, kind: kind)
    }
    public var mediaPreview: ToolArtifactMediaPreview? {
        ToolArtifactMediaPreviewBuilder.mediaPreview(for: value, kind: kind)
    }
    public var sourceTextPreview: ToolArtifactSourceTextPreview? {
        guard hasTextPreview else { return nil }
        return ToolArtifactTextPreviewBuilder.sourceTextPreview(for: value, kind: kind)
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
