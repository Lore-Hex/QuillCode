import Foundation

public enum ToolCardStatus: String, Codable, Sendable, Hashable {
    case queued
    case running
    case done
    case failed
    case review
}

public enum ToolCardReviewState: String, Codable, Sendable, Hashable {
    case none
    case ready
    case needsReview
}

public enum ToolCardActionKind: String, Codable, Sendable, Hashable {
    case approve
    case deny
}

public enum ToolCardActionStyle: String, Codable, Sendable, Hashable {
    case primary
    case secondary
    case destructive
}

public struct ToolCardActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var kind: ToolCardActionKind
    public var requestID: String
    public var style: ToolCardActionStyle
    public var systemImage: String?

    public init(
        id: String? = nil,
        title: String,
        kind: ToolCardActionKind,
        requestID: String,
        style: ToolCardActionStyle,
        systemImage: String? = nil
    ) {
        self.id = id ?? "tool-card-action-\(kind.rawValue)-\(requestID)"
        self.title = title
        self.kind = kind
        self.requestID = requestID
        self.style = style
        self.systemImage = systemImage
    }
}

public enum ToolCardDensity: String, Codable, Sendable, Hashable {
    case collapsed
    case peek
    case expanded
}

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

public struct ToolArtifactImagePreview: Codable, Sendable, Hashable {
    public var typeLabel: String
    public var extensionLabel: String
    public var detail: String
    public var systemImage: String { "photo" }

    public init(extensionLabel: String, detail: String) {
        self.typeLabel = "Image"
        self.extensionLabel = extensionLabel
        self.detail = detail
    }
}

public struct ToolArtifactState: Codable, Sendable, Hashable, Identifiable {
    public var id: String { value }
    public var value: String
    public var label: String
    public var kind: ToolArtifactKind
    public var textPreview: String?
    public var detail: String { Self.detail(for: value, kind: kind) }
    public var href: String? { Self.href(for: value, kind: kind) }
    public var isImagePreview: Bool { Self.isImagePreview(for: value, kind: kind) }
    public var previewURL: String? { Self.previewURL(for: value, kind: kind) }
    public var imagePreview: ToolArtifactImagePreview? {
        Self.imagePreview(for: value, kind: kind)
    }
    public var documentPreview: ToolArtifactDocumentPreview? {
        Self.documentPreview(for: value, kind: kind)
    }
    public var isDocumentPreview: Bool { documentPreview != nil }
    public var hasTextPreview: Bool {
        guard let textPreview else { return false }
        return !textPreview.isEmpty
    }

    public init(value: String, textPreview: String? = nil) {
        self.value = value
        self.label = Self.label(for: value)
        self.kind = Self.kind(for: value)
        self.textPreview = textPreview
    }

    private static func kind(for value: String) -> ToolArtifactKind {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else {
            return value.hasPrefix("/") ? .file : .path
        }
        if scheme == "http" || scheme == "https" {
            return .url
        }
        if isInlineImageData(value) {
            return .url
        }
        if scheme == "file" {
            return .file
        }
        return .path
    }

    private static func label(for value: String) -> String {
        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "data"].contains(scheme) {
            if scheme == "data" {
                return isInlineImageData(value) ? "Inline image" : value
            }
            if scheme == "http" || scheme == "https" {
                let host = url.host ?? value
                return url.path.isEmpty || url.path == "/" ? host : "\(host)\(url.path)"
            }
            if !url.lastPathComponent.isEmpty {
                return url.lastPathComponent
            }
            return value
        }
        let url = URL(fileURLWithPath: value)
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? value : lastPathComponent
    }

    private static func detail(for value: String, kind: ToolArtifactKind) -> String {
        switch kind {
        case .url:
            if isInlineImageData(value) {
                return "Image artifact"
            }
            guard let url = URL(string: value), let host = url.host else { return value }
            return url.path.isEmpty || url.path == "/" ? host : "\(host)\(url.path)"
        case .file:
            let url = value.hasPrefix("file://")
                ? URL(string: value)
                : URL(fileURLWithPath: value)
            guard let path = url?.deletingLastPathComponent().path, !path.isEmpty else {
                return "File artifact"
            }
            return path
        case .path:
            return value
        }
    }

    private static func isImagePreview(for value: String, kind: ToolArtifactKind) -> Bool {
        if isInlineImageData(value) {
            return true
        }
        guard kind == .file || kind == .url else {
            return false
        }
        return imageExtensions.contains(pathExtension(for: value))
    }

    private static func previewURL(for value: String, kind: ToolArtifactKind) -> String? {
        if isInlineImageData(value) {
            return value
        }
        guard isImagePreview(for: value, kind: kind) else {
            return nil
        }
        return href(for: value, kind: kind)
    }

    private static func imagePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactImagePreview? {
        guard isImagePreview(for: value, kind: kind) else {
            return nil
        }
        return ToolArtifactImagePreview(
            extensionLabel: imagePreviewExtension(for: value),
            detail: detail(for: value, kind: kind)
        )
    }

    private static func href(for value: String, kind: ToolArtifactKind) -> String? {
        switch kind {
        case .url:
            return value
        case .file:
            if value.hasPrefix("file://") {
                return value
            }
            if value.hasPrefix("/") {
                return URL(fileURLWithPath: value).absoluteString
            }
            return nil
        case .path:
            return nil
        }
    }

    private static func documentPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactDocumentPreview? {
        guard kind == .file || kind == .url, !isImagePreview(for: value, kind: kind) else {
            return nil
        }
        let fileExtension = previewExtension(for: value)
        guard let documentKind = documentKindsByExtension[fileExtension] else {
            return nil
        }
        return ToolArtifactDocumentPreview(
            kind: documentKind,
            extensionLabel: fileExtension.uppercased(),
            detail: detail(for: value, kind: kind)
        )
    }

    private static func previewExtension(for value: String) -> String {
        let filename: String
        if let url = URL(string: value), url.scheme != nil {
            filename = url.lastPathComponent.lowercased()
        } else {
            filename = URL(fileURLWithPath: value).lastPathComponent.lowercased()
        }
        if filename.hasSuffix(".appshot.json") {
            return "appshot"
        }
        return pathExtension(for: value)
    }

    private static func imagePreviewExtension(for value: String) -> String {
        if let subtype = inlineImageSubtype(for: value) {
            return normalizedImageExtension(subtype)
        }
        let fileExtension = pathExtension(for: value)
        return fileExtension.isEmpty ? "IMAGE" : normalizedImageExtension(fileExtension)
    }

    private static func inlineImageSubtype(for value: String) -> String? {
        let lowercasedValue = value.lowercased()
        guard lowercasedValue.hasPrefix("data:image/") else {
            return nil
        }
        let afterPrefix = lowercasedValue.dropFirst("data:image/".count)
        let delimiterIndex = afterPrefix.firstIndex { character in
            character == ";" || character == ","
        }
        let subtype = delimiterIndex.map { afterPrefix[..<$0] } ?? afterPrefix[...]
        return subtype.isEmpty ? nil : String(subtype)
    }

    private static func normalizedImageExtension(_ rawExtension: String) -> String {
        let baseExtension = rawExtension
            .lowercased()
            .split(separator: "+", maxSplits: 1)
            .first
            .map(String.init) ?? rawExtension.lowercased()
        switch baseExtension {
        case "jpeg":
            return "JPG"
        case "svg":
            return "SVG"
        case "x-icon":
            return "ICO"
        default:
            return baseExtension.uppercased()
        }
    }

    private static func pathExtension(for value: String) -> String {
        if let url = URL(string: value), url.scheme != nil {
            return url.pathExtension.lowercased()
        }
        return URL(fileURLWithPath: value).pathExtension.lowercased()
    }

    private static func isInlineImageData(_ value: String) -> Bool {
        value.lowercased().hasPrefix("data:image/")
    }

    private static let imageExtensions: Set<String> = [
        "png",
        "jpg",
        "jpeg",
        "gif",
        "webp",
        "heic",
        "tif",
        "tiff",
        "bmp"
    ]

    private static let documentKindsByExtension: [String: ToolArtifactDocumentKind] = [
        "appshot": .appshot,
        "pdf": .pdf,
        "doc": .document,
        "docx": .document,
        "odt": .document,
        "pages": .document,
        "rtf": .document,
        "numbers": .spreadsheet,
        "ods": .spreadsheet,
        "xls": .spreadsheet,
        "xlsx": .spreadsheet,
        "key": .presentation,
        "odp": .presentation,
        "ppt": .presentation,
        "pptx": .presentation
    ]
}

enum ToolArtifactPreviewBuilder {
    static func textPreview(for value: String) -> String? {
        let artifact = ToolArtifactState(value: value)
        guard artifact.kind == .file,
              !artifact.isImagePreview,
              artifact.documentPreview?.kind != .appshot
        else { return nil }
        guard let fileURL = localArtifactFileURL(for: value) else { return nil }
        guard isTextPreviewCandidate(fileURL) else { return nil }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { return nil }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            guard let data = try handle.read(upToCount: byteLimit + 1),
                  !data.isEmpty
            else { return nil }

            var wasTruncated = data.count > byteLimit
            let previewData = Data(data.prefix(byteLimit))
            guard !previewData.contains(0),
                  var text = String(data: previewData, encoding: .utf8)
            else { return nil }

            text = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > lineLimit {
                wasTruncated = true
                text = lines.prefix(lineLimit).joined(separator: "\n")
            }
            if wasTruncated {
                if !text.hasSuffix("\n") {
                    text += "\n"
                }
                text += "..."
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else { return nil }
        return url
    }

    private static func isTextPreviewCandidate(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        if filenames.contains(filename) {
            return true
        }
        let pathExtension = url.pathExtension.lowercased()
        return extensions.contains(pathExtension)
    }

    private static let byteLimit = 6 * 1024
    private static let lineLimit = 80
    private static let filenames: Set<String> = [
        ".env.example",
        ".gitignore",
        "dockerfile",
        "gemfile",
        "license",
        "makefile",
        "podfile",
        "readme"
    ]
    private static let extensions: Set<String> = [
        "c",
        "cc",
        "conf",
        "cpp",
        "css",
        "csv",
        "go",
        "h",
        "hpp",
        "html",
        "java",
        "js",
        "json",
        "jsx",
        "kt",
        "log",
        "m",
        "md",
        "mm",
        "py",
        "rb",
        "rs",
        "sh",
        "sql",
        "swift",
        "toml",
        "ts",
        "tsx",
        "txt",
        "xml",
        "yaml",
        "yml"
    ]
}

public struct ToolCardState: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var status: ToolCardStatus
    public var executionContext: ExecutionContextSurface?
    public var inputJSON: String?
    public var outputJSON: String?
    public var artifacts: [ToolArtifactState]
    public var actions: [ToolCardActionSurface]
    public var isExpanded: Bool
    public var density: ToolCardDensity
    public var reviewState: ToolCardReviewState

    public init(
        id: String,
        title: String,
        subtitle: String,
        status: ToolCardStatus,
        executionContext: ExecutionContextSurface? = nil,
        inputJSON: String? = nil,
        outputJSON: String? = nil,
        artifacts: [ToolArtifactState] = [],
        actions: [ToolCardActionSurface] = [],
        isExpanded: Bool = false,
        density: ToolCardDensity? = nil,
        reviewState: ToolCardReviewState? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.executionContext = executionContext
        self.inputJSON = inputJSON
        self.outputJSON = outputJSON
        self.artifacts = artifacts
        self.actions = actions
        self.isExpanded = isExpanded
        self.density = density ?? Self.defaultDensity(status: status, isExpanded: isExpanded)
        self.reviewState = reviewState ?? Self.defaultReviewState(
            status: status,
            actions: actions,
            subtitle: subtitle
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case status
        case executionContext
        case inputJSON
        case outputJSON
        case artifacts
        case actions
        case isExpanded
        case density
        case reviewState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.status = try container.decode(ToolCardStatus.self, forKey: .status)
        self.executionContext = try container.decodeIfPresent(ExecutionContextSurface.self, forKey: .executionContext)
        self.inputJSON = try container.decodeIfPresent(String.self, forKey: .inputJSON)
        self.outputJSON = try container.decodeIfPresent(String.self, forKey: .outputJSON)
        self.artifacts = try container.decodeIfPresent([ToolArtifactState].self, forKey: .artifacts) ?? []
        self.actions = try container.decodeIfPresent([ToolCardActionSurface].self, forKey: .actions) ?? []
        self.isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
        self.density = try container.decodeIfPresent(ToolCardDensity.self, forKey: .density)
            ?? Self.defaultDensity(status: status, isExpanded: isExpanded)
        self.reviewState = try container.decodeIfPresent(ToolCardReviewState.self, forKey: .reviewState)
            ?? Self.defaultReviewState(status: status, actions: actions, subtitle: subtitle)
    }

    public static func defaultDensity(status: ToolCardStatus, isExpanded: Bool = false) -> ToolCardDensity {
        if isExpanded {
            return .expanded
        }
        switch status {
        case .queued, .running:
            return .peek
        case .done:
            return .collapsed
        case .failed, .review:
            return .expanded
        }
    }

    public var opensDetailsByDefault: Bool {
        density == .expanded
    }

    public static func defaultReviewState(
        status: ToolCardStatus,
        actions: [ToolCardActionSurface] = [],
        subtitle: String = ""
    ) -> ToolCardReviewState {
        guard status == .review else {
            return .none
        }
        // Compatibility fallback for older encoded surfaces and simple harness fixtures.
        if actions.isEmpty,
           subtitle.localizedCaseInsensitiveContains("Blocked") {
            return .needsReview
        }
        return .ready
    }

    public var statusDisplayLabel: String {
        switch status {
        case .queued:
            return "Queued"
        case .running:
            return "Running"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        case .review:
            return needsReview ? "Needs review" : "Ready"
        }
    }

    public var statusAccessibilityLabel: String {
        switch status {
        case .review:
            return needsReview ? "needs review" : "ready to run"
        default:
            return status.rawValue
        }
    }

    public var needsReview: Bool {
        status == .review && reviewState == .needsReview
    }

    public var densityAccessibilityLabel: String {
        switch density {
        case .collapsed:
            return "collapsed"
        case .peek:
            return "preview"
        case .expanded:
            return "expanded"
        }
    }

    public var imagePreviewArtifacts: [ToolArtifactState] {
        artifacts.filter(\.isImagePreview)
    }

    public var textPreviewArtifacts: [ToolArtifactState] {
        artifacts.filter(\.hasTextPreview)
    }

    public var documentPreviewArtifacts: [ToolArtifactState] {
        artifacts.filter(\.isDocumentPreview)
    }
}
