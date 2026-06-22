import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
import QuillComputerUseKit

public enum ToolCardStatus: String, Codable, Sendable, Hashable {
    case queued
    case running
    case done
    case failed
    case review
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

private enum ToolArtifactPreviewBuilder {
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
    public var isExpanded: Bool
    public var density: ToolCardDensity

    public init(
        id: String,
        title: String,
        subtitle: String,
        status: ToolCardStatus,
        executionContext: ExecutionContextSurface? = nil,
        inputJSON: String? = nil,
        outputJSON: String? = nil,
        artifacts: [ToolArtifactState] = [],
        isExpanded: Bool = false,
        density: ToolCardDensity? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.executionContext = executionContext
        self.inputJSON = inputJSON
        self.outputJSON = outputJSON
        self.artifacts = artifacts
        self.isExpanded = isExpanded
        self.density = density ?? Self.defaultDensity(status: status, isExpanded: isExpanded)
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
        case isExpanded
        case density
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
        self.isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
        self.density = try container.decodeIfPresent(ToolCardDensity.self, forKey: .density)
            ?? Self.defaultDensity(status: status, isExpanded: isExpanded)
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

public struct ComposerState: Sendable, Hashable {
    public var draft: String
    public var isSending: Bool
    public var placeholder: String

    public init(
        draft: String = "",
        isSending: Bool = false,
        placeholder: String = "Message QuillCode"
    ) {
        self.draft = draft
        self.isSending = isSending
        self.placeholder = placeholder
    }
}

public struct TerminalCommandState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var command: String
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32?
    public var ok: Bool
    public var status: TerminalCommandStatus
    public var executionContext: ExecutionContextSurface?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        command: String,
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        status: TerminalCommandStatus? = nil,
        executionContext: ExecutionContextSurface? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.command = command
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.ok = ok
        self.status = status ?? (ok ? .done : .failed)
        self.executionContext = executionContext
        self.createdAt = createdAt
    }
}

public enum TerminalCommandStatus: String, Sendable, Hashable {
    case running
    case done
    case failed
    case stopped
}

public struct WorkspaceWorktreeCreateRequest: Sendable, Hashable {
    public var path: String
    public var branch: String
    public var base: String

    public init(path: String, branch: String = "", base: String = "") {
        self.path = path
        self.branch = branch
        self.base = base
    }
}

public struct WorkspaceWorktreeRemoveRequest: Sendable, Hashable {
    public var path: String
    public var force: Bool

    public init(path: String, force: Bool = false) {
        self.path = path
        self.force = force
    }
}

public struct TerminalState: Sendable, Hashable {
    public var projectID: UUID?
    public var currentDirectoryPath: String?
    public var environmentOverrides: [String: String]
    public var removedEnvironmentKeys: Set<String>
    public var isVisible: Bool
    public var draft: String
    public var isRunning: Bool
    public var entries: [TerminalCommandState]

    public init(
        projectID: UUID? = nil,
        currentDirectoryPath: String? = nil,
        environmentOverrides: [String: String] = [:],
        removedEnvironmentKeys: Set<String> = [],
        isVisible: Bool = false,
        draft: String = "",
        isRunning: Bool = false,
        entries: [TerminalCommandState] = []
    ) {
        self.projectID = projectID
        self.currentDirectoryPath = currentDirectoryPath
        self.environmentOverrides = environmentOverrides
        self.removedEnvironmentKeys = removedEnvironmentKeys
        self.isVisible = isVisible
        self.draft = draft
        self.isRunning = isRunning
        self.entries = entries
    }
}

public struct BrowserCommentState: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var url: String
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), url: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.url = url
        self.text = text
        self.createdAt = createdAt
    }
}

public struct BrowserSnapshotState: Sendable, Hashable {
    public var sourceLabel: String
    public var inspectionDepth: BrowserInspectionDepth
    public var summary: String
    public var details: [String]
    public var outline: [String]
    public var textSnippet: String?

    public init(
        sourceLabel: String,
        inspectionDepth: BrowserInspectionDepth = .metadataOnly,
        summary: String,
        details: [String] = [],
        outline: [String] = [],
        textSnippet: String? = nil
    ) {
        self.sourceLabel = sourceLabel
        self.inspectionDepth = inspectionDepth
        self.summary = summary
        self.details = details
        self.outline = outline
        self.textSnippet = textSnippet
    }
}

public struct WorkspaceReviewCommentState: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var path: String
    public var lineNumber: Int?
    public var endLineNumber: Int?
    public var lineKind: WorkspaceReviewLineKind?
    public var text: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        path: String,
        lineNumber: Int? = nil,
        endLineNumber: Int? = nil,
        lineKind: WorkspaceReviewLineKind? = nil,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.lineNumber = lineNumber
        self.endLineNumber = endLineNumber
        self.lineKind = lineKind
        self.text = text
        self.createdAt = createdAt
    }
}

public struct BrowserState: Sendable, Hashable {
    public var isVisible: Bool
    public var addressDraft: String
    public var currentURL: String?
    public var history: [String]
    public var historyIndex: Int?
    public var title: String
    public var status: String
    public var snapshot: BrowserSnapshotState?
    public var comments: [BrowserCommentState]

    public var canGoBack: Bool {
        guard let historyIndex else { return false }
        return history.indices.contains(historyIndex) && historyIndex > history.startIndex
    }

    public var canGoForward: Bool {
        guard let historyIndex else { return false }
        return history.indices.contains(historyIndex) && history.index(after: historyIndex) < history.endIndex
    }

    public var canReload: Bool {
        currentURL != nil
    }

    public init(
        isVisible: Bool = false,
        addressDraft: String = "",
        currentURL: String? = nil,
        history: [String] = [],
        historyIndex: Int? = nil,
        title: String = "Browser preview",
        status: String = "Ready",
        snapshot: BrowserSnapshotState? = nil,
        comments: [BrowserCommentState] = []
    ) {
        self.isVisible = isVisible
        self.addressDraft = addressDraft
        self.currentURL = currentURL
        self.history = history
        self.historyIndex = historyIndex
        self.title = title
        self.status = status
        self.snapshot = snapshot
        self.comments = comments
    }
}

public struct ExtensionsState: Sendable, Hashable {
    public var isVisible: Bool
    public var mcpServerStatuses: [String: MCPServerLifecycleStatus]
    public var mcpServerProbeSummaries: [String: MCPServerProbeSummary]

    public init(
        isVisible: Bool = false,
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        mcpServerProbeSummaries: [String: MCPServerProbeSummary] = [:]
    ) {
        self.isVisible = isVisible
        self.mcpServerStatuses = mcpServerStatuses
        self.mcpServerProbeSummaries = mcpServerProbeSummaries
    }
}

public enum MCPServerLifecycleStatus: String, Sendable, Hashable {
    case stopped
    case probing
    case running
    case ready
    case failed

    public var title: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .probing:
            return "Probing"
        case .running:
            return "Running"
        case .ready:
            return "Ready"
        case .failed:
            return "Failed"
        }
    }

    public var isActive: Bool {
        switch self {
        case .probing, .running, .ready:
            return true
        case .stopped, .failed:
            return false
        }
    }
}

public struct MCPServerProbeSummary: Codable, Sendable, Hashable {
    public var protocolVersion: String?
    public var serverName: String?
    public var serverVersion: String?
    public var toolDescriptors: [MCPToolDescriptor]
    public var toolNames: [String]
    public var resourceNames: [String]
    public var resourceURIs: [String]
    public var promptNames: [String]
    public var errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case serverName
        case serverVersion
        case toolDescriptors
        case toolNames
        case resourceNames
        case resourceURIs
        case promptNames
        case errorMessage
    }

    public init(
        protocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        toolDescriptors: [MCPToolDescriptor] = [],
        toolNames: [String] = [],
        resourceNames: [String] = [],
        resourceURIs: [String] = [],
        promptNames: [String] = [],
        errorMessage: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.toolDescriptors = toolDescriptors.isEmpty
            ? toolNames.map { MCPToolDescriptor(name: $0) }
            : toolDescriptors
        self.toolNames = toolNames.isEmpty
            ? self.toolDescriptors.map(\.name)
            : toolNames
        self.resourceNames = resourceNames
        self.resourceURIs = resourceURIs
        self.promptNames = promptNames
        self.errorMessage = errorMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
        self.serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
        self.serverVersion = try container.decodeIfPresent(String.self, forKey: .serverVersion)
        self.toolDescriptors = try container.decodeIfPresent([MCPToolDescriptor].self, forKey: .toolDescriptors) ?? []
        self.toolNames = try container.decodeIfPresent([String].self, forKey: .toolNames) ?? []
        if self.toolDescriptors.isEmpty {
            self.toolDescriptors = self.toolNames.map { MCPToolDescriptor(name: $0) }
        }
        if self.toolNames.isEmpty {
            self.toolNames = self.toolDescriptors.map(\.name)
        }
        self.resourceNames = try container.decodeIfPresent([String].self, forKey: .resourceNames) ?? []
        self.resourceURIs = try container.decodeIfPresent([String].self, forKey: .resourceURIs) ?? []
        self.promptNames = try container.decodeIfPresent([String].self, forKey: .promptNames) ?? []
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }

    public init(result: MCPServerProbeResult) {
        self.init(
            protocolVersion: result.protocolVersion,
            serverName: result.serverName,
            serverVersion: result.serverVersion,
            toolDescriptors: result.toolDescriptors,
            resourceNames: result.resourceNames,
            resourceURIs: result.resourceURIs,
            promptNames: result.promptNames,
            errorMessage: nil
        )
    }

    public var serverLabel: String? {
        switch (serverName, serverVersion) {
        case let (.some(name), .some(version)) where !version.isEmpty:
            return "\(name) \(version)"
        case let (.some(name), _):
            return name
        default:
            return nil
        }
    }

    public var toolCountLabel: String? {
        guard errorMessage == nil else { return nil }
        return "\(toolNames.count) tool\(toolNames.count == 1 ? "" : "s")"
    }

    public var resourceCountLabel: String? {
        guard errorMessage == nil, !resourceNames.isEmpty else { return nil }
        return "\(resourceNames.count) resource\(resourceNames.count == 1 ? "" : "s")"
    }

    public var promptCountLabel: String? {
        guard errorMessage == nil, !promptNames.isEmpty else { return nil }
        return "\(promptNames.count) prompt\(promptNames.count == 1 ? "" : "s")"
    }
}

public struct MemoriesState: Sendable, Hashable {
    public var isVisible: Bool

    public init(isVisible: Bool = false) {
        self.isVisible = isVisible
    }
}

public struct ActivityState: Sendable, Hashable {
    public var isVisible: Bool
    public var collapsedSectionIDs: Set<ActivitySectionKind>

    public init(isVisible: Bool = false, collapsedSectionIDs: Set<ActivitySectionKind> = []) {
        self.isVisible = isVisible
        self.collapsedSectionIDs = collapsedSectionIDs
    }
}

public struct SidebarSelectionState: Sendable, Hashable {
    public var isActive: Bool
    public var selectedThreadIDs: Set<UUID>

    public init(isActive: Bool = false, selectedThreadIDs: Set<UUID> = []) {
        self.isActive = isActive
        self.selectedThreadIDs = selectedThreadIDs
    }
}

private final class MCPServerProcessHandle: @unchecked Sendable {
    let process: Process
    let standardInput: Pipe
    let standardOutput: Pipe
    let standardError: Pipe
    let session: MCPStdioProber

    init(
        process: Process,
        standardInput: Pipe,
        standardOutput: Pipe,
        standardError: Pipe,
        session: MCPStdioProber
    ) {
        self.process = process
        self.standardInput = standardInput
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.session = session
    }
}

private struct MCPToolCallRequest {
    var serverID: String
    var toolName: String
    var toolArgumentsJSON: String

    init(argumentsJSON: String) throws {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            throw MCPToolCallRequestError.invalidJSON
        }

        let serverID = (object["serverID"] as? String ?? object["serverId"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let toolName = (object["toolName"] as? String ?? object["name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverID.isEmpty else { throw MCPToolCallRequestError.missingServerID }
        guard !toolName.isEmpty else { throw MCPToolCallRequestError.missingToolName }

        if let argumentsJSON = object["argumentsJSON"] as? String,
           !argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.toolArgumentsJSON = argumentsJSON
        } else if let arguments = object["arguments"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) {
            self.toolArgumentsJSON = String(decoding: data, as: UTF8.self)
        } else {
            self.toolArgumentsJSON = "{}"
        }
        self.serverID = serverID
        self.toolName = toolName
    }
}

private enum MCPToolCallRequestError: Error, CustomStringConvertible {
    case invalidJSON
    case missingServerID
    case missingToolName

    var description: String {
        switch self {
        case .invalidJSON:
            return "MCP call arguments must be a JSON object."
        case .missingServerID:
            return "MCP call requires a non-empty serverID."
        case .missingToolName:
            return "MCP call requires a non-empty toolName."
        }
    }
}

private struct MCPResourceReadRequest {
    var serverID: String
    var resourceIdentifier: String

    init(argumentsJSON: String) throws {
        let object = try Self.object(from: argumentsJSON)
        self.serverID = Self.trimmedString(object["serverID"] ?? object["serverId"])
        self.resourceIdentifier = Self.trimmedString(
            object["resourceURI"] ?? object["uri"] ?? object["resourceName"] ?? object["name"]
        )
        guard !serverID.isEmpty else { throw MCPResourceReadRequestError.missingServerID }
        guard !resourceIdentifier.isEmpty else { throw MCPResourceReadRequestError.missingResource }
    }

    private static func object(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            throw MCPResourceReadRequestError.invalidJSON
        }
        return object
    }

    private static func trimmedString(_ value: Any?) -> String {
        (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum MCPResourceReadRequestError: Error, CustomStringConvertible {
    case invalidJSON
    case missingServerID
    case missingResource

    var description: String {
        switch self {
        case .invalidJSON:
            return "MCP resource read arguments must be a JSON object."
        case .missingServerID:
            return "MCP resource read requires a non-empty serverID."
        case .missingResource:
            return "MCP resource read requires a non-empty resourceURI or resourceName."
        }
    }
}

private struct MCPPromptGetRequest {
    var serverID: String
    var promptName: String
    var promptArgumentsJSON: String

    init(argumentsJSON: String) throws {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            throw MCPPromptGetRequestError.invalidJSON
        }

        self.serverID = (object["serverID"] as? String ?? object["serverId"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.promptName = (object["promptName"] as? String ?? object["name"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverID.isEmpty else { throw MCPPromptGetRequestError.missingServerID }
        guard !promptName.isEmpty else { throw MCPPromptGetRequestError.missingPromptName }

        if let argumentsJSON = object["argumentsJSON"] as? String,
           !argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.promptArgumentsJSON = argumentsJSON
        } else if let arguments = object["arguments"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]) {
            self.promptArgumentsJSON = String(decoding: data, as: UTF8.self)
        } else {
            self.promptArgumentsJSON = "{}"
        }
    }
}

private enum MCPPromptGetRequestError: Error, CustomStringConvertible {
    case invalidJSON
    case missingServerID
    case missingPromptName

    var description: String {
        switch self {
        case .invalidJSON:
            return "MCP prompt arguments must be a JSON object."
        case .missingServerID:
            return "MCP prompt get requires a non-empty serverID."
        case .missingPromptName:
            return "MCP prompt get requires a non-empty promptName."
        }
    }
}

@MainActor
public final class QuillCodeWorkspaceModel {
    public private(set) var root: QuillCodeRootState
    public private(set) var composer: ComposerState
    public private(set) var terminal: TerminalState
    public private(set) var browser: BrowserState
    public private(set) var extensions: ExtensionsState
    public private(set) var memories: MemoriesState
    public private(set) var activity: ActivityState
    public private(set) var automations: AutomationsState
    public private(set) var sidebarSelection: SidebarSelectionState
    public private(set) var lastError: String?

    private var runner: AgentRunner
    private let threadStore: JSONThreadStore?
    private let projectStore: JSONProjectStore?
    private let automationStore: JSONAutomationStore?
    private let globalMemoryDirectory: URL?
    private var computerUseBackend: (any ComputerUseBackend)?
    private let sshRemoteShellExecutor: SSHRemoteShellExecutor
    private var mcpServerProcesses: [String: MCPServerProcessHandle]

    public init(
        root: QuillCodeRootState = QuillCodeRootState(),
        composer: ComposerState = ComposerState(),
        terminal: TerminalState = TerminalState(),
        browser: BrowserState = BrowserState(),
        extensions: ExtensionsState = ExtensionsState(),
        memories: MemoriesState = MemoriesState(),
        activity: ActivityState = ActivityState(),
        automations: AutomationsState = AutomationsState(),
        sidebarSelection: SidebarSelectionState = SidebarSelectionState(),
        runner: AgentRunner = AgentRunner(),
        threadStore: JSONThreadStore? = nil,
        projectStore: JSONProjectStore? = nil,
        automationStore: JSONAutomationStore? = nil,
        globalMemoryDirectory: URL? = nil,
        computerUseBackend: (any ComputerUseBackend)? = nil,
        sshRemoteShellExecutor: SSHRemoteShellExecutor = SSHRemoteShellExecutor()
    ) {
        self.root = root
        self.composer = composer
        self.terminal = terminal
        self.browser = browser
        self.extensions = extensions
        self.memories = memories
        self.activity = activity
        self.automations = automations
        self.sidebarSelection = sidebarSelection
        self.runner = runner
        self.threadStore = threadStore
        self.projectStore = projectStore
        self.automationStore = automationStore
        self.globalMemoryDirectory = globalMemoryDirectory
        self.computerUseBackend = computerUseBackend
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
        self.mcpServerProcesses = [:]
        if let computerUseBackend {
            self.root.topBar.computerUseStatus = computerUseBackend.status
        }
        syncTerminalSessionToSelectedProject()
        refreshTopBar()
    }

    deinit {
        for handle in mcpServerProcesses.values where handle.process.isRunning {
            handle.process.terminate()
        }
    }

    public var selectedThread: ChatThread? {
        guard let selectedThreadID = root.selectedThreadID else { return nil }
        return root.threads.first { $0.id == selectedThreadID }
    }

    public var selectedProject: ProjectRef? {
        guard let selectedProjectID = root.selectedProjectID else { return nil }
        return root.projects.first { $0.id == selectedProjectID }
    }

    public var activeWorkspaceRoot: URL? {
        guard let selectedProject, !selectedProject.isRemote else { return nil }
        return URL(fileURLWithPath: selectedProject.path)
    }

    var terminalCurrentDirectoryURL: URL? {
        guard selectedProject?.isRemote != true else { return nil }
        guard terminal.projectID == knownProjectID(root.selectedProjectID) else {
            return activeWorkspaceRoot
        }
        if let path = terminal.currentDirectoryPath, !path.isEmpty {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return activeWorkspaceRoot
    }

    private func syncTerminalSessionToSelectedProject() {
        let selectedProjectID = knownProjectID(root.selectedProjectID)
        guard terminal.projectID != selectedProjectID else { return }
        terminal.projectID = selectedProjectID
        terminal.currentDirectoryPath = selectedProject?.displayPath
        terminal.environmentOverrides = [:]
        terminal.removedEnvironmentKeys = []
    }

    public var currentToolCards: [ToolCardState] {
        guard let selectedThread else { return [] }
        return enrichToolCards(Self.toolCards(for: selectedThread), for: selectedThread)
    }

    public var currentTimelineItems: [TranscriptTimelineItemSurface] {
        guard let selectedThread else { return [] }
        return enrichTimelineItems(Self.transcriptTimelineItems(for: selectedThread), for: selectedThread)
    }

    private func enrichToolCards(_ cards: [ToolCardState], for thread: ChatThread) -> [ToolCardState] {
        guard let context = executionContext(for: thread) else { return cards }
        return cards.map { card in
            guard card.executionContext == nil, Self.isProjectExecutionTool(card.title) else {
                return card
            }
            var copy = card
            copy.executionContext = context
            return copy
        }
    }

    private func enrichTimelineItems(
        _ items: [TranscriptTimelineItemSurface],
        for thread: ChatThread
    ) -> [TranscriptTimelineItemSurface] {
        guard let context = executionContext(for: thread) else { return items }
        return items.map { item in
            guard var card = item.toolCard,
                  card.executionContext == nil,
                  Self.isProjectExecutionTool(card.title)
            else {
                return item
            }
            card.executionContext = context
            return .toolCard(card)
        }
    }

    private func executionContext(for thread: ChatThread) -> ExecutionContextSurface? {
        let project = thread.projectID.flatMap(project)
            ?? selectedProject
        guard let project else { return nil }
        return .project(project)
    }

    private func project(id: UUID) -> ProjectRef? {
        root.projects.first { $0.id == id }
    }

    private static func isProjectExecutionTool(_ toolName: String) -> Bool {
        toolName == ToolDefinition.shellRun.name
            || toolName == ToolDefinition.fileRead.name
            || toolName == ToolDefinition.fileWrite.name
            || toolName == ToolDefinition.applyPatch.name
            || toolName == ToolDefinition.gitStatus.name
            || toolName == ToolDefinition.gitDiff.name
            || toolName == ToolDefinition.gitStage.name
            || toolName == ToolDefinition.gitRestore.name
            || toolName == ToolDefinition.gitStageHunk.name
            || toolName == ToolDefinition.gitRestoreHunk.name
            || toolName == ToolDefinition.gitCommit.name
            || toolName == ToolDefinition.gitPush.name
            || toolName == ToolDefinition.gitPullRequestCreate.name
            || toolName == ToolDefinition.gitPullRequestView.name
            || toolName == ToolDefinition.gitPullRequestChecks.name
            || toolName == ToolDefinition.gitPullRequestDiff.name
            || toolName == ToolDefinition.gitPullRequestCheckout.name
            || toolName == ToolDefinition.gitPullRequestReviewers.name
            || toolName == ToolDefinition.gitPullRequestLabels.name
            || toolName == ToolDefinition.gitPullRequestComment.name
            || toolName == ToolDefinition.gitPullRequestReview.name
            || toolName == ToolDefinition.gitPullRequestMerge.name
            || toolName == ToolDefinition.gitWorktreeList.name
            || toolName == ToolDefinition.gitWorktreeCreate.name
            || toolName == ToolDefinition.gitWorktreeRemove.name
    }

    public var canRetryLastUserTurn: Bool {
        guard composer.isSending == false else { return false }
        return selectedThread?.messages.contains {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } == true
    }

    public func setDraft(_ draft: String) {
        composer.draft = draft
    }

    @discardableResult
    public func setMessageFeedback(messageID: UUID, value: MessageFeedbackValue) -> Bool {
        guard selectedThread?.messages.contains(where: { $0.id == messageID && $0.role == .assistant }) == true else {
            return false
        }
        let feedback = MessageFeedback(messageID: messageID, value: value)
        guard let payloadJSON = try? JSONHelpers.encodePretty(feedback) else {
            return false
        }
        let summary: String
        switch value {
        case .helpful:
            summary = "Marked assistant response helpful"
        case .notHelpful:
            summary = "Marked assistant response not helpful"
        }
        mutateSelectedThread { thread in
            thread.events.append(ThreadEvent(
                kind: .messageFeedback,
                summary: summary,
                payloadJSON: payloadJSON
            ))
        }
        return true
    }

    @discardableResult
    public func prepareRetryLastUserTurn() -> Bool {
        guard let lastUserMessage = selectedThread?.messages.last(where: {
            $0.role == .user && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return false
        }
        composer.draft = lastUserMessage.content
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    public func setTerminalDraft(_ draft: String) {
        terminal.draft = draft
    }

    public func setTerminalVisible(_ isVisible: Bool) {
        terminal.isVisible = isVisible
    }

    public func toggleTerminal() {
        terminal.isVisible.toggle()
    }

    @discardableResult
    public func clearTerminalHistory() -> Bool {
        guard !terminal.isRunning else {
            return false
        }
        terminal.entries.removeAll()
        terminal.isVisible = true
        lastError = nil
        return true
    }

    public func setBrowserAddressDraft(_ draft: String) {
        browser.addressDraft = draft
    }

    public func toggleBrowser() {
        browser.isVisible.toggle()
    }

    public func toggleExtensions() {
        extensions.isVisible.toggle()
    }

    public func toggleMemories() {
        memories.isVisible.toggle()
    }

    public func toggleActivity() {
        activity.isVisible.toggle()
    }

    public func toggleAutomations() {
        automations.isVisible.toggle()
    }

    public func setAutomations(_ items: [QuillAutomation]) {
        automations.items = QuillAutomation.sortedForDisplay(items)
        saveAutomations()
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        scheduleDescription: String = "Manual follow-up",
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let thread = selectedThread else { return nil }
        let automation = WorkspaceAutomationFactory.threadFollowUp(
            for: thread,
            selectedProjectID: root.selectedProjectID,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        setAutomations(automations.items + [automation])
        automations.isVisible = true
        return automation
    }

    @discardableResult
    public func createThreadFollowUpAutomation(after seconds: TimeInterval, now: Date = Date()) -> QuillAutomation? {
        guard let schedule = WorkspaceAutomationFactory.relativeSchedule(seconds: seconds, now: now) else { return nil }
        return createThreadFollowUpAutomation(
            scheduleDescription: schedule.description,
            nextRunAt: schedule.nextRunAt,
            now: now
        )
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        guard let schedule = ThreadFollowUpScheduleParser.parse(
            scheduleText,
            now: now,
            calendar: calendar
        ) else {
            lastError = "Could not understand that follow-up schedule. Try `/follow-up in 30 minutes`, `/follow-up tomorrow at 9 AM`, or `/follow-up daily`."
            refreshTopBar(agentStatus: "Idle")
            return nil
        }
        return createThreadFollowUpAutomation(
            scheduleDescription: schedule.scheduleDescription,
            nextRunAt: schedule.nextRunAt,
            recurrence: schedule.recurrence,
            now: now
        )
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        every recurrence: QuillAutomationRecurrence,
        now: Date = Date()
    ) -> QuillAutomation? {
        createThreadFollowUpAutomation(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )
    }

    @discardableResult
    public func createTomorrowMorningThreadFollowUpAutomation(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        createThreadFollowUpAutomation(
            scheduleDescription: "Tomorrow at 9:00 AM",
            nextRunAt: WorkspaceAutomationFactory.tomorrowMorning(from: now, calendar: calendar),
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        scheduleDescription: String = "Manual workspace check",
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let project = selectedProject else { return nil }
        let automation = WorkspaceAutomationFactory.workspaceSchedule(
            for: project,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        setAutomations(automations.items + [automation])
        automations.isVisible = true
        return automation
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(after seconds: TimeInterval, now: Date = Date()) -> QuillAutomation? {
        guard let schedule = WorkspaceAutomationFactory.relativeSchedule(seconds: seconds, now: now) else { return nil }
        return createWorkspaceScheduleAutomation(
            scheduleDescription: schedule.description,
            nextRunAt: schedule.nextRunAt,
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        guard let schedule = ThreadFollowUpScheduleParser.parse(
            scheduleText,
            now: now,
            calendar: calendar
        ) else {
            lastError = "Could not understand that workspace-check schedule. Try `/workspace-check in 1 hour`, `/workspace-check tomorrow at 9 AM`, or `/workspace-check every 2 hours`."
            refreshTopBar(agentStatus: "Idle")
            return nil
        }
        return createWorkspaceScheduleAutomation(
            scheduleDescription: schedule.scheduleDescription,
            nextRunAt: schedule.nextRunAt,
            recurrence: schedule.recurrence,
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        every recurrence: QuillAutomationRecurrence,
        now: Date = Date()
    ) -> QuillAutomation? {
        createWorkspaceScheduleAutomation(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )
    }

    @discardableResult
    public func createTomorrowMorningWorkspaceScheduleAutomation(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        createWorkspaceScheduleAutomation(
            scheduleDescription: "Tomorrow at 9:00 AM",
            nextRunAt: WorkspaceAutomationFactory.tomorrowMorning(from: now, calendar: calendar),
            now: now
        )
    }

    public func updateAutomationStatus(id: UUID, status: QuillAutomationStatus) -> Bool {
        guard let index = automations.items.firstIndex(where: { $0.id == id }) else { return false }
        automations.items[index].status = status
        automations.items[index].updatedAt = Date()
        setAutomations(automations.items)
        return true
    }

    @discardableResult
    public func runAutomation(id: UUID) -> UUID? {
        runAutomationReport(id: id)?.followUpThreadID
    }

    @discardableResult
    public func runAutomationReport(id: UUID, now: Date = Date()) -> AutomationRunReport? {
        guard let automation = automations.items.first(where: { $0.id == id }) else { return nil }
        guard automation.status == .active else { return nil }

        switch automation.kind {
        case .threadFollowUp:
            return runThreadFollowUpAutomation(automation, now: now)
        case .workspaceSchedule:
            return runWorkspaceScheduleAutomation(automation, now: now)
        case .monitor:
            lastError = "Monitor automations can be configured, but monitor runners are not available yet."
            refreshTopBar(agentStatus: "Idle")
            return nil
        }
    }

    @discardableResult
    public func runDueAutomations(now: Date = Date(), limit: Int = 5) -> [UUID] {
        runDueAutomationReports(now: now, limit: limit).map(\.followUpThreadID)
    }

    @discardableResult
    public func runDueAutomationReports(now: Date = Date(), limit: Int = 5) -> [AutomationRunReport] {
        let dueAutomationIDs = WorkspaceAutomationRunner.dueAutomationIDs(
            in: automations.items,
            now: now,
            limit: limit
        )
        return dueAutomationIDs.compactMap { runAutomationReport(id: $0, now: now) }
    }

    public func deleteAutomation(id: UUID) -> Bool {
        let initialCount = automations.items.count
        automations.items.removeAll { $0.id == id }
        guard automations.items.count != initialCount else { return false }
        setAutomations(automations.items)
        return true
    }

    private func runThreadFollowUpAutomation(
        _ automation: QuillAutomation,
        now: Date
    ) -> AutomationRunReport? {
        guard let threadID = automation.threadID,
              let source = root.threads.first(where: { $0.id == threadID })
        else {
            lastError = "The original thread for \(automation.title) is no longer available."
            refreshTopBar(agentStatus: "Idle")
            return nil
        }

        let projectID = knownProjectID(automation.projectID ?? source.projectID)
        let copiedMessages = Self.forkSeedMessages(from: source.messages)
        let draft = WorkspaceAutomationRunner.threadFollowUpDraft(
            automation: automation,
            source: source,
            selectedProjectID: projectID,
            copiedMessages: copiedMessages,
            now: now
        )
        return applyAutomationRunDraft(draft)
    }

    private func runWorkspaceScheduleAutomation(
        _ automation: QuillAutomation,
        now: Date
    ) -> AutomationRunReport? {
        guard let projectID = automation.projectID,
              let project = project(id: projectID)
        else {
            lastError = "The project for \(automation.title) is no longer available."
            refreshTopBar(agentStatus: "Idle")
            return nil
        }

        if project.isRemote {
            _ = refreshRemoteProjectContext(projectID)
        } else {
            refreshProjectMetadata(projectID)
        }

        let draft = WorkspaceAutomationRunner.workspaceScheduleDraft(
            automation: automation,
            project: project,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: instructions(for: projectID),
            memories: memoryNotes(for: projectID),
            now: now
        )
        return applyAutomationRunDraft(draft)
    }

    private func applyAutomationRunDraft(_ draft: WorkspaceAutomationRunDraft) -> AutomationRunReport {
        replaceAutomation(draft.automation)
        clearSidebarSelection()
        root.threads.insert(draft.thread, at: 0)
        root.selectedThreadID = draft.thread.id
        root.selectedProjectID = draft.selectedProjectID
        syncTerminalSessionToSelectedProject()
        touchProject(draft.selectedProjectID)
        saveProjects()
        try? threadStore?.save(draft.thread)
        automations.isVisible = true
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        return draft.report
    }

    private func replaceAutomation(_ automation: QuillAutomation) {
        guard let index = automations.items.firstIndex(where: { $0.id == automation.id }) else { return }
        automations.items[index] = automation
        setAutomations(automations.items)
    }

    public func toggleActivitySection(_ section: ActivitySectionKind) {
        activity.isVisible = true
        if activity.collapsedSectionIDs.contains(section) {
            activity.collapsedSectionIDs.remove(section)
        } else {
            activity.collapsedSectionIDs.insert(section)
        }
    }

    @discardableResult
    public func openBrowserPreview(_ input: String? = nil, workspaceRoot: URL? = nil) -> Bool {
        let rawValue = input ?? browser.addressDraft
        guard let url = Self.normalizedBrowserURL(rawValue, workspaceRoot: workspaceRoot) else {
            browser.isVisible = true
            browser.status = "Invalid address"
            lastError = "Enter an http, https, file, localhost, or project file URL."
            refreshTopBar(agentStatus: "Idle")
            return false
        }

        setBrowserPage(url, updateHistory: true)
        return true
    }

    @discardableResult
    public func goBackInBrowser() -> Bool {
        guard browser.canGoBack,
              let historyIndex = browser.historyIndex
        else {
            return false
        }
        return openBrowserHistoryEntry(at: historyIndex - 1)
    }

    @discardableResult
    public func goForwardInBrowser() -> Bool {
        guard browser.canGoForward,
              let historyIndex = browser.historyIndex
        else {
            return false
        }
        return openBrowserHistoryEntry(at: historyIndex + 1)
    }

    @discardableResult
    public func reloadBrowserPreview() -> Bool {
        guard let currentURL = browser.currentURL,
              let url = URL(string: currentURL)
        else {
            return false
        }
        setBrowserPage(url, updateHistory: false)
        browser.status = "Reloaded"
        return true
    }

    private func openBrowserHistoryEntry(at index: Int) -> Bool {
        guard browser.history.indices.contains(index),
              let url = URL(string: browser.history[index])
        else {
            return false
        }
        browser.historyIndex = index
        setBrowserPage(url, updateHistory: false)
        return true
    }

    private func setBrowserPage(_ url: URL, updateHistory: Bool) {
        browser.isVisible = true
        browser.currentURL = url.absoluteString
        browser.addressDraft = url.absoluteString
        browser.snapshot = BrowserInspector.snapshot(for: url)
        browser.title = browser.snapshot?.details
            .first { $0.hasPrefix("Title: ") }
            .map { String($0.dropFirst("Title: ".count)) }
            ?? BrowserInspector.title(for: url)
        browser.status = "Preview ready"
        if updateHistory {
            appendBrowserHistory(url.absoluteString)
        }
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
    }

    private func appendBrowserHistory(_ url: String) {
        if let historyIndex = browser.historyIndex,
           browser.history.indices.contains(historyIndex),
           browser.history[historyIndex] == url {
            return
        }

        let preservedHistory: ArraySlice<String>
        if let historyIndex = browser.historyIndex,
           browser.history.indices.contains(historyIndex) {
            preservedHistory = browser.history.prefix(through: historyIndex)
        } else {
            preservedHistory = []
        }

        browser.history = Array(preservedHistory) + [url]
        browser.historyIndex = browser.history.indices.last
    }

    private func replaceCurrentBrowserHistory(with url: String) {
        guard let historyIndex = browser.historyIndex,
              browser.history.indices.contains(historyIndex)
        else {
            appendBrowserHistory(url)
            return
        }
        browser.history[historyIndex] = url
    }

    @discardableResult
    public func openBrowserPreview(
        _ input: String? = nil,
        workspaceRoot: URL? = nil,
        pageFetcher: any BrowserPageFetching
    ) async -> Bool {
        guard openBrowserPreview(input, workspaceRoot: workspaceRoot) else { return false }
        _ = await refreshBrowserSnapshot(pageFetcher: pageFetcher)
        return true
    }

    @discardableResult
    public func refreshBrowserSnapshot(pageFetcher: any BrowserPageFetching) async -> Bool {
        guard let currentURL = browser.currentURL,
              let url = URL(string: currentURL),
              Self.canFetchBrowserSnapshot(for: url)
        else {
            return false
        }

        browser.status = "Fetching snapshot"
        refreshTopBar(agentStatus: "Idle")

        do {
            let fetchedPage = try await pageFetcher.fetchHTML(from: url)
            guard browser.currentURL == currentURL else { return false }

            browser.currentURL = fetchedPage.finalURL.absoluteString
            browser.addressDraft = fetchedPage.finalURL.absoluteString
            replaceCurrentBrowserHistory(with: fetchedPage.finalURL.absoluteString)
            browser.snapshot = BrowserInspector.snapshot(for: fetchedPage, originalURL: url)
            browser.title = browser.snapshot?.details
                .first { $0.hasPrefix("Title: ") }
                .map { String($0.dropFirst("Title: ".count)) }
                ?? BrowserInspector.title(for: fetchedPage.finalURL)
            browser.status = "Preview ready"
            lastError = nil
            refreshTopBar(agentStatus: "Idle")
            return true
        } catch {
            guard browser.currentURL == currentURL else { return false }
            if var snapshot = browser.snapshot {
                snapshot.details.append("Snapshot fetch: \(Self.browserSnapshotFetchMessage(for: error))")
                browser.snapshot = snapshot
            }
            browser.status = "Preview ready"
            lastError = nil
            refreshTopBar(agentStatus: "Idle")
            return false
        }
    }

    @discardableResult
    public func addBrowserComment(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = browser.currentURL else {
            return false
        }
        browser.comments.append(BrowserCommentState(url: url, text: trimmed))
        browser.status = "Comment added"
        return true
    }

    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        clearSidebarSelection()
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectMetadata(effectiveProjectID)
        let thread = ChatThread(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            instructions: instructions(for: effectiveProjectID),
            memories: memoryNotes(for: effectiveProjectID)
        )
        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = effectiveProjectID
        syncTerminalSessionToSelectedProject()
        touchProject(effectiveProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return thread.id
    }

    @discardableResult
    public func forkFromLast() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        clearSidebarSelection()
        let copiedMessages = Self.forkSeedMessages(from: source.messages)
        let fork = ChatThread(
            title: "Fork: \(source.title)",
            projectID: knownProjectID(source.projectID),
            mode: source.mode,
            model: source.model,
            messages: copiedMessages,
            events: [
                .init(
                    kind: .notice,
                    summary: "Forked from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories
        )
        root.threads.insert(fork, at: 0)
        root.selectedThreadID = fork.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(fork)
        refreshTopBar(agentStatus: "Idle")
        return fork.id
    }

    @discardableResult
    public func compactContext() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        clearSidebarSelection()
        let copiedMessages = Self.compactSeedMessages(from: source)
        let compacted = ChatThread(
            title: "Compact: \(source.title)",
            projectID: knownProjectID(source.projectID),
            mode: source.mode,
            model: source.model,
            messages: copiedMessages,
            events: [
                .init(
                    kind: .notice,
                    summary: "Compacted context from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories
        )
        root.threads.insert(compacted, at: 0)
        root.selectedThreadID = compacted.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(compacted)
        refreshTopBar(agentStatus: "Idle")
        return compacted.id
    }

    public func selectThread(_ id: UUID) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(thread.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
    }

    public func startSidebarSelection(selecting id: UUID? = nil) {
        sidebarSelection.isActive = true
        if let id, root.threads.contains(where: { $0.id == id }) {
            sidebarSelection.selectedThreadIDs.insert(id)
        }
    }

    public func clearSidebarSelection() {
        sidebarSelection = SidebarSelectionState()
    }

    public func selectAllSidebarThreads() {
        let ids = root.allSidebarItems.map(\.id)
        guard !ids.isEmpty else {
            clearSidebarSelection()
            return
        }
        sidebarSelection = SidebarSelectionState(isActive: true, selectedThreadIDs: Set(ids))
    }

    public func toggleSidebarThreadSelection(_ id: UUID) {
        guard root.threads.contains(where: { $0.id == id }) else { return }
        sidebarSelection.isActive = true
        if sidebarSelection.selectedThreadIDs.contains(id) {
            sidebarSelection.selectedThreadIDs.remove(id)
        } else {
            sidebarSelection.selectedThreadIDs.insert(id)
        }
    }

    @discardableResult
    public func performSidebarBulkAction(_ kind: SidebarBulkActionKind) -> Bool {
        let ids = selectedSidebarThreadIDs()
        switch kind {
        case .select:
            startSidebarSelection()
            return true
        case .selectAll:
            selectAllSidebarThreads()
            return true
        case .clearSelection:
            clearSidebarSelection()
            return true
        case .pin:
            guard !ids.isEmpty else { return false }
            updateThreads(ids) { thread in
                guard !thread.isArchived else { return }
                thread.isPinned = true
            }
        case .unpin:
            guard !ids.isEmpty else { return false }
            updateThreads(ids) { thread in
                thread.isPinned = false
            }
        case .archive:
            guard !ids.isEmpty else { return false }
            let previousSelection = selectedThread
            updateThreads(ids) { thread in
                thread.isArchived = true
                thread.isPinned = false
            }
            if let selectedID = previousSelection?.id, ids.contains(selectedID) {
                selectBestThread(afterRemoving: ids, preferredProjectID: previousSelection?.projectID)
            }
        case .unarchive:
            guard !ids.isEmpty else { return false }
            updateThreads(ids) { thread in
                thread.isArchived = false
            }
            if let firstID = ids.first,
               let firstThread = root.threads.first(where: { $0.id == firstID }) {
                root.selectedThreadID = firstID
                root.selectedProjectID = knownProjectID(firstThread.projectID)
                syncTerminalSessionToSelectedProject()
                touchProject(root.selectedProjectID)
            }
        case .delete:
            guard !ids.isEmpty else { return false }
            let previousSelection = selectedThread
            root.threads.removeAll { thread in
                if ids.contains(thread.id) {
                    try? threadStore?.delete(thread.id)
                    return true
                }
                return false
            }
            if let selectedID = previousSelection?.id, ids.contains(selectedID) {
                selectBestThread(afterRemoving: ids, preferredProjectID: previousSelection?.projectID)
            } else if let selectedThread {
                root.selectedProjectID = knownProjectID(selectedThread.projectID)
            } else {
                root.selectedProjectID = knownProjectID(root.selectedProjectID)
            }
            saveProjects()
        }

        clearSidebarSelection()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func addProject(path: URL, name: String? = nil) -> UUID {
        let standardized = path.standardizedFileURL
        let projectName = name ?? Self.defaultProjectName(for: standardized)
        if let index = root.projects.firstIndex(where: { $0.path == standardized.path }) {
            root.projects[index].name = projectName
            root.projects[index].instructions = ProjectInstructionLoader.load(from: standardized)
            root.projects[index].localActions = LocalEnvironmentActionLoader.load(from: standardized)
            root.projects[index].extensionManifests = ProjectExtensionManifestLoader.load(from: standardized)
            root.projects[index].memories = MemoryNoteLoader.loadProject(from: standardized)
            root.projects[index].lastOpenedAt = Date()
            root.selectedProjectID = root.projects[index].id
            syncTerminalSessionToSelectedProject()
            saveProjects()
            refreshTopBar(agentStatus: "Idle")
            return root.projects[index].id
        }

        let project = ProjectRef(
            name: projectName,
            path: standardized.path,
            lastOpenedAt: Date(),
            instructions: ProjectInstructionLoader.load(from: standardized),
            localActions: LocalEnvironmentActionLoader.load(from: standardized),
            extensionManifests: ProjectExtensionManifestLoader.load(from: standardized),
            memories: MemoryNoteLoader.loadProject(from: standardized)
        )
        root.projects.insert(project, at: 0)
        root.selectedProjectID = project.id
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return project.id
    }

    @discardableResult
    public func addSSHProject(_ address: String, name: String? = nil) -> UUID? {
        guard let connection = ProjectConnection.parseSSH(address) else {
            lastError = "Use SSH format user@host:/path or ssh://user@host/path."
            return nil
        }
        let projectName = name ?? Self.defaultSSHProjectName(for: connection)
        if let index = root.projects.firstIndex(where: { $0.connection == connection }) {
            root.projects[index].name = projectName
            root.projects[index].lastOpenedAt = Date()
            root.selectedProjectID = root.projects[index].id
            syncTerminalSessionToSelectedProject()
            saveProjects()
            refreshTopBar(agentStatus: "Idle")
            return root.projects[index].id
        }

        let project = ProjectRef(
            name: projectName,
            path: connection.path,
            connection: connection,
            lastOpenedAt: Date(),
            instructions: [],
            localActions: [],
            extensionManifests: [],
            memories: []
        )
        root.projects.insert(project, at: 0)
        root.selectedProjectID = project.id
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return project.id
    }

    public func selectProject(_ id: UUID?) {
        if let id {
            guard root.projects.contains(where: { $0.id == id }) else { return }
        }
        root.selectedProjectID = id
        syncTerminalSessionToSelectedProject()
        refreshProjectMetadata(id)
        touchProject(id)
        root.selectedThreadID = root.threads
            .filter { !$0.isArchived && $0.projectID == id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .id
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
    }

    @discardableResult
    public func renameProject(_ id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = root.projects.firstIndex(where: { $0.id == id })
        else {
            return false
        }
        root.projects[index].name = trimmed
        root.projects[index].lastOpenedAt = Date()
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func refreshProjectContext(_ id: UUID) -> Bool {
        guard let project = root.projects.first(where: { $0.id == id }) else {
            return false
        }
        if project.isRemote {
            guard refreshRemoteProjectContext(id) else {
                return false
            }
        } else {
            refreshProjectMetadata(id)
        }
        if selectedThread?.projectID == id || root.selectedProjectID == id {
            let refreshedInstructions = instructions(for: id)
            let refreshedMemories = memoryNotes(for: id)
            mutateSelectedThread { thread in
                guard thread.projectID == id else { return }
                thread.instructions = refreshedInstructions
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Refreshed project context",
                    payloadJSON: id.uuidString
                ))
            }
        }
        touchProject(id)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func removeProject(_ id: UUID) -> Bool {
        guard let index = root.projects.firstIndex(where: { $0.id == id }) else {
            return false
        }
        root.projects.remove(at: index)
        for threadIndex in root.threads.indices where root.threads[threadIndex].projectID == id {
            root.threads[threadIndex].projectID = nil
            try? threadStore?.save(root.threads[threadIndex])
        }
        if root.selectedProjectID == id {
            root.selectedProjectID = nil
        } else {
            root.selectedProjectID = knownProjectID(root.selectedProjectID)
        }
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    public func togglePinSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        togglePinThread(selectedThreadID)
    }

    public func archiveSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        archiveThread(selectedThreadID)
    }

    @discardableResult
    public func renameThread(_ id: UUID, to title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard mutateThread(id, { thread in
            thread.title = trimmed
        }) != nil else {
            return false
        }
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func duplicateThread(_ id: UUID) -> UUID? {
        guard let source = root.threads.first(where: { $0.id == id }) else { return nil }
        clearSidebarSelection()
        var duplicate = ChatThread(
            title: "Copy: \(source.title)",
            projectID: knownProjectID(source.projectID),
            mode: source.mode,
            model: source.model,
            messages: source.messages,
            events: source.events,
            isPinned: false,
            isArchived: false,
            instructions: source.instructions,
            memories: source.memories
        )
        duplicate.events.append(.init(
            kind: .notice,
            summary: "Duplicated from \(source.title)",
            payloadJSON: source.id.uuidString
        ))
        root.threads.insert(duplicate, at: 0)
        root.selectedThreadID = duplicate.id
        root.selectedProjectID = knownProjectID(source.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        try? threadStore?.save(duplicate)
        refreshTopBar(agentStatus: "Idle")
        return duplicate.id
    }

    public func togglePinThread(_ id: UUID) {
        mutateThread(id) { thread in
            thread.isPinned.toggle()
        }
    }

    public func archiveThread(_ id: UUID) {
        let archivedProjectID = root.threads.first { $0.id == id }?.projectID
        mutateThread(id) { thread in
            thread.isArchived = true
        }
        if root.selectedThreadID == id {
            root.selectedThreadID = root.threads
                .filter { !$0.isArchived && $0.projectID == archivedProjectID }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first?
                .id
        }
        refreshTopBar(agentStatus: "Idle")
    }

    @discardableResult
    public func unarchiveThread(_ id: UUID) -> Bool {
        guard let source = root.threads.first(where: { $0.id == id }),
              mutateThread(id, { thread in
                  thread.isArchived = false
              }) != nil
        else {
            return false
        }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(source.projectID)
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    @discardableResult
    public func deleteThread(_ id: UUID) -> Bool {
        guard let index = root.threads.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let removed = root.threads.remove(at: index)
        try? threadStore?.delete(id)
        if root.selectedThreadID == id {
            root.selectedThreadID = root.threads
                .filter { !$0.isArchived && $0.projectID == removed.projectID }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first?
                .id
        }
        if let selectedThread {
            root.selectedProjectID = knownProjectID(selectedThread.projectID)
        } else {
            root.selectedProjectID = knownProjectID(root.selectedProjectID)
        }
        saveProjects()
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    public func setMode(_ mode: AgentMode) {
        root.config.mode = mode
        mutateSelectedThread { thread in
            thread.mode = mode
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func setModel(_ model: String) {
        let modelID = TrustedRouterDefaults.normalizedDefaultModelID(model)
        root.config.defaultModel = modelID
        mutateSelectedThread { thread in
            thread.model = modelID
        }
        refreshTopBar(agentStatus: "Idle")
    }

    public func toggleModelFavorite(_ model: String) {
        let modelID = TrustedRouterDefaults.canonicalModelID(model)
        guard !modelID.isEmpty else { return }
        if let index = root.config.favoriteModels.firstIndex(of: modelID) {
            root.config.favoriteModels.remove(at: index)
        } else {
            root.config.favoriteModels.append(modelID)
        }
        root.config.favoriteModels = AppConfig(favoriteModels: root.config.favoriteModels).favoriteModels
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setModelCatalog(_ models: [ModelInfo]) {
        guard !models.isEmpty else { return }
        root.modelCatalog = TrustedRouterDefaults.normalizedModelCatalog(models)
    }

    public func applySettings(config: AppConfig, trustedRouterAPIKeyConfigured: Bool) {
        root.config = config
        root.trustedRouterAPIKeyConfigured = trustedRouterAPIKeyConfigured
        mutateSelectedThread { thread in
            thread.mode = config.mode
            thread.model = config.defaultModel
        }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func applyRuntime(_ runtime: QuillCodeRuntime) {
        runner = runtime.runner
        refreshTopBar(agentStatus: runtime.statusLabel)
    }

    public func setAgentStatus(_ status: String, lastError: String? = nil) {
        self.lastError = lastError
        refreshTopBar(agentStatus: status)
    }

    public func submitComposer(workspaceRoot: URL) async {
        let prompt = composer.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        if let command = SlashCommandParser.parse(prompt) {
            composer.draft = ""
            lastError = nil
            handleSlashCommand(command, originalPrompt: prompt, workspaceRoot: workspaceRoot)
            return
        }

        if selectedThread == nil {
            _ = newChat()
        }
        guard var thread = selectedThread else { return }
        syncThreadContext(into: &thread)
        let threadID = thread.id

        composer.draft = ""
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        do {
            try Task.checkCancellation()
            let activeMCPToolDefinitions = mcpToolDefinitionsForReadyServers()
            let activeMCPExecutor = mcpToolExecutionOverride()
            let activePlanDefinitions = [ToolDefinition.planUpdate]
            let activePlanExecutor = planToolExecutionOverride()
            let activeBrowserDefinitions = [ToolDefinition.browserInspect]
            let activeBrowserExecutor = browserToolExecutionOverride(snapshot: browser)
            let activeComputerDefinitions = computerUseBackend == nil ? [] : ToolDefinition.computerUseDefinitions
            let activeComputerExecutor = computerUseToolExecutionOverride()
            let activeMemoryDefinitions = globalMemoryDirectory == nil ? [] : [ToolDefinition.memoryRemember]
            let activeMemoryExecutor = memoryToolExecutionOverride()
            let activeRemoteProjectExecutor = remoteProjectToolExecutionOverride(project: selectedProject)
            var activeRunner = runner
            activeRunner.baseToolDefinitions = baseToolDefinitionsForSelectedProject()
            activeRunner.additionalToolDefinitions = activePlanDefinitions
                + activeBrowserDefinitions
                + activeComputerDefinitions
                + activeMemoryDefinitions
                + activeMCPToolDefinitions
            activeRunner.toolExecutionOverride = combinedToolExecutionOverride(
                plan: activePlanExecutor,
                browser: activeBrowserExecutor,
                computerUse: activeComputerExecutor,
                memory: activeMemoryExecutor,
                mcp: activeMCPExecutor,
                remoteProject: activeRemoteProjectExecutor
            )

            let result = try await activeRunner.send(
                prompt,
                in: thread,
                workspaceRoot: workspaceRoot,
                onProgress: { [weak self] progressThread in
                    await self?.applyAgentProgress(progressThread, expectedThreadID: threadID)
                }
            )
            try Task.checkCancellation()
            thread = result.thread
            if Self.didSaveMemory(in: thread) {
                refreshThreadMemoryContext(&thread)
            }
            replaceThread(thread)
            try threadStore?.save(thread)
            composer.isSending = false
            refreshTopBar(agentStatus: "Idle")
        } catch is CancellationError {
            finishCancelledSend(userPrompt: prompt, threadID: threadID)
        } catch {
            composer.isSending = false
            lastError = String(describing: error)
            refreshTopBar(agentStatus: "Failed")
        }
    }

    private func applyAgentProgress(_ thread: ChatThread, expectedThreadID: UUID) {
        guard thread.id == expectedThreadID else { return }
        replaceThread(thread)
        composer.isSending = true
        lastError = nil
        refreshTopBar(agentStatus: agentStatus(for: thread))
    }

    private func agentStatus(for thread: ChatThread) -> String {
        switch thread.events.last?.kind {
        case .toolQueued:
            return "Queued"
        case .toolRunning:
            return "Running"
        case .approvalRequested:
            return "Review"
        case .notice where thread.events.last?.summary == AgentRunner.streamingNotice:
            return "Streaming"
        case .toolCompleted:
            return "Finishing"
        case .toolFailed:
            return "Failed"
        case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice, .none:
            return "Running"
        }
    }

    public func runReviewAction(_ action: WorkspaceReviewActionSurface, workspaceRoot: URL) {
        guard selectedThread != nil else { return }
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let actionCall = action.toolCall
        let actionResult = executeReviewGitToolCall(actionCall, router: router)
        appendToolRun(call: actionCall, result: actionResult)

        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let diffResult = executeReviewGitToolCall(diffCall, router: router)
        appendToolRun(call: diffCall, result: diffResult)

        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        refreshTopBar(agentStatus: actionResult.ok && diffResult.ok ? "Idle" : "Failed")
    }

    private func executeReviewGitToolCall(_ call: ToolCall, router: ToolRouter) -> ToolResult {
        guard let project = selectedProject, project.isRemote else {
            return router.execute(call)
        }
        return Self.executeRemoteGitToolCall(
            call,
            connection: project.connection,
            executor: sshRemoteShellExecutor
        )
    }

    @discardableResult
    public func addReviewComment(path: String, text: String) -> Bool {
        addReviewComment(path: path, lineNumber: nil, endLineNumber: nil, lineKind: nil, text: text)
    }

    @discardableResult
    public func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int? = nil,
        lineKind: WorkspaceReviewLineKind?,
        text: String
    ) -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedThread != nil,
              !trimmedPath.isEmpty,
              !trimmedText.isEmpty
        else {
            return false
        }

        let currentReview = surface().review
        guard let file = currentReview.files.first(where: { $0.path == trimmedPath }) else {
            return false
        }

        let normalizedRange = Self.normalizedReviewRange(
            lineNumber: lineNumber,
            endLineNumber: endLineNumber
        )
        if let normalizedRange {
            guard Self.reviewRangeExists(normalizedRange, lineKind: lineKind, in: file) else {
                return false
            }
        }

        let comment = WorkspaceReviewCommentState(
            path: trimmedPath,
            lineNumber: normalizedRange?.lowerBound,
            endLineNumber: normalizedRange?.upperBound,
            lineKind: lineKind,
            text: trimmedText
        )
        let payloadJSON = (try? JSONHelpers.encodePretty(comment)) ?? "{}"
        let summary = normalizedRange.map { range in
            range.lowerBound == range.upperBound
                ? "Commented on \(trimmedPath):\(range.lowerBound)"
                : "Commented on \(trimmedPath):\(range.lowerBound)-\(range.upperBound)"
        } ?? "Commented on \(trimmedPath)"
        mutateSelectedThread { thread in
            thread.events.append(.init(
                kind: .reviewComment,
                summary: summary,
                payloadJSON: payloadJSON
            ))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        refreshTopBar(agentStatus: "Idle")
        return true
    }

    private static func normalizedReviewRange(
        lineNumber: Int?,
        endLineNumber: Int?
    ) -> ClosedRange<Int>? {
        guard let lineNumber else { return nil }
        let endLineNumber = endLineNumber ?? lineNumber
        guard lineNumber > 0, endLineNumber > 0 else { return nil }
        return min(lineNumber, endLineNumber)...max(lineNumber, endLineNumber)
    }

    private static func reviewRangeExists(
        _ range: ClosedRange<Int>,
        lineKind: WorkspaceReviewLineKind?,
        in file: WorkspaceReviewFileSurface
    ) -> Bool {
        let lines = file.hunkItems.flatMap(\.lines)
        guard lines.contains(where: {
            $0.displayLineNumber == range.lowerBound
                && (lineKind == nil || $0.kind == lineKind)
        }) else {
            return false
        }
        return range.allSatisfy { number in
            lines.contains { $0.displayLineNumber == number }
        }
    }

    @discardableResult
    public func runWorkspaceCommand(_ commandID: String, workspaceRoot: URL) -> Bool {
        guard let plan = WorkspaceCommandPlan(commandID: commandID) else { return false }
        switch plan {
        case .localEnvironmentAction(let actionID):
            return runLocalEnvironmentAction(actionID, workspaceRoot: workspaceRoot)
        case .deleteMemory(let id):
            return deleteGlobalMemory(id: id)
        case .updateAutomationStatus(let id, let status):
            return updateAutomationStatus(id: id, status: status)
        case .runAutomation(let id):
            return runAutomation(id: id) != nil
        case .deleteAutomation(let id):
            return deleteAutomation(id: id)
        case .createThreadFollowUpAfter(let seconds):
            return createThreadFollowUpAutomation(after: seconds) != nil
        case .createWorkspaceScheduleAfter(let seconds):
            return createWorkspaceScheduleAutomation(after: seconds) != nil
        case .createThreadFollowUpEvery(let recurrence):
            return createThreadFollowUpAutomation(every: recurrence) != nil
        case .createWorkspaceScheduleEvery(let recurrence):
            return createWorkspaceScheduleAutomation(every: recurrence) != nil
        case .startMCPServer(let id):
            return startMCPServer(id: id, workspaceRoot: workspaceRoot)
        case .stopMCPServer(let id):
            return stopMCPServer(id: id)
        case .updateExtension(let id):
            return runProjectExtensionUpdate(id: id, workspaceRoot: workspaceRoot)
        case .toggleThreadSelection(let id):
            toggleSidebarThreadSelection(id)
            return true
        case .toggleActivitySection(let section):
            toggleActivitySection(section)
            return true
        case .setDraft(let draft):
            setDraft(draft)
            return true
        case .runTool(let toolName):
            runToolCall(
                ToolCall(name: toolName, argumentsJSON: "{}"),
                workspaceRoot: workspaceRoot
            )
            return true
        case .action(let action):
            return runWorkspaceCommandAction(action)
        }
    }

    @discardableResult
    private func runWorkspaceCommandAction(_ action: WorkspaceCommandAction) -> Bool {
        switch action {
        case .toggleTerminal:
            toggleTerminal()
            return true
        case .clearTerminal:
            return clearTerminalHistory()
        case .toggleBrowser:
            toggleBrowser()
            return true
        case .browserBack:
            return goBackInBrowser()
        case .browserForward:
            return goForwardInBrowser()
        case .browserReload:
            return reloadBrowserPreview()
        case .toggleExtensions:
            toggleExtensions()
            return true
        case .toggleMemories:
            toggleMemories()
            return true
        case .toggleActivity:
            toggleActivity()
            return true
        case .toggleAutomations:
            toggleAutomations()
            return true
        case .createThreadFollowUp:
            return createThreadFollowUpAutomation() != nil
        case .createWorkspaceSchedule:
            return createWorkspaceScheduleAutomation() != nil
        case .createThreadFollowUpTomorrow:
            return createTomorrowMorningThreadFollowUpAutomation() != nil
        case .createWorkspaceScheduleTomorrow:
            return createTomorrowMorningWorkspaceScheduleAutomation() != nil
        case .projectNewChat:
            guard let projectID = root.selectedProjectID else { return false }
            _ = newChat(projectID: projectID)
            return true
        case .projectRefreshContext:
            guard let projectID = root.selectedProjectID else { return false }
            return refreshProjectContext(projectID)
        case .projectRename:
            guard let name = selectedProject?.name else { return false }
            setDraft("/project rename \(name)")
            return true
        case .projectRemove:
            guard let projectID = root.selectedProjectID else { return false }
            return removeProject(projectID)
        case .threadRename:
            guard let title = selectedThread?.title else { return false }
            setDraft("/rename \(title)")
            return true
        case .threadDuplicate:
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return duplicateThread(selectedThreadID) != nil
        case .threadArchive:
            guard let selectedThreadID = root.selectedThreadID else { return false }
            archiveThread(selectedThreadID)
            return true
        case .threadUnarchive:
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return unarchiveThread(selectedThreadID)
        case .threadDelete:
            guard let selectedThreadID = root.selectedThreadID else { return false }
            return deleteThread(selectedThreadID)
        case .threadSelectionStart:
            return performSidebarBulkAction(.select)
        case .threadSelectionSelectAll:
            return performSidebarBulkAction(.selectAll)
        case .threadSelectionClear:
            return performSidebarBulkAction(.clearSelection)
        case .threadBulkPin:
            return performSidebarBulkAction(.pin)
        case .threadBulkUnpin:
            return performSidebarBulkAction(.unpin)
        case .threadBulkArchive:
            return performSidebarBulkAction(.archive)
        case .threadBulkUnarchive:
            return performSidebarBulkAction(.unarchive)
        case .threadBulkDelete:
            return performSidebarBulkAction(.delete)
        case .retryLastTurn:
            return prepareRetryLastUserTurn()
        case .forkFromLast:
            return forkFromLast() != nil
        case .compactContext:
            return compactContext() != nil
        }
    }

    @discardableResult
    private func startMCPServer(id: String, workspaceRoot: URL) -> Bool {
        guard let manifest = selectedProject?.extensionManifests.first(where: {
            $0.id == id && $0.kind == .mcpServer
        }) else {
            lastError = "MCP server manifest not found."
            return false
        }
        guard manifest.isEnabled else {
            lastError = "\(manifest.name) is disabled."
            extensions.mcpServerStatuses[id] = .failed
            return false
        }
        guard let command = manifest.launchExecutable,
              !command.isEmpty
        else {
            lastError = "\(manifest.name) does not define a launch command."
            extensions.mcpServerStatuses[id] = .failed
            return false
        }
        if let handle = mcpServerProcesses[id], handle.process.isRunning {
            if extensions.mcpServerStatuses[id]?.isActive != true {
                extensions.mcpServerStatuses[id] = .running
            }
            refreshTopBar(agentStatus: "Idle")
            return true
        }

        let process = Process()
        process.currentDirectoryURL = workspaceRoot
        let arguments = manifest.launchArguments ?? []
        if command.contains("/") {
            let commandURL = command.hasPrefix("/")
                ? URL(fileURLWithPath: command)
                : workspaceRoot.appendingPathComponent(command)
            process.executableURL = commandURL
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
        }

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.terminationHandler = { [weak self] process in
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                self?.finishMCPServerProcess(id: id, terminationStatus: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            lastError = "Could not start \(manifest.name): \(error.localizedDescription)"
            extensions.mcpServerStatuses[id] = .failed
            refreshTopBar(agentStatus: "Failed")
            appendNotice("MCP server \(manifest.name) failed to start")
            return false
        }

        let session = MCPStdioProber(
            standardInput: standardInput.fileHandleForWriting,
            standardOutput: standardOutput.fileHandleForReading
        )
        let handle = MCPServerProcessHandle(
            process: process,
            standardInput: standardInput,
            standardOutput: standardOutput,
            standardError: standardError,
            session: session
        )
        mcpServerProcesses[id] = handle
        extensions.mcpServerStatuses[id] = .probing
        extensions.mcpServerProbeSummaries[id] = nil
        lastError = nil
        refreshTopBar(agentStatus: "Idle")

        do {
            let result = try session.probe(timeout: 2.0)
            extensions.mcpServerStatuses[id] = .ready
            extensions.mcpServerProbeSummaries[id] = MCPServerProbeSummary(result: result)
            standardError.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
            appendNotice("MCP server \(manifest.name) ready\(mcpProbeNoticeSuffix(for: result))")
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
            }
            mcpServerProcesses[id] = nil
            let message = error.localizedDescription
            lastError = "Could not verify \(manifest.name): \(message)"
            extensions.mcpServerStatuses[id] = .failed
            extensions.mcpServerProbeSummaries[id] = MCPServerProbeSummary(errorMessage: message)
            refreshTopBar(agentStatus: "Failed")
            appendNotice("MCP server \(manifest.name) probe failed: \(message)")
            return false
        }
        return true
    }

    @discardableResult
    private func stopMCPServer(id: String) -> Bool {
        guard let manifest = selectedProject?.extensionManifests.first(where: {
            $0.id == id && $0.kind == .mcpServer
        }) else {
            lastError = "MCP server manifest not found."
            return false
        }

        if let handle = mcpServerProcesses[id], handle.process.isRunning {
            handle.standardOutput.fileHandleForReading.readabilityHandler = nil
            handle.standardError.fileHandleForReading.readabilityHandler = nil
            handle.process.terminate()
        }
        mcpServerProcesses[id] = nil
        extensions.mcpServerStatuses[id] = .stopped
        extensions.mcpServerProbeSummaries[id] = nil
        lastError = nil
        refreshTopBar(agentStatus: "Idle")
        appendNotice("MCP server \(manifest.name) stopped")
        return true
    }

    private func finishMCPServerProcess(id: String, terminationStatus: Int32) {
        mcpServerProcesses[id] = nil
        if extensions.mcpServerStatuses[id] == .stopped {
            return
        }
        extensions.mcpServerStatuses[id] = terminationStatus == 0 ? .stopped : .failed
        if terminationStatus != 0 {
            extensions.mcpServerProbeSummaries[id] = MCPServerProbeSummary(
                errorMessage: "Process exited with status \(terminationStatus)."
            )
        } else {
            extensions.mcpServerProbeSummaries[id] = nil
        }
        refreshTopBar(agentStatus: terminationStatus == 0 ? "Idle" : "Failed")
    }

    private func mcpProbeNoticeSuffix(for result: MCPServerProbeResult) -> String {
        let toolPreview = result.toolNames.prefix(3).joined(separator: ", ")
        let toolLabel: String
        if result.toolNames.isEmpty {
            toolLabel = "0 tools"
        } else {
            let remaining = result.toolNames.count - min(result.toolNames.count, 3)
            toolLabel = remaining > 0
                ? "\(result.toolNames.count) tools: \(toolPreview), +\(remaining) more"
                : "\(result.toolNames.count) tools: \(toolPreview)"
        }
        let resourceLabel = result.resourceNames.isEmpty
            ? nil
            : "\(result.resourceNames.count) resource\(result.resourceNames.count == 1 ? "" : "s")"
        let promptLabel = result.promptNames.isEmpty
            ? nil
            : "\(result.promptNames.count) prompt\(result.promptNames.count == 1 ? "" : "s")"
        let parts = [toolLabel, resourceLabel, promptLabel].compactMap { $0 }
        return " (\(parts.joined(separator: "; ")))"
    }

    private func mcpToolDefinitionsForReadyServers() -> [ToolDefinition] {
        var definitions: [ToolDefinition] = []

        let readyTools = readyMCPToolDescriptions()
        if !readyTools.isEmpty {
            var definition = ToolDefinition.mcpCall
            definition.description = """
            Call a tool on a verified project-local MCP stdio server. Use only these Ready MCP tools:
            \(readyTools.joined(separator: "\n"))
            """
            definitions.append(definition)
        }

        let readyResources = readyMCPResourceDescriptions()
        if !readyResources.isEmpty {
            var definition = ToolDefinition.mcpReadResource
            definition.description = """
            Read a resource from a verified project-local MCP stdio server. Use only these Ready MCP resources:
            \(readyResources.joined(separator: "\n"))
            """
            definitions.append(definition)
        }

        let readyPrompts = readyMCPPromptDescriptions()
        if !readyPrompts.isEmpty {
            var definition = ToolDefinition.mcpGetPrompt
            definition.description = """
            Get a prompt from a verified project-local MCP stdio server. Use only these Ready MCP prompts:
            \(readyPrompts.joined(separator: "\n"))
            """
            definitions.append(definition)
        }

        return definitions
    }

    private func readyMCPToolDescriptions() -> [String] {
        (selectedProject?.extensionManifests ?? [])
            .filter { manifest in
                manifest.kind == .mcpServer
                    && extensions.mcpServerStatuses[manifest.id] == .ready
                    && mcpServerProcesses[manifest.id]?.process.isRunning == true
            }
            .compactMap { manifest -> String? in
                guard let summary = extensions.mcpServerProbeSummaries[manifest.id],
                      !summary.toolDescriptors.isEmpty
                else { return nil }
                let tools = summary.toolDescriptors.map { descriptor in
                    var details: [String] = []
                    if !descriptor.schemaSummary.isEmpty {
                        details.append(descriptor.schemaSummary)
                    }
                    if !descriptor.description.isEmpty {
                        details.append(descriptor.description)
                    }
                    return details.isEmpty
                        ? descriptor.name
                        : "\(descriptor.name) [\(details.joined(separator: "; "))]"
                }
                return "- \(manifest.id) (\(manifest.name)): \(tools.joined(separator: ", "))"
            }
    }

    private func readyMCPResourceDescriptions() -> [String] {
        (selectedProject?.extensionManifests ?? [])
            .filter { manifest in
                manifest.kind == .mcpServer
                    && extensions.mcpServerStatuses[manifest.id] == .ready
                    && mcpServerProcesses[manifest.id]?.process.isRunning == true
            }
            .compactMap { manifest -> String? in
                guard let summary = extensions.mcpServerProbeSummaries[manifest.id],
                      !summary.resourceNames.isEmpty
                else { return nil }
                let resources = zip(summary.resourceNames, summary.resourceURIs).map { name, uri in
                    name == uri ? uri : "\(name) [\(uri)]"
                }
                let fallbackResources = Array(summary.resourceNames.dropFirst(resources.count))
                return "- \(manifest.id) (\(manifest.name)): \((resources + fallbackResources).joined(separator: ", "))"
            }
    }

    private func readyMCPPromptDescriptions() -> [String] {
        (selectedProject?.extensionManifests ?? [])
            .filter { manifest in
                manifest.kind == .mcpServer
                    && extensions.mcpServerStatuses[manifest.id] == .ready
                    && mcpServerProcesses[manifest.id]?.process.isRunning == true
            }
            .compactMap { manifest -> String? in
                let prompts = extensions.mcpServerProbeSummaries[manifest.id]?.promptNames ?? []
                guard !prompts.isEmpty else { return nil }
                return "- \(manifest.id) (\(manifest.name)): \(prompts.joined(separator: ", "))"
            }
    }

    private func mcpToolExecutionOverride() -> AgentToolExecutionOverride? {
        let sessions = mcpServerProcesses.compactMapValues { handle in
            handle.process.isRunning ? handle.session : nil
        }
        let summaries = extensions.mcpServerProbeSummaries
        let allowedTools = summaries.mapValues { Set($0.toolNames) }
        let allowedPrompts = summaries.mapValues { Set($0.promptNames) }
        guard !sessions.isEmpty else { return nil }

        return { call, _ in
            do {
                switch call.name {
                case ToolDefinition.mcpCall.name:
                    let request = try MCPToolCallRequest(argumentsJSON: call.argumentsJSON)
                    guard let session = sessions[request.serverID] else {
                        return ToolResult(ok: false, error: "MCP server is not running or is not Ready: \(request.serverID)")
                    }
                    guard allowedTools[request.serverID]?.contains(request.toolName) == true else {
                        return ToolResult(
                            ok: false,
                            error: "MCP tool \(request.toolName) was not advertised by \(request.serverID)."
                        )
                    }
                    return try session.callTool(
                        toolName: request.toolName,
                        argumentsJSON: request.toolArgumentsJSON
                    )

                case ToolDefinition.mcpReadResource.name:
                    let request = try MCPResourceReadRequest(argumentsJSON: call.argumentsJSON)
                    guard let session = sessions[request.serverID] else {
                        return ToolResult(ok: false, error: "MCP server is not running or is not Ready: \(request.serverID)")
                    }
                    guard let uri = Self.mcpResourceURI(
                        for: request.resourceIdentifier,
                        summary: summaries[request.serverID]
                    ) else {
                        return ToolResult(
                            ok: false,
                            error: "MCP resource \(request.resourceIdentifier) was not advertised by \(request.serverID)."
                        )
                    }
                    return try session.readResource(uri: uri)

                case ToolDefinition.mcpGetPrompt.name:
                    let request = try MCPPromptGetRequest(argumentsJSON: call.argumentsJSON)
                    guard let session = sessions[request.serverID] else {
                        return ToolResult(ok: false, error: "MCP server is not running or is not Ready: \(request.serverID)")
                    }
                    guard allowedPrompts[request.serverID]?.contains(request.promptName) == true else {
                        return ToolResult(
                            ok: false,
                            error: "MCP prompt \(request.promptName) was not advertised by \(request.serverID)."
                        )
                    }
                    return try session.getPrompt(
                        name: request.promptName,
                        argumentsJSON: request.promptArgumentsJSON
                    )

                default:
                    return nil
                }
            } catch {
                return ToolResult(ok: false, error: Self.mcpUserFacingError(error))
            }
        }
    }

    private nonisolated static func mcpResourceURI(for identifier: String, summary: MCPServerProbeSummary?) -> String? {
        guard let summary else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if summary.resourceURIs.contains(trimmed) {
            return trimmed
        }
        if summary.resourceURIs.isEmpty && summary.resourceNames.contains(trimmed) {
            return trimmed
        }
        for (index, name) in summary.resourceNames.enumerated()
            where name == trimmed && summary.resourceURIs.indices.contains(index) {
            return summary.resourceURIs[index]
        }
        return nil
    }

    private func computerUseToolExecutionOverride() -> AgentToolExecutionOverride? {
        guard let computerUseBackend else { return nil }
        let executor = ComputerUseToolExecutor(backend: computerUseBackend)
        return { call, _ in
            await executor.execute(call)
        }
    }

    private func browserToolExecutionOverride(snapshot: BrowserState) -> AgentToolExecutionOverride {
        { call, _ in
            guard call.name == ToolDefinition.browserInspect.name else { return nil }
            return BrowserInspector.toolResult(from: snapshot)
        }
    }

    private func planToolExecutionOverride() -> AgentToolExecutionOverride {
        { call, _ in
            guard call.name == ToolDefinition.planUpdate.name else { return nil }
            return PlanUpdateToolExecutor.execute(call)
        }
    }

    private func memoryToolExecutionOverride() -> AgentToolExecutionOverride? {
        guard let directory = globalMemoryDirectory else { return nil }
        return { call, _ in
            guard call.name == ToolDefinition.memoryRemember.name else { return nil }
            return Self.executeMemoryRememberTool(call, directory: directory)
        }
    }

    private func baseToolDefinitionsForSelectedProject() -> [ToolDefinition] {
        selectedProject?.isRemote == true
            ? Self.remoteProjectToolDefinitions
            : ToolRouter.definitions
    }

    private static let remoteProjectToolDefinitions: [ToolDefinition] = [
        .shellRun,
        .fileRead,
        .fileWrite,
        .applyPatch,
        .gitStatus,
        .gitDiff,
        .gitStage,
        .gitRestore,
        .gitStageHunk,
        .gitRestoreHunk,
        .gitCommit,
        .gitPush,
        .gitPullRequestCreate,
        .gitPullRequestView,
        .gitPullRequestChecks,
        .gitPullRequestDiff,
        .gitPullRequestCheckout,
        .gitPullRequestReviewers,
        .gitPullRequestLabels,
        .gitPullRequestComment,
        .gitPullRequestReview,
        .gitPullRequestMerge,
        .gitWorktreeList,
        .gitWorktreeCreate,
        .gitWorktreeRemove
    ]

    private nonisolated static let remoteProjectGitToolNames: Set<String> = [
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
        ToolDefinition.gitStage.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitStageHunk.name,
        ToolDefinition.gitRestoreHunk.name,
        ToolDefinition.gitCommit.name,
        ToolDefinition.gitPush.name,
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestMerge.name,
        ToolDefinition.gitWorktreeList.name,
        ToolDefinition.gitWorktreeCreate.name,
        ToolDefinition.gitWorktreeRemove.name
    ]

    private func remoteProjectToolExecutionOverride(project: ProjectRef?) -> AgentToolExecutionOverride? {
        guard let project, project.isRemote else { return nil }
        let connection = project.connection
        let executor = sshRemoteShellExecutor
        return { call, _ in
            switch call.name {
            case ToolDefinition.shellRun.name:
                return Self.executeRemoteShellToolCall(
                    call,
                    connection: connection,
                    executor: executor
                )
            case ToolDefinition.fileRead.name, ToolDefinition.fileWrite.name:
                return Self.executeRemoteFileToolCall(
                    call,
                    connection: connection,
                    executor: executor
                )
            case ToolDefinition.applyPatch.name:
                return Self.executeRemotePatchToolCall(
                    call,
                    connection: connection,
                    executor: executor
                )
            case let name where Self.remoteProjectGitToolNames.contains(name):
                return Self.executeRemoteGitToolCall(
                    call,
                    connection: connection,
                    executor: executor
                )
            default:
                return nil
            }
        }
    }

    private func combinedToolExecutionOverride(
        plan: AgentToolExecutionOverride?,
        browser: AgentToolExecutionOverride?,
        computerUse: AgentToolExecutionOverride?,
        memory: AgentToolExecutionOverride?,
        mcp: AgentToolExecutionOverride?,
        remoteProject: AgentToolExecutionOverride?
    ) -> AgentToolExecutionOverride? {
        guard plan != nil
                || browser != nil
                || computerUse != nil
                || memory != nil
                || mcp != nil
                || remoteProject != nil else {
            return nil
        }
        return { call, workspaceRoot in
            if let result = await plan?(call, workspaceRoot) {
                return result
            }
            if let result = await remoteProject?(call, workspaceRoot) {
                return result
            }
            if let result = await browser?(call, workspaceRoot) {
                return result
            }
            if let result = await computerUse?(call, workspaceRoot) {
                return result
            }
            if let result = await memory?(call, workspaceRoot) {
                return result
            }
            if let result = await mcp?(call, workspaceRoot) {
                return result
            }
            return nil
        }
    }

    private nonisolated static func executeRemoteGitToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let command: String
            var artifacts: [String] = []
            switch call.name {
            case ToolDefinition.gitStatus.name:
                command = "git status --short --branch"
            case ToolDefinition.gitDiff.name:
                command = args.bool("staged") == true ? "git diff --staged" : "git diff"
            case ToolDefinition.gitStage.name:
                let path = try remoteProjectRelativePath(try args.requiredString("path"))
                command = "git add -- \(shellSingleQuoted(path))"
            case ToolDefinition.gitRestore.name:
                let path = try remoteProjectRelativePath(try args.requiredString("path"))
                let stagedFlag = args.bool("staged") == true ? " --staged" : ""
                command = "git restore\(stagedFlag) -- \(shellSingleQuoted(path))"
            case ToolDefinition.gitStageHunk.name:
                command = try remoteGitHunkCommand(
                    path: try args.requiredString("path"),
                    patch: try args.requiredString("patch"),
                    applyArguments: ["--cached", "--whitespace=nowarn"],
                    successMessage: "Hunk staged.\\n"
                )
            case ToolDefinition.gitRestoreHunk.name:
                command = try remoteGitHunkCommand(
                    path: try args.requiredString("path"),
                    patch: try args.requiredString("patch"),
                    applyArguments: ["--reverse", "--whitespace=nowarn"],
                    successMessage: "Hunk restored.\\n"
                )
            case ToolDefinition.gitCommit.name:
                let message = try args.requiredString("message").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else {
                    throw GitToolError.emptyCommitMessage
                }
                command = "git commit -m \(shellSingleQuoted(message))"
            case ToolDefinition.gitPush.name:
                command = try remoteGitPushCommand(
                    remote: args.string("remote"),
                    branch: args.string("branch"),
                    setUpstream: args.bool("setUpstream") ?? false
                )
            case ToolDefinition.gitPullRequestCreate.name:
                command = try remoteGitPullRequestCommand(
                    title: args.string("title"),
                    body: args.string("body"),
                    base: args.string("base"),
                    head: args.string("head"),
                    draft: args.bool("draft") ?? false,
                    fill: args.bool("fill") ?? false
                )
            case ToolDefinition.gitPullRequestView.name:
                command = try remoteGitPullRequestViewCommand(selector: args.string("selector"))
            case ToolDefinition.gitPullRequestChecks.name:
                command = try remoteGitPullRequestChecksCommand(selector: args.string("selector"))
            case ToolDefinition.gitPullRequestDiff.name:
                command = try remoteGitPullRequestDiffCommand(selector: args.string("selector"))
            case ToolDefinition.gitPullRequestCheckout.name:
                command = try remoteGitPullRequestCheckoutCommand(
                    selector: args.string("selector"),
                    branch: args.string("branch")
                )
            case ToolDefinition.gitPullRequestReviewers.name:
                command = try remoteGitPullRequestReviewersCommand(
                    selector: args.string("selector"),
                    add: args.stringArray("add"),
                    remove: args.stringArray("remove")
                )
            case ToolDefinition.gitPullRequestLabels.name:
                command = try remoteGitPullRequestLabelsCommand(
                    selector: args.string("selector"),
                    add: args.stringArray("add"),
                    remove: args.stringArray("remove")
                )
            case ToolDefinition.gitPullRequestComment.name:
                command = try remoteGitPullRequestCommentCommand(
                    selector: args.string("selector"),
                    body: try args.requiredString("body")
                )
            case ToolDefinition.gitPullRequestReview.name:
                command = try remoteGitPullRequestReviewCommand(
                    selector: args.string("selector"),
                    action: try args.requiredString("action"),
                    body: args.string("body")
                )
            case ToolDefinition.gitPullRequestMerge.name:
                command = try remoteGitPullRequestMergeCommand(
                    selector: args.string("selector"),
                    method: args.string("method"),
                    auto: args.bool("auto") ?? false,
                    deleteBranch: args.bool("deleteBranch") ?? false
                )
            case ToolDefinition.gitWorktreeList.name:
                command = "git worktree list --porcelain"
            case ToolDefinition.gitWorktreeCreate.name:
                let worktreePath = try remoteGitWorktreePath(
                    try args.requiredString("path"),
                    connection: connection
                )
                command = remoteGitWorktreeCreateCommand(
                    worktreePath: worktreePath,
                    branch: args.string("branch"),
                    base: args.string("base")
                )
                artifacts = [remoteArtifactPath(connection: connection, absolutePath: worktreePath)]
            case ToolDefinition.gitWorktreeRemove.name:
                let worktreePath = try remoteGitWorktreePath(
                    try args.requiredString("path"),
                    connection: connection
                )
                command = remoteGitWorktreeRemoveCommand(
                    worktreePath: worktreePath,
                    force: args.bool("force") ?? false
                )
            default:
                return ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
            }

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if [
                ToolDefinition.gitPullRequestCreate.name,
                ToolDefinition.gitPullRequestView.name,
                ToolDefinition.gitPullRequestDiff.name,
                ToolDefinition.gitPullRequestCheckout.name,
                ToolDefinition.gitPullRequestReviewers.name,
                ToolDefinition.gitPullRequestLabels.name,
                ToolDefinition.gitPullRequestComment.name,
                ToolDefinition.gitPullRequestReview.name,
                ToolDefinition.gitPullRequestMerge.name
            ].contains(call.name), result.ok {
                result.artifacts = GitToolExecutor.extractURLs(from: result.stdout)
            } else if result.ok, !artifacts.isEmpty {
                result.artifacts = artifacts
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private nonisolated static func remoteGitPushCommand(
        remote: String?,
        branch: String?,
        setUpstream: Bool
    ) throws -> String {
        let remoteName = try GitToolExecutor.safeGitName(
            GitToolExecutor.trimmedNonEmpty(remote) ?? "origin"
        )
        let upstreamArguments = setUpstream ? "-u " : ""
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            let branchName = try GitToolExecutor.safeGitName(branch)
            return "git push \(upstreamArguments)\(shellSingleQuoted(remoteName)) \(shellSingleQuoted(branchName))"
        }

        let invalidBranchMessage = shellSingleQuoted(String(describing: GitToolError.invalidGitName("$branch")))
        return [
            "branch=$(git branch --show-current)",
            "test -n \"$branch\" || { printf '%s\\n' \(shellSingleQuoted(String(describing: GitToolError.noCurrentBranch))) >&2; exit 1; }",
            "case \"$branch\" in -*|*..*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*) printf '%s\\n' \(invalidBranchMessage) >&2; exit 1;; esac",
            "git push \(upstreamArguments)\(shellSingleQuoted(remoteName)) \"$branch\""
        ].joined(separator: " && ")
    }

    private nonisolated static func remoteGitPullRequestCommand(
        title: String?,
        body: String?,
        base: String?,
        head: String?,
        draft: Bool,
        fill: Bool
    ) throws -> String {
        let trimmedTitle = GitToolExecutor.trimmedNonEmpty(title)
        guard fill || trimmedTitle != nil else {
            throw GitToolError.emptyPullRequestTitle
        }

        var arguments = ["gh", "pr", "create"]
        if let trimmedTitle {
            arguments += ["--title", trimmedTitle]
        }
        if let body = GitToolExecutor.trimmedNonEmpty(body) {
            arguments += ["--body", body]
        }
        if let base = GitToolExecutor.trimmedNonEmpty(base) {
            arguments += ["--base", try GitToolExecutor.safeGitName(base)]
        }
        if let head = GitToolExecutor.trimmedNonEmpty(head) {
            arguments += ["--head", try GitToolExecutor.safeGitName(head)]
        }
        if draft {
            arguments.append("--draft")
        }
        if fill {
            arguments.append("--fill")
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestViewCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "view"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments.append("--comments")
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestChecksCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "checks"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestDiffCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "diff"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestCheckoutCommand(selector: String?, branch: String?) throws -> String {
        var arguments = ["gh", "pr", "checkout"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            arguments += ["--branch", try GitToolExecutor.safeGitName(branch)]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestReviewersCommand(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let reviewersToAdd = try GitToolExecutor.safePullRequestReviewers(add)
        let reviewersToRemove = try GitToolExecutor.safePullRequestReviewers(remove)
        guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestReviewers
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        if !reviewersToAdd.isEmpty {
            arguments += ["--add-reviewer", reviewersToAdd.joined(separator: ",")]
        }
        if !reviewersToRemove.isEmpty {
            arguments += ["--remove-reviewer", reviewersToRemove.joined(separator: ",")]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestLabelsCommand(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let labelsToAdd = try GitToolExecutor.safePullRequestLabels(add)
        let labelsToRemove = try GitToolExecutor.safePullRequestLabels(remove)
        guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestLabels
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        if !labelsToAdd.isEmpty {
            arguments += ["--add-label", labelsToAdd.joined(separator: ",")]
        }
        if !labelsToRemove.isEmpty {
            arguments += ["--remove-label", labelsToRemove.joined(separator: ",")]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestCommentCommand(
        selector: String?,
        body: String
    ) throws -> String {
        guard let body = GitToolExecutor.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }

        var arguments = ["gh", "pr", "comment"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments += ["--body", body]
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestReviewCommand(
        selector: String?,
        action: String,
        body: String?
    ) throws -> String {
        let flag = try GitToolExecutor.safePullRequestReviewFlag(action)
        let body = GitToolExecutor.trimmedNonEmpty(body)
        guard flag == "--approve" || body != nil else {
            throw GitToolError.emptyPullRequestReviewBody
        }

        var arguments = ["gh", "pr", "review"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(flag)
        if let body {
            arguments += ["--body", body]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitPullRequestMergeCommand(
        selector: String?,
        method: String?,
        auto: Bool,
        deleteBranch: Bool
    ) throws -> String {
        var arguments = ["gh", "pr", "merge"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(try GitToolExecutor.safePullRequestMergeFlag(method))
        if auto {
            arguments.append("--auto")
        }
        if deleteBranch {
            arguments.append("--delete-branch")
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitWorktreeCreateCommand(
        worktreePath: String,
        branch: String?,
        base: String?
    ) -> String {
        var arguments = ["git", "worktree", "add"]
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            arguments += ["-b", branch]
        }
        arguments.append(worktreePath)
        if let base = GitToolExecutor.trimmedNonEmpty(base) {
            arguments.append(base)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private nonisolated static func remoteGitWorktreeRemoveCommand(
        worktreePath: String,
        force: Bool
    ) -> String {
        let forceFlag = force ? " --force" : ""
        return [
            "worktree=\(shellSingleQuoted(worktreePath))",
            "git worktree list --porcelain | grep -F -x -- \"worktree $worktree\" >/dev/null || { printf 'Git worktree is not registered: %s\\n' \"$worktree\" >&2; exit 1; }",
            "git worktree remove\(forceFlag) -- \"$worktree\""
        ].joined(separator: " && ")
    }

    private nonisolated static func remoteGitWorktreePath(
        _ rawPath: String,
        connection: ProjectConnection
    ) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw GitToolError.emptyPath
        }
        guard let workspace = normalizedAbsolutePOSIXPath(connection.path) else {
            throw GitToolError.outsideWorkspace(connection.path)
        }
        let parent = posixParentPath(workspace)
        let candidateRaw = trimmed.hasPrefix("/") ? trimmed : "\(parent)/\(trimmed)"
        guard let candidate = normalizedAbsolutePOSIXPath(candidateRaw),
              isPOSIXPath(candidate, inside: parent) else {
            throw GitToolError.outsideWorkspace(rawPath)
        }
        guard candidate != workspace else {
            throw GitToolError.mainWorkspaceWorktreePath
        }
        return candidate
    }

    private nonisolated static func normalizedAbsolutePOSIXPath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return nil
        }
        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        return components.isEmpty ? "/" : "/\(components.joined(separator: "/"))"
    }

    private nonisolated static func posixParentPath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 1 else { return "/" }
        return "/\(components.dropLast().joined(separator: "/"))"
    }

    private nonisolated static func isPOSIXPath(_ path: String, inside parent: String) -> Bool {
        if parent == "/" {
            return path.hasPrefix("/")
        }
        return path == parent || path.hasPrefix("\(parent)/")
    }

    private nonisolated static func remoteGitHunkCommand(
        path: String,
        patch: String,
        applyArguments: [String],
        successMessage: String
    ) throws -> String {
        let relativePath = try remoteProjectRelativePath(path)
        var normalizedPatch = patch
        let trimmedPatch = normalizedPatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPatch.isEmpty else {
            throw GitToolError.emptyPatch
        }
        if let mismatch = GitToolExecutor.mismatchedPatchPath(
            in: normalizedPatch,
            expectedPath: relativePath
        ) {
            throw GitToolError.patchPathMismatch(mismatch)
        }
        if !normalizedPatch.hasSuffix("\n") {
            normalizedPatch.append("\n")
        }

        let encoded = Data(normalizedPatch.utf8).base64EncodedString()
        let flags = applyArguments.map(shellSingleQuoted).joined(separator: " ")
        return [
            "patch_file=\"${TMPDIR:-/tmp}/quillcode-hunk.$$.patch\"",
            "trap 'rm -f \"$patch_file\"' EXIT",
            "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \"$patch_file\"",
            "git apply \(flags) --check \"$patch_file\"",
            "git apply \(flags) \"$patch_file\"",
            "printf \(shellSingleQuoted(successMessage))"
        ].joined(separator: " && ")
    }

    private nonisolated static func executeRemoteFileToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let relativePath = try remoteProjectRelativePath(try args.requiredString("path"))
            let command: String
            switch call.name {
            case ToolDefinition.fileRead.name:
                command = "cat -- \(shellSingleQuoted(relativePath))"
            case ToolDefinition.fileWrite.name:
                let content = try args.requiredString("content")
                let encoded = Data(content.utf8).base64EncodedString()
                let directory = remoteDirectory(for: relativePath)
                command = [
                    "mkdir -p -- \(shellSingleQuoted(directory))",
                    "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \(shellSingleQuoted(relativePath))",
                    "printf 'Wrote %s\\n' \(shellSingleQuoted(relativePath))"
                ].joined(separator: " && ")
            default:
                return ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
            }

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if result.ok {
                result.artifacts = [remoteArtifactPath(connection: connection, relativePath: relativePath)]
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private nonisolated static func executeRemotePatchToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            var patch = try args.requiredString("patch")
            let trimmedPatch = patch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPatch.isEmpty else {
                return ToolResult(ok: false, error: String(describing: PatchToolError.emptyPatch))
            }
            if let unsafePath = PatchToolExecutor.unsafePath(in: patch) {
                return ToolResult(
                    ok: false,
                    error: String(describing: PatchToolError.unsafePath(unsafePath))
                )
            }
            if !patch.hasSuffix("\n") {
                patch.append("\n")
            }

            let encoded = Data(patch.utf8).base64EncodedString()
            let command = [
                "patch_file=\"${TMPDIR:-/tmp}/quillcode.$$.patch\"",
                "trap 'rm -f \"$patch_file\"' EXIT",
                "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \"$patch_file\"",
                "git apply --check \"$patch_file\"",
                "git apply \"$patch_file\"",
                "printf 'Patch applied.\\n'"
            ].joined(separator: " && ")

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            return ShellToolExecutor().run(request)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private nonisolated static func executeRemoteShellToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let command = try args.requiredString("cmd")
            let requestConnection = remoteShellConnection(
                connection,
                cwd: args.string("cwd")
            )
            guard let request = executor.request(command: command, connection: requestConnection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            return ShellToolExecutor().run(request)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private nonisolated static func remoteProjectRelativePath(_ rawPath: String) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw FileToolError.outsideWorkspace(rawPath)
        }

        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                throw FileToolError.outsideWorkspace(rawPath)
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else {
            throw FileToolError.outsideWorkspace(rawPath)
        }
        return components.joined(separator: "/")
    }

    private nonisolated static func remoteDirectory(for relativePath: String) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? "." : directory
    }

    private nonisolated static func remoteArtifactPath(
        connection: ProjectConnection,
        relativePath: String
    ) -> String {
        var copy = connection
        copy.path = remotePath(connection.path, appending: relativePath)
        return copy.displayLabel
    }

    private nonisolated static func remoteArtifactPath(
        connection: ProjectConnection,
        absolutePath: String
    ) -> String {
        var copy = connection
        copy.path = absolutePath
        return copy.displayLabel
    }

    private nonisolated static func remoteShellConnection(
        _ connection: ProjectConnection,
        cwd: String?
    ) -> ProjectConnection {
        let trimmedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCWD.isEmpty else { return connection }
        var copy = connection
        if trimmedCWD.hasPrefix("/") || trimmedCWD.hasPrefix("~") {
            copy.path = trimmedCWD
        } else {
            copy.path = remotePath(connection.path, appending: trimmedCWD)
        }
        return copy
    }

    private nonisolated static func remotePath(_ base: String, appending relativePath: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRelative.isEmpty else { return trimmedBase.isEmpty ? "~" : trimmedBase }

        let isAbsolute = trimmedBase.hasPrefix("/")
        let isHome = trimmedBase == "~" || trimmedBase.hasPrefix("~/")
        let baseRemainder: String
        if isAbsolute {
            baseRemainder = trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if isHome {
            baseRemainder = String(trimmedBase.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            baseRemainder = trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var components: [String] = []
        for component in ([baseRemainder, trimmedRelative].filter { !$0.isEmpty }.joined(separator: "/")).split(separator: "/") {
            switch component {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                } else if !isAbsolute && !isHome {
                    components.append(String(component))
                }
            default:
                components.append(String(component))
            }
        }

        let suffix = components.joined(separator: "/")
        if isAbsolute {
            return "/" + suffix
        }
        if isHome || trimmedBase.isEmpty {
            return suffix.isEmpty ? "~" : "~/" + suffix
        }
        return suffix.isEmpty ? "." : suffix
    }

    private nonisolated static func executeMemoryRememberTool(_ call: ToolCall, directory: URL) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let content = try args.requiredString("content")
            let saved = try saveGlobalMemory(content: content, to: directory)
            return ToolResult(
                ok: true,
                stdout: try JSONHelpers.encodePretty(saved.output),
                artifacts: [saved.note.relativePath]
            )
        } catch {
            return ToolResult(
                ok: false,
                error: userFacingMemoryError(error)
            )
        }
    }

    private nonisolated static func saveGlobalMemory(
        content: String,
        to directory: URL
    ) throws -> (note: MemoryNote, output: MemoryRememberToolOutput) {
        let note = try MemoryNoteLoader.saveGlobal(content: content, to: directory)
        let output = MemoryRememberToolOutput(
            title: note.title,
            relativePath: note.relativePath,
            content: note.content
        )
        return (note, output)
    }

    private nonisolated static func userFacingMemoryError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.isEmpty {
            return localized
        }
        return String(describing: error)
    }

    private nonisolated static func didSaveMemory(in thread: ChatThread) -> Bool {
        thread.events.contains { event in
            guard event.kind == .toolCompleted,
                  event.summary == "\(ToolDefinition.memoryRemember.name) completed",
                  let result = decode(ToolResult.self, event.payloadJSON),
                  result.ok
            else {
                return false
            }
            return result.artifacts.contains { $0.hasPrefix("memories/") }
        }
    }

    private nonisolated static func mcpUserFacingError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.isEmpty {
            return localized
        }
        return String(describing: error)
    }

    private func appendNotice(_ summary: String) {
        mutateSelectedThread { thread in
            thread.events.append(.init(kind: .notice, summary: summary))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
    }

    @discardableResult
    private func deleteGlobalMemory(id: String) -> Bool {
        guard let globalMemoryDirectory else { return false }
        do {
            let note = try MemoryNoteLoader.deleteGlobal(id: id, from: globalMemoryDirectory)
            root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
            let projectID = selectedThread?.projectID ?? root.selectedProjectID
            let refreshedMemories = memoryNotes(for: projectID)
            appendLocalCommandTranscript(
                userText: "Forget memory: \(note.title)",
                assistantText: "Forgot memory: \(note.title). It will no longer be included as background context.",
                title: "Forgot memory: \(note.title)"
            )
            mutateSelectedThread { thread in
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Forgot memory: \(note.title)",
                    payloadJSON: note.relativePath
                ))
            }
            refreshTopBar(agentStatus: "Idle")
            return true
        } catch let error as MemoryNoteDeleteError {
            appendLocalCommandTranscript(
                userText: "Forget memory",
                assistantText: error.localizedDescription,
                title: "Memory not deleted"
            )
            refreshTopBar(agentStatus: "Idle")
            return true
        } catch {
            appendLocalCommandTranscript(
                userText: "Forget memory",
                assistantText: MemoryNoteDeleteError.deleteFailed.localizedDescription,
                title: "Memory not deleted"
            )
            refreshTopBar(agentStatus: "Idle")
            return true
        }
    }

    @discardableResult
    public func runLocalEnvironmentAction(_ actionID: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let action = localAction(withID: actionID) else {
            return false
        }
        var arguments: [String: Any] = ["cmd": action.command]
        if let environment = action.environment {
            arguments["environment"] = environment
        }
        if let timeoutSeconds = action.timeoutSeconds {
            arguments["timeoutSeconds"] = timeoutSeconds
        }
        runToolCall(
            ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: toolArgumentsJSON(arguments)
            ),
            workspaceRoot: workspaceRoot
        )
        return true
    }

    @discardableResult
    public func runProjectExtensionUpdate(id: String, workspaceRoot: URL) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let manifest = selectedProject?.extensionManifests.first(where: { $0.id == id }),
              let command = manifest.updateCommand,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        var arguments: [String: Any] = ["cmd": command]
        if let timeoutSeconds = manifest.updateTimeoutSeconds {
            arguments["timeoutSeconds"] = timeoutSeconds
        }
        let result = runToolCall(
            ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: toolArgumentsJSON(arguments)
            ),
            workspaceRoot: workspaceRoot
        )
        refreshProjectMetadata(root.selectedProjectID)
        appendNotice(result.ok
            ? "Updated extension \(manifest.name)"
            : "Extension update failed for \(manifest.name)"
        )
        return result.ok
    }

    public func createWorktree(_ request: WorkspaceWorktreeCreateRequest, workspaceRoot: URL) {
        var arguments: [String: Any] = ["path": request.path]
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = request.base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            arguments["branch"] = branch
        }
        if !base.isEmpty {
            arguments["base"] = base
        }
        let result = runToolCall(
            ToolCall(
                name: ToolDefinition.gitWorktreeCreate.name,
                argumentsJSON: toolArgumentsJSON(arguments)
            ),
            workspaceRoot: workspaceRoot
        )
        if result.ok {
            openCreatedWorktree(result, request: request)
        }
    }

    public func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest, workspaceRoot: URL) {
        runToolCall(
            ToolCall(
                name: ToolDefinition.gitWorktreeRemove.name,
                argumentsJSON: toolArgumentsJSON([
                    "path": request.path,
                    "force": request.force
                ])
            ),
            workspaceRoot: workspaceRoot
        )
    }

    @discardableResult
    public func runToolCall(_ call: ToolCall, workspaceRoot: URL) -> ToolResult {
        if selectedThread == nil {
            _ = newChat()
        }
        guard selectedThread != nil else {
            return ToolResult(ok: false, error: "No active thread")
        }
        let contextProjectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshProjectMetadata(contextProjectID)
        let refreshedMemories = memoryNotes(for: contextProjectID)
        let refreshedInstructions = instructions(for: contextProjectID)
        mutateSelectedThread { thread in
            thread.memories = refreshedMemories
            thread.instructions = refreshedInstructions
        }
        lastError = nil
        refreshTopBar(agentStatus: "Running")

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let result: ToolResult
        if call.name == ToolDefinition.browserInspect.name {
            result = BrowserInspector.toolResult(from: browser)
        } else if call.name == ToolDefinition.planUpdate.name {
            result = PlanUpdateToolExecutor.execute(call)
        } else if selectedProject?.isRemote == true,
                  call.name == ToolDefinition.shellRun.name,
                  let project = selectedProject {
            result = Self.executeRemoteShellToolCall(
                call,
                connection: project.connection,
                executor: sshRemoteShellExecutor
            )
        } else if selectedProject?.isRemote == true,
                  (call.name == ToolDefinition.fileRead.name || call.name == ToolDefinition.fileWrite.name),
                  let project = selectedProject {
            result = Self.executeRemoteFileToolCall(
                call,
                connection: project.connection,
                executor: sshRemoteShellExecutor
            )
        } else if selectedProject?.isRemote == true,
                  call.name == ToolDefinition.applyPatch.name,
                  let project = selectedProject {
            result = Self.executeRemotePatchToolCall(
                call,
                connection: project.connection,
                executor: sshRemoteShellExecutor
            )
        } else if selectedProject?.isRemote == true,
                  Self.remoteProjectGitToolNames.contains(call.name),
                  let project = selectedProject {
            result = Self.executeRemoteGitToolCall(
                call,
                connection: project.connection,
                executor: sshRemoteShellExecutor
            )
        } else if selectedProject?.isRemote == true {
            result = ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
        } else {
            result = router.execute(call)
        }
        appendToolRun(call: call, result: result)
        let followUpResult = appendReviewDiffAfterPatchIfNeeded(
            call: call,
            result: result,
            router: router
        )

        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
        let ok = result.ok && (followUpResult?.ok ?? true)
        refreshTopBar(agentStatus: ok ? "Idle" : "Failed")
        return result
    }

    public func runTerminalCommand(workspaceRoot: URL) async {
        await runTerminalCommand(terminal.draft, workspaceRoot: workspaceRoot)
    }

    public func runTerminalCommand(_ input: String, workspaceRoot: URL) async {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !terminal.isRunning else { return }
        syncTerminalSessionToSelectedProject()

        let entryID = UUID()
        terminal.draft = ""
        terminal.isVisible = true
        terminal.isRunning = true
        terminal.entries.append(TerminalCommandState(
            id: entryID,
            command: command,
            stdout: "",
            stderr: "",
            exitCode: nil,
            ok: false,
            status: .running
        ))
        lastError = nil
        refreshTopBar(agentStatus: "Terminal")

        guard let executionContext = terminalExecutionContext(command: command, workspaceRoot: workspaceRoot) else {
            finishTerminalEntry(
                id: entryID,
                stdout: "",
                stderr: "SSH Remote project is missing a usable host.",
                exitCode: nil,
                ok: false,
                status: .failed
            )
            terminal.isRunning = false
            refreshTopBar(agentStatus: "Failed")
            return
        }
        updateTerminalEntryExecutionContext(id: entryID, executionContext.surface)

        var finalResult: ToolResult?
        for await event in ShellToolExecutor().runStreaming(executionContext.request) {
            if Task.isCancelled || terminal.entries.first(where: { $0.id == entryID })?.status == .stopped {
                break
            }
            switch event {
            case .stdout(let text):
                appendTerminalOutput(id: entryID, stdout: text)
            case .stderr(let text):
                appendTerminalOutput(id: entryID, stderr: text)
            case .finished(let result):
                finalResult = result
            }
        }

        if terminal.entries.first(where: { $0.id == entryID })?.status == .stopped {
            Self.removeTerminalMarkers(executionContext.markerURLs)
            terminal.isRunning = false
            refreshTopBar(agentStatus: "Stopped")
            return
        }
        guard !Task.isCancelled, let result = finalResult else {
            Self.removeTerminalMarkers(executionContext.markerURLs)
            finishTerminalEntry(
                id: entryID,
                stdout: "",
                stderr: "Command stopped.",
                exitCode: nil,
                ok: false,
                status: .stopped
            )
            terminal.isRunning = false
            lastError = nil
            refreshTopBar(agentStatus: "Stopped")
            return
        }

        let terminalResult = Self.terminalSessionResult(for: executionContext, stdout: result.stdout)
        terminal.currentDirectoryPath = terminalResult.currentDirectoryPath
        if let environmentDelta = terminalResult.environmentDelta {
            terminal.environmentOverrides = environmentDelta.overrides
            terminal.removedEnvironmentKeys = environmentDelta.removedKeys
        }
        finishTerminalEntry(
            id: entryID,
            stdout: terminalResult.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            ok: result.ok,
            status: result.ok ? .done : .failed
        )
        terminal.isRunning = false
        refreshTopBar(agentStatus: result.ok ? "Idle" : "Failed")
    }

    private func appendTerminalOutput(id: UUID, stdout: String = "", stderr: String = "") {
        guard let index = terminal.entries.firstIndex(where: { $0.id == id }),
              terminal.entries[index].status == .running else {
            return
        }
        terminal.entries[index].stdout += stdout
        terminal.entries[index].stderr += stderr
    }

    private func updateTerminalEntryExecutionContext(id: UUID, _ executionContext: ExecutionContextSurface) {
        guard let index = terminal.entries.firstIndex(where: { $0.id == id }) else { return }
        terminal.entries[index].executionContext = executionContext
    }

    private struct TerminalExecutionContext {
        var request: ShellExecutionRequest
        var cwdMarkerURL: URL?
        var environmentMarkerURL: URL?
        var remoteMarker: String?
        var remoteConnection: ProjectConnection?
        var fallbackCurrentDirectoryPath: String
        var surface: ExecutionContextSurface

        var markerURLs: [URL] {
            [cwdMarkerURL, environmentMarkerURL].compactMap { $0 }
        }
    }

    private func terminalExecutionContext(
        command: String,
        workspaceRoot: URL
    ) -> TerminalExecutionContext? {
        if let selectedProject, selectedProject.isRemote {
            let connection = Self.remoteTerminalConnection(
                for: selectedProject,
                terminalCurrentDirectoryPath: terminal.currentDirectoryPath
            )
            let marker = Self.remoteTerminalMarker()
            let wrappedCommand = Self.remoteTerminalWrappedCommand(
                command,
                marker: marker,
                environmentOverrides: terminal.environmentOverrides,
                removedEnvironmentKeys: terminal.removedEnvironmentKeys
            )
            guard let request = sshRemoteShellExecutor.request(
                command: wrappedCommand,
                connection: connection
            ) else {
                return nil
            }
            return TerminalExecutionContext(
                request: request,
                cwdMarkerURL: nil,
                environmentMarkerURL: nil,
                remoteMarker: marker,
                remoteConnection: connection,
                fallbackCurrentDirectoryPath: connection.displayLabel,
                surface: .project(selectedProject)
            )
        }

        let environment = Self.effectiveTerminalEnvironment(
            overrides: terminal.environmentOverrides,
            removedKeys: terminal.removedEnvironmentKeys
        )
        let workingDirectory = terminalCurrentDirectoryURL ?? workspaceRoot.standardizedFileURL
        return Self.localTerminalExecutionContext(
            command: command,
            workingDirectory: workingDirectory,
            environment: environment,
            executionContext: .local(path: workingDirectory.standardizedFileURL.path)
        )
    }

    private static func localTerminalExecutionContext(
        command: String,
        workingDirectory: URL,
        environment: [String: String],
        executionContext: ExecutionContextSurface
    ) -> TerminalExecutionContext {
        let markerID = UUID().uuidString
        let markerDirectory = FileManager.default.temporaryDirectory
        let cwdMarkerURL = markerDirectory.appendingPathComponent("quillcode-terminal-\(markerID).cwd")
        let environmentMarkerURL = markerDirectory.appendingPathComponent("quillcode-terminal-\(markerID).env")
        let cwdMarkerPath = shellSingleQuoted(cwdMarkerURL.path)
        let environmentMarkerPath = shellSingleQuoted(environmentMarkerURL.path)
        let wrappedCommand = """
        \(command)
        status=$?
        printf '%s\n' "$PWD" > \(cwdMarkerPath)
        /usr/bin/env -0 > \(environmentMarkerPath)
        exit "$status"
        """
        return TerminalExecutionContext(
            request: ShellExecutionRequest(
                command: wrappedCommand,
                cwd: workingDirectory,
                environment: environment
            ),
            cwdMarkerURL: cwdMarkerURL,
            environmentMarkerURL: environmentMarkerURL,
            remoteMarker: nil,
            remoteConnection: nil,
            fallbackCurrentDirectoryPath: workingDirectory.standardizedFileURL.path,
            surface: executionContext
        )
    }

    private static func remoteTerminalConnection(
        for project: ProjectRef,
        terminalCurrentDirectoryPath: String?
    ) -> ProjectConnection {
        var connection = project.connection
        let current = terminalCurrentDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !current.isEmpty else { return connection }
        if current.hasPrefix("/") || current == "~" || current.hasPrefix("~/") {
            connection.path = current
            return connection
        }
        guard let prefix = remoteTerminalDisplayPrefix(for: connection),
              current.hasPrefix(prefix) else {
            return connection
        }
        let path = String(current.dropFirst(prefix.count))
        connection.path = path.isEmpty ? "/" : path
        return connection
    }

    private static func remoteTerminalDisplayPrefix(for connection: ProjectConnection) -> String? {
        guard connection.kind == .ssh,
              let host = connection.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        let userPrefix = connection.user.map { "\($0)@" } ?? ""
        let portSuffix = connection.port.map { ":\($0)" } ?? ""
        return "ssh://\(userPrefix)\(host)\(portSuffix)"
    }

    private static func remoteTerminalMarker() -> String {
        "__QUILLCODE_TERMINAL_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
    }

    private static func remoteTerminalWrappedCommand(
        _ command: String,
        marker: String,
        environmentOverrides: [String: String],
        removedEnvironmentKeys: Set<String>
    ) -> String {
        let environmentPreamble = remoteTerminalEnvironmentPreamble(
            overrides: environmentOverrides,
            removedKeys: removedEnvironmentKeys
        )
        return """
        __quillcode_base_env="$(/usr/bin/env -0 | od -An -tx1 | tr -d ' \\n')"
        \(environmentPreamble)
        \(command)
        __quillcode_status=$?
        printf '\\n\(marker):cwd\\n%s\\n' "$PWD"
        printf '\(marker):base-env\\n%s\\n' "$__quillcode_base_env"
        printf '\(marker):final-env\\n'
        /usr/bin/env -0 | od -An -tx1 | tr -d ' \\n'
        printf '\\n\(marker):end\\n'
        exit "$__quillcode_status"
        """
    }

    private static func remoteTerminalEnvironmentPreamble(
        overrides: [String: String],
        removedKeys: Set<String>
    ) -> String {
        let unsetLines = removedKeys
            .filter(isValidShellEnvironmentKey)
            .sorted()
            .map { "unset \($0)" }
        let exportLines = overrides
            .filter { isValidShellEnvironmentKey($0.key) }
            .sorted { $0.key < $1.key }
            .map { "export \($0.key)=\(shellSingleQuoted($0.value))" }
        return (unsetLines + exportLines).joined(separator: "\n")
    }

    private static func isValidShellEnvironmentKey(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              first == "_" || CharacterSet.letters.contains(first) else {
            return false
        }
        return value.unicodeScalars.dropFirst().allSatisfy {
            $0 == "_" || CharacterSet.alphanumerics.contains($0)
        }
    }

    private struct TerminalSessionResult {
        var stdout: String
        var currentDirectoryPath: String
        var environmentDelta: TerminalEnvironmentDelta?
    }

    private static func terminalSessionResult(
        for context: TerminalExecutionContext,
        stdout: String
    ) -> TerminalSessionResult {
        if let marker = context.remoteMarker,
           let connection = context.remoteConnection,
           let metadata = remoteTerminalMetadata(from: stdout, marker: marker) {
            var updated = connection
            if !metadata.cwd.isEmpty {
                updated.path = metadata.cwd
            }
            return TerminalSessionResult(
                stdout: metadata.stdout,
                currentDirectoryPath: updated.displayLabel,
                environmentDelta: remoteTerminalEnvironmentDelta(metadata)
            )
        }

        let environmentDelta: TerminalEnvironmentDelta?
        if let environmentMarkerURL = context.environmentMarkerURL {
            environmentDelta = terminalEnvironmentDelta(markerURL: environmentMarkerURL)
        } else {
            environmentDelta = nil
        }
        return TerminalSessionResult(
            stdout: stdout,
            currentDirectoryPath: terminalCurrentDirectoryPath(for: context),
            environmentDelta: environmentDelta
        )
    }

    private struct RemoteTerminalMetadata {
        var stdout: String
        var cwd: String
        var baseEnvironment: [String: String]?
        var finalEnvironment: [String: String]?
    }

    private static func remoteTerminalMetadata(from stdout: String, marker: String) -> RemoteTerminalMetadata? {
        let cwdToken = "\n\(marker):cwd\n"
        let baseToken = "\n\(marker):base-env\n"
        let finalToken = "\n\(marker):final-env\n"
        let endToken = "\n\(marker):end\n"
        guard let cwdRange = stdout.range(of: cwdToken) else {
            return nil
        }

        let visibleStdout = String(stdout[..<cwdRange.lowerBound])
        let afterCWDToken = stdout[cwdRange.upperBound...]
        guard let baseRange = afterCWDToken.range(of: baseToken) else {
            return RemoteTerminalMetadata(
                stdout: visibleStdout,
                cwd: String(afterCWDToken).trimmingCharacters(in: .whitespacesAndNewlines),
                baseEnvironment: nil,
                finalEnvironment: nil
            )
        }
        let cwd = String(afterCWDToken[..<baseRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterBaseToken = afterCWDToken[baseRange.upperBound...]
        guard let finalRange = afterBaseToken.range(of: finalToken) else {
            return RemoteTerminalMetadata(
                stdout: visibleStdout,
                cwd: cwd,
                baseEnvironment: nil,
                finalEnvironment: nil
            )
        }
        let baseHex = String(afterBaseToken[..<finalRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let afterFinalToken = afterBaseToken[finalRange.upperBound...]
        guard let endRange = afterFinalToken.range(of: endToken) else {
            return RemoteTerminalMetadata(
                stdout: visibleStdout,
                cwd: cwd,
                baseEnvironment: nil,
                finalEnvironment: nil
            )
        }
        let finalHex = String(afterFinalToken[..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return RemoteTerminalMetadata(
            stdout: visibleStdout,
            cwd: cwd,
            baseEnvironment: terminalEnvironment(fromHex: baseHex),
            finalEnvironment: terminalEnvironment(fromHex: finalHex)
        )
    }

    private static func remoteTerminalEnvironmentDelta(
        _ metadata: RemoteTerminalMetadata
    ) -> TerminalEnvironmentDelta? {
        guard let baseEnvironment = metadata.baseEnvironment,
              let finalEnvironment = metadata.finalEnvironment else {
            return nil
        }
        var overrides: [String: String] = [:]
        for (key, value) in finalEnvironment
            where baseEnvironment[key] != value
                && !ignoredTerminalEnvironmentDeltaKeys.contains(key) {
            overrides[key] = value
        }
        let removedKeys = Set(baseEnvironment.keys.filter {
            finalEnvironment[$0] == nil && !ignoredTerminalEnvironmentDeltaKeys.contains($0)
        })
        return TerminalEnvironmentDelta(overrides: overrides, removedKeys: removedKeys)
    }

    private static func terminalCurrentDirectoryPath(for context: TerminalExecutionContext) -> String {
        guard let markerURL = context.cwdMarkerURL else {
            return context.fallbackCurrentDirectoryPath
        }
        defer { removeTerminalMarker(at: markerURL) }
        guard let rawPath = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return context.fallbackCurrentDirectoryPath
        }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return context.fallbackCurrentDirectoryPath
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private struct TerminalEnvironmentDelta {
        var overrides: [String: String]
        var removedKeys: Set<String>
    }

    private static let ignoredTerminalEnvironmentDeltaKeys: Set<String> = [
        "PWD",
        "OLDPWD",
        "SHLVL",
        "_"
    ]

    private static func effectiveTerminalEnvironment(
        overrides: [String: String],
        removedKeys: Set<String>
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in removedKeys {
            environment.removeValue(forKey: key)
        }
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }

    private static func terminalEnvironmentDelta(markerURL: URL) -> TerminalEnvironmentDelta? {
        defer { removeTerminalMarker(at: markerURL) }
        guard let data = try? Data(contentsOf: markerURL) else {
            return nil
        }
        let finalEnvironment = terminalEnvironment(from: data)
        let baseEnvironment = ProcessInfo.processInfo.environment
        var overrides: [String: String] = [:]
        for (key, value) in finalEnvironment
            where baseEnvironment[key] != value
                && !ignoredTerminalEnvironmentDeltaKeys.contains(key) {
            overrides[key] = value
        }
        let removedKeys = Set(baseEnvironment.keys.filter {
            finalEnvironment[$0] == nil && !ignoredTerminalEnvironmentDeltaKeys.contains($0)
        })
        return TerminalEnvironmentDelta(overrides: overrides, removedKeys: removedKeys)
    }

    private static func terminalEnvironment(from data: Data) -> [String: String] {
        var environment: [String: String] = [:]
        for entry in data.split(separator: 0, omittingEmptySubsequences: true) {
            let text = String(decoding: entry, as: UTF8.self)
            guard let equalsIndex = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<equalsIndex])
            let value = String(text[text.index(after: equalsIndex)...])
            guard !key.isEmpty else { continue }
            environment[key] = value
        }
        return environment
    }

    private static func terminalEnvironment(fromHex hex: String) -> [String: String]? {
        let scalars = Array(hex.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
        guard scalars.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(scalars.count / 2)
        var index = 0
        while index < scalars.count {
            let pair = String(String.UnicodeScalarView([scalars[index], scalars[index + 1]]))
            guard let byte = UInt8(pair, radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        return terminalEnvironment(from: Data(bytes))
    }

    private static func removeTerminalMarkers(_ urls: [URL]) {
        for url in urls {
            removeTerminalMarker(at: url)
        }
    }

    private static func removeTerminalMarker(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private nonisolated static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func finishTerminalEntry(
        id: UUID,
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        status: TerminalCommandStatus
    ) {
        guard let index = terminal.entries.firstIndex(where: { $0.id == id }) else { return }
        if terminal.entries[index].status == .stopped, status != .stopped {
            return
        }
        terminal.entries[index].stdout = stdout
        terminal.entries[index].stderr = stderr
        terminal.entries[index].exitCode = exitCode
        terminal.entries[index].ok = ok
        terminal.entries[index].status = status
    }

    public func cancelActiveWork() {
        let runningMCPIDs = mcpServerProcesses.compactMap { id, handle in
            handle.process.isRunning ? id : nil
        }
        let hadActiveWork = composer.isSending || terminal.isRunning || !runningMCPIDs.isEmpty
        composer.isSending = false
        terminal.isRunning = false
        for index in terminal.entries.indices where terminal.entries[index].status == .running {
            terminal.entries[index].stderr = terminal.entries[index].stderr.isEmpty
                ? "Command stopped."
                : terminal.entries[index].stderr
            terminal.entries[index].exitCode = nil
            terminal.entries[index].ok = false
            terminal.entries[index].status = .stopped
        }
        for id in runningMCPIDs {
            mcpServerProcesses[id]?.standardOutput.fileHandleForReading.readabilityHandler = nil
            mcpServerProcesses[id]?.standardError.fileHandleForReading.readabilityHandler = nil
            mcpServerProcesses[id]?.process.terminate()
            mcpServerProcesses[id] = nil
            extensions.mcpServerStatuses[id] = .stopped
            extensions.mcpServerProbeSummaries[id] = nil
        }
        lastError = nil
        if hadActiveWork {
            refreshTopBar(agentStatus: "Stopped")
        }
    }

    public static func toolCards(for thread: ChatThread) -> [ToolCardState] {
        var cards: [ToolCardState] = []
        var activeToolCardIndex: Int?

        func updateActiveToolCard(status: ToolCardStatus, subtitle: String, outputJSON: String? = nil) {
            guard let index = activeToolCardIndex else {
                return
            }
            updateCard(&cards, at: index, status: status, subtitle: subtitle, outputJSON: outputJSON)
            if status == .done || status == .failed {
                activeToolCardIndex = nil
            }
        }

        for event in thread.events {
            switch event.kind {
            case .toolQueued:
                let call = decode(ToolCall.self, event.payloadJSON)
                cards.append(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: call?.name ?? "Tool",
                    subtitle: "Queued",
                    status: .queued,
                    inputJSON: call?.argumentsJSON ?? event.payloadJSON
                ))
                activeToolCardIndex = cards.count - 1
            case .toolRunning:
                updateActiveToolCard(status: .running, subtitle: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    subtitle: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                cards.append(ToolCardState(
                    id: event.id.uuidString,
                    title: "Safety Check",
                    subtitle: event.summary,
                    status: .review,
                    inputJSON: event.payloadJSON,
                    isExpanded: true
                ))
            case .message, .messageFeedback, .approvalDecided, .reviewComment, .notice:
                continue
            }
        }

        return cards
    }

    public static func messageSurfaces(for thread: ChatThread) -> [MessageSurface] {
        let feedbackByMessageID = messageFeedbackByMessageID(for: thread)
        return thread.messages
            .filter { $0.role != .tool }
            .map { message in
                MessageSurface(message: message, feedback: feedbackByMessageID[message.id])
            }
    }

    public static func transcriptTimelineItems(for thread: ChatThread) -> [TranscriptTimelineItemSurface] {
        guard !thread.events.isEmpty else {
            return messageSurfaces(for: thread).map(TranscriptTimelineItemSurface.message)
                + toolCards(for: thread).map(TranscriptTimelineItemSurface.toolCard)
        }

        let feedbackByMessageID = messageFeedbackByMessageID(for: thread)
        var consumedMessageIDs = Set<UUID>()
        var items: [TranscriptTimelineItemSurface] = []
        var activeToolItemIndex: Int?

        func appendMessage(matching summary: String) {
            guard let message = thread.messages.first(where: {
                !consumedMessageIDs.contains($0.id) && $0.content == summary
            }) else {
                return
            }
            consumedMessageIDs.insert(message.id)
            items.append(.message(MessageSurface(message: message, feedback: feedbackByMessageID[message.id])))
        }

        func appendToolCard(_ card: ToolCardState) {
            items.append(.toolCard(card))
            activeToolItemIndex = items.count - 1
        }

        func updateActiveToolCard(status: ToolCardStatus, subtitle: String, outputJSON: String? = nil) {
            guard let index = activeToolItemIndex,
                  var card = items[index].toolCard
            else {
                appendToolCard(ToolCardState(
                    id: "orphan-\(UUID().uuidString)",
                    title: "Tool",
                    subtitle: subtitle,
                    status: status,
                    outputJSON: outputJSON,
                    artifacts: outputJSON.map(Self.artifacts(from:)) ?? []
                ))
                return
            }
            card.status = status
            card.subtitle = subtitle
            card.density = ToolCardState.defaultDensity(status: status, isExpanded: card.isExpanded)
            card.isExpanded = card.density == .expanded
            if let outputJSON {
                card.outputJSON = outputJSON
                card.artifacts = Self.artifacts(from: outputJSON)
            }
            items[index] = .toolCard(card)
            if status == .done || status == .failed {
                activeToolItemIndex = nil
            }
        }

        for event in thread.events {
            switch event.kind {
            case .message:
                appendMessage(matching: event.summary)
            case .toolQueued:
                let call = decode(ToolCall.self, event.payloadJSON)
                appendToolCard(ToolCardState(
                    id: call?.id ?? event.id.uuidString,
                    title: call?.name ?? "Tool",
                    subtitle: "Queued",
                    status: .queued,
                    inputJSON: call?.argumentsJSON ?? event.payloadJSON
                ))
            case .toolRunning:
                updateActiveToolCard(status: .running, subtitle: "Running")
            case .toolCompleted:
                updateActiveToolCard(
                    status: .done,
                    subtitle: "Completed",
                    outputJSON: event.payloadJSON
                )
            case .toolFailed:
                updateActiveToolCard(
                    status: .failed,
                    subtitle: "Failed",
                    outputJSON: event.payloadJSON
                )
            case .approvalRequested:
                items.append(.toolCard(ToolCardState(
                    id: event.id.uuidString,
                    title: "Safety Check",
                    subtitle: event.summary,
                    status: .review,
                    inputJSON: event.payloadJSON,
                    isExpanded: true
                )))
            case .messageFeedback, .approvalDecided, .reviewComment, .notice:
                continue
            }
        }

        for message in thread.messages where message.role != .tool && !consumedMessageIDs.contains(message.id) {
            items.append(.message(MessageSurface(message: message, feedback: feedbackByMessageID[message.id])))
        }
        return items
    }

    private static func messageFeedbackByMessageID(for thread: ChatThread) -> [UUID: MessageFeedbackValue] {
        var feedbackByMessageID: [UUID: MessageFeedbackValue] = [:]
        for event in thread.events where event.kind == .messageFeedback {
            guard let feedback = decode(MessageFeedback.self, event.payloadJSON) else { continue }
            feedbackByMessageID[feedback.messageID] = feedback.value
        }
        return feedbackByMessageID
    }

    private func appendToolRun(call: ToolCall, result: ToolResult) {
        let transcriptCall = call.redactedForTranscript()
        let callJSON = (try? JSONHelpers.encodePretty(transcriptCall)) ?? transcriptCall.argumentsJSON
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        mutateSelectedThread { thread in
            thread.events.append(.init(
                kind: .toolQueued,
                summary: "\(call.name) queued",
                payloadJSON: callJSON
            ))
            thread.events.append(.init(
                kind: .toolRunning,
                summary: "\(call.name) running"
            ))
            thread.events.append(.init(
                kind: result.ok ? .toolCompleted : .toolFailed,
                summary: "\(call.name) \(result.ok ? "completed" : "failed")",
                payloadJSON: resultJSON
            ))
        }
    }

    private func openCreatedWorktree(_ result: ToolResult, request: WorkspaceWorktreeCreateRequest) {
        guard let artifact = result.artifacts.first else { return }
        if selectedProject?.isRemote == true {
            openCreatedRemoteWorktree(artifact, request: request)
            return
        }
        let worktreeURL = URL(fileURLWithPath: artifact).standardizedFileURL
        guard FileManager.default.fileExists(atPath: worktreeURL.path) else { return }

        let projectID = addProject(path: worktreeURL, name: Self.defaultProjectName(for: worktreeURL))
        refreshProjectMetadata(projectID)

        let titleLabel = Self.worktreeThreadLabel(request: request, url: worktreeURL)
        let messageText = "Opened worktree `\(worktreeURL.lastPathComponent)` at `\(worktreeURL.path)`."
        let message = ChatMessage(role: .assistant, content: messageText)
        let thread = ChatThread(
            title: "Worktree: \(titleLabel)",
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            messages: [message],
            events: [
                .init(
                    kind: .notice,
                    summary: "Opened worktree \(worktreeURL.lastPathComponent)",
                    payloadJSON: worktreeURL.path
                ),
                .init(kind: .message, summary: messageText)
            ],
            instructions: instructions(for: projectID),
            memories: memoryNotes(for: projectID)
        )

        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = projectID
        syncTerminalSessionToSelectedProject()
        touchProject(projectID)
        saveProjects()
        try? threadStore?.save(thread)
        refreshTopBar(agentStatus: "Idle")
    }

    private func openCreatedRemoteWorktree(_ artifact: String, request: WorkspaceWorktreeCreateRequest) {
        guard let connection = ProjectConnection.parseSSH(artifact),
              let projectID = addSSHProject(artifact, name: Self.defaultSSHProjectName(for: connection)) else {
            return
        }

        let titleLabel = Self.worktreeThreadLabel(request: request, path: connection.path)
        let pathName = URL(fileURLWithPath: connection.path).lastPathComponent
        let displayName = pathName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? connection.displayLabel
            : pathName
        let messageText = "Opened remote worktree `\(displayName)` at `\(connection.displayLabel)`."
        let message = ChatMessage(role: .assistant, content: messageText)
        let thread = ChatThread(
            title: "Worktree: \(titleLabel)",
            projectID: projectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            messages: [message],
            events: [
                .init(
                    kind: .notice,
                    summary: "Opened remote worktree \(displayName)",
                    payloadJSON: connection.displayLabel
                ),
                .init(kind: .message, summary: messageText)
            ],
            instructions: instructions(for: projectID),
            memories: memoryNotes(for: projectID)
        )

        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = projectID
        syncTerminalSessionToSelectedProject()
        touchProject(projectID)
        saveProjects()
        try? threadStore?.save(thread)
        refreshTopBar(agentStatus: "Idle")
    }

    private static func worktreeThreadLabel(request: WorkspaceWorktreeCreateRequest, url: URL) -> String {
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }
        return defaultProjectName(for: url)
    }

    private static func worktreeThreadLabel(request: WorkspaceWorktreeCreateRequest, path: String) -> String {
        let branch = request.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }
        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? path : lastPathComponent
    }

    @discardableResult
    private func appendReviewDiffAfterPatchIfNeeded(
        call: ToolCall,
        result: ToolResult,
        router: ToolRouter
    ) -> ToolResult? {
        guard call.name == ToolDefinition.applyPatch.name, result.ok else {
            return nil
        }
        let diffCall = ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        let diffResult: ToolResult
        if let project = selectedProject, project.isRemote {
            diffResult = Self.executeRemoteGitToolCall(
                diffCall,
                connection: project.connection,
                executor: sshRemoteShellExecutor
            )
        } else {
            diffResult = router.execute(diffCall)
        }
        appendToolRun(call: diffCall, result: diffResult)
        return diffResult
    }

    private func toolArgumentsJSON(_ values: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private func handleSlashCommand(_ command: SlashCommand, originalPrompt: String, workspaceRoot: URL) {
        switch command {
        case .help:
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: SlashCommandCatalog.helpText(),
                title: "Slash commands"
            )
        case .status:
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: statusText(),
                title: "Status"
            )
        case .newChat:
            _ = newChat()
        case .mode(let mode):
            setMode(mode)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Mode set to \(Self.modeLabel(mode)).",
                title: "Set mode"
            )
        case .model(let model):
            setModel(model)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Model set to \(model).",
                title: "Set model"
            )
        case .renameThread(let title):
            if let id = root.selectedThreadID, renameThread(id, to: title) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Renamed chat to \(title.trimmingCharacters(in: .whitespacesAndNewlines)).",
                    title: "Rename chat"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not rename this chat. Try /rename New chat title.",
                    title: "Rename chat"
                )
            }
        case .renameProject(let name):
            if let id = root.selectedProjectID, renameProject(id, to: name) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Renamed project to \(name.trimmingCharacters(in: .whitespacesAndNewlines)).",
                    title: "Rename project"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not rename this project. Try /project rename New project name.",
                    title: "Rename project"
                )
            }
        case .sshProject(let address):
            if let projectID = addSSHProject(address),
               let project = root.projects.first(where: { $0.id == projectID }) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Added SSH Remote \(project.name) at \(project.displayPath). Shell, file read/write, apply patch, git status/diff/stage/restore/commit/push/PR checkout/reviewers/labels/merge/worktree, and project context refresh run through SSH.",
                    title: "Add SSH Remote"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: lastError ?? "Use SSH format user@host:/path or ssh://user@host/path.",
                    title: "Add SSH Remote"
                )
            }
        case .remember(let content):
            runRememberSlashCommand(content, originalPrompt: originalPrompt)
        case .threadFollowUp(let scheduleText):
            if let automation = createThreadFollowUpAutomation(matching: scheduleText) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Scheduled a thread follow-up for \(automation.scheduleDescription).",
                    title: "Schedule follow-up"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: lastError ?? "Could not schedule this follow-up.",
                    title: "Schedule follow-up"
                )
            }
        case .workspaceSchedule(let scheduleText):
            if let automation = createWorkspaceScheduleAutomation(matching: scheduleText) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Scheduled a workspace check for \(automation.scheduleDescription).",
                    title: "Schedule workspace check"
                )
            } else {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: lastError ?? "Could not schedule this workspace check.",
                    title: "Schedule workspace check"
                )
            }
        case .workspaceCommand(let commandID):
            if !runWorkspaceCommand(commandID, workspaceRoot: workspaceRoot) {
                appendLocalCommandTranscript(
                    userText: originalPrompt,
                    assistantText: "Could not run /\(originalPrompt.dropFirst()). Try /help.",
                    title: "Slash command"
                )
            }
        case .toolCall(let call):
            _ = runToolCall(call, workspaceRoot: workspaceRoot)
        case .environmentAction(let query):
            runEnvironmentSlashCommand(query, originalPrompt: originalPrompt, workspaceRoot: workspaceRoot)
        case .invalid(let message):
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: message,
                title: "Slash command"
            )
        case .unknown(let name):
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Unknown slash command '/\(name)'. Try /help.",
                title: "Slash command"
            )
        }
        composer.isSending = false
        refreshTopBar(agentStatus: "Idle")
    }

    private func runRememberSlashCommand(_ content: String, originalPrompt: String) {
        guard let globalMemoryDirectory else {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: MemoryNoteWriteError.unavailable.localizedDescription,
                title: "Memory not saved"
            )
            return
        }

        do {
            let saved = try Self.saveGlobalMemory(content: content, to: globalMemoryDirectory)
            let note = saved.note
            root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
            let projectID = selectedThread?.projectID ?? root.selectedProjectID
            let refreshedMemories = memoryNotes(for: projectID)
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "Saved memory: \(note.title). It will be included as background context in future turns.",
                title: "Memory: \(note.title)"
            )
            mutateSelectedThread { thread in
                thread.memories = refreshedMemories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Saved memory: \(note.title)",
                    payloadJSON: note.relativePath
                ))
            }
        } catch let error as MemoryNoteWriteError {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: error.localizedDescription,
                title: "Memory not saved"
            )
        } catch {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: MemoryNoteWriteError.writeFailed.localizedDescription,
                title: "Memory not saved"
            )
        }
    }

    private func runEnvironmentSlashCommand(_ query: String?, originalPrompt: String, workspaceRoot: URL) {
        refreshProjectMetadata(root.selectedProjectID)
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let actions = selectedProject?.localActions ?? []
            let message: String
            if actions.isEmpty {
                message = "No local environment actions found. Add scripts under `.quillcode/actions` or `.quillcode/local-env`."
            } else {
                let rows = actions
                    .map { action in
                        let detail = action.detail.map { " — \($0)" } ?? ""
                        let cwd = action.workingDirectory.map { " — cwd: \($0)" } ?? ""
                        let timeout = action.timeoutSeconds.map { " — timeout: \($0)s" } ?? ""
                        return "- `/env \(action.title)` — \(action.relativePath)\(cwd)\(timeout)\(detail)"
                    }
                    .joined(separator: "\n")
                message = "Local environment actions:\n\(rows)"
            }
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: message,
                title: "Local environment actions"
            )
            return
        }

        guard let action = localAction(matching: query) else {
            appendLocalCommandTranscript(
                userText: originalPrompt,
                assistantText: "No local environment action matches `\(query)`. Run `/env` to see available actions.",
                title: "Local environment actions"
            )
            return
        }
        _ = runLocalEnvironmentAction(action.id, workspaceRoot: workspaceRoot)
    }

    private func appendLocalCommandTranscript(userText: String, assistantText: String, title: String) {
        if selectedThread == nil {
            _ = newChat()
        }
        mutateSelectedThread { thread in
            if thread.messages.isEmpty && thread.title == "New chat" {
                thread.title = title
            }
            thread.messages.append(ChatMessage(role: .user, content: userText))
            thread.messages.append(ChatMessage(role: .assistant, content: assistantText))
        }
        if let thread = selectedThread {
            try? threadStore?.save(thread)
        }
    }

    private func finishCancelledSend(userPrompt: String, threadID: UUID) {
        composer.isSending = false
        lastError = nil
        mutateThread(threadID) { thread in
            if thread.messages.isEmpty && thread.title == "New chat" {
                thread.title = Self.title(fromUserPrompt: userPrompt)
            }
            if !thread.messages.contains(where: { $0.role == .user && $0.content == userPrompt }) {
                thread.messages.append(ChatMessage(role: .user, content: userPrompt))
            }
            let summary = "Stopped by user"
            if let lastEvent = thread.events.last,
               lastEvent.kind == .toolQueued || lastEvent.kind == .toolRunning {
                thread.events.append(.init(
                    kind: .toolFailed,
                    summary: summary,
                    payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#
                ))
            }
            if thread.events.last?.kind != .notice || thread.events.last?.summary != summary {
                thread.events.append(.init(kind: .notice, summary: summary))
            }
        }
        refreshTopBar(agentStatus: "Stopped")
    }

    private static func title(fromUserPrompt userPrompt: String) -> String {
        let words = userPrompt.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "New chat" : words
    }

    private static func forkSeedMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        let visibleMessages = visibleConversationMessages(from: messages)
        guard let lastUserIndex = visibleMessages.lastIndex(where: { $0.role == .user }) else {
            return Array(visibleMessages.suffix(4))
        }
        return Array(visibleMessages[lastUserIndex...].prefix(4))
    }

    private static func compactSeedMessages(from thread: ChatThread) -> [ChatMessage] {
        let visibleMessages = visibleConversationMessages(from: thread.messages)
        let recentMessages = forkSeedMessages(from: visibleMessages)
        let recentIDs = Set(recentMessages.map(\.id))
        let olderMessages = visibleMessages.filter { !recentIDs.contains($0.id) }
        return [compactSummaryMessage(
            sourceTitle: thread.title,
            olderMessages: olderMessages,
            recentMessages: recentMessages
        )] + recentMessages
    }

    private static func visibleConversationMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .tool }
    }

    private static func compactSummaryMessage(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) -> ChatMessage {
        let olderCount = olderMessages.count
        let recentCount = recentMessages.count
        var lines = [
            "Context compacted from \"\(sourceTitle)\".",
            "Kept \(recentCount) latest message\(recentCount == 1 ? "" : "s") and summarized \(olderCount) earlier message\(olderCount == 1 ? "" : "s")."
        ]
        if olderMessages.isEmpty {
            lines.append("No earlier turns were dropped.")
        } else {
            lines.append("Earlier context:")
            for message in olderMessages.suffix(6) {
                lines.append("- \(roleLabel(message.role)): \(singleLineExcerpt(message.content, limit: 180))")
            }
        }
        lines.append("Continue from the preserved latest turn below.")
        return ChatMessage(role: .assistant, content: lines.joined(separator: "\n"))
    }

    private static func roleLabel(_ role: ChatRole) -> String {
        switch role {
        case .system:
            return "System"
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .tool:
            return "Tool"
        }
    }

    private static func singleLineExcerpt(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func statusText() -> String {
        let project = selectedProject?.name ?? root.topBar.projectName ?? "No project"
        let thread = selectedThread?.title ?? "No chat"
        let instructionLabel = Self.instructionStatusLabel(for: selectedProject?.instructions ?? selectedThread?.instructions ?? [])
        let memoryLabel = Self.memoryStatusLabel(for: selectedThread?.memories ?? memoryNotes(for: root.selectedProjectID))
        return """
        Project: \(project)
        Thread: \(thread)
        Instructions: \(instructionLabel)
        Memories: \(memoryLabel)
        Mode: \(Self.modeLabel(root.topBar.mode))
        Model: \(root.topBar.model)
        Agent: \(root.topBar.agentStatus)
        """
    }

    private func mutateSelectedThread(_ update: (inout ChatThread) -> Void) {
        guard let selectedThreadID = root.selectedThreadID,
              let index = mutateThread(selectedThreadID, update)
        else {
            return
        }
        root.selectedThreadID = root.threads[index].id
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    func selectedSidebarThreadIDs() -> [UUID] {
        let validIDs = Set(root.threads.map(\.id))
        sidebarSelection.selectedThreadIDs = sidebarSelection.selectedThreadIDs.intersection(validIDs)
        if sidebarSelection.selectedThreadIDs.isEmpty {
            return []
        }
        return root.allSidebarItems
            .map(\.id)
            .filter { sidebarSelection.selectedThreadIDs.contains($0) }
    }

    private func updateThreads(_ ids: [UUID], _ update: (inout ChatThread) -> Void) {
        let targetIDs = Set(ids)
        guard !targetIDs.isEmpty else { return }
        for index in root.threads.indices where targetIDs.contains(root.threads[index].id) {
            update(&root.threads[index])
            root.threads[index].updatedAt = Date()
            try? threadStore?.save(root.threads[index])
        }
        saveProjects()
    }

    private func selectBestThread(afterRemoving ids: [UUID], preferredProjectID: UUID?) {
        let removedIDs = Set(ids)
        let preferred = root.threads
            .filter { !$0.isArchived && !removedIDs.contains($0.id) && $0.projectID == preferredProjectID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
        let fallback = preferred ?? root.threads
            .filter { !$0.isArchived && !removedIDs.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first

        root.selectedThreadID = fallback?.id
        root.selectedProjectID = knownProjectID(fallback?.projectID ?? preferredProjectID)
        syncTerminalSessionToSelectedProject()
    }

    @discardableResult
    private func mutateThread(_ id: UUID, _ update: (inout ChatThread) -> Void) -> Int? {
        guard let index = root.threads.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        update(&root.threads[index])
        root.threads[index].updatedAt = Date()
        try? threadStore?.save(root.threads[index])
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return index
    }

    private func replaceThread(_ thread: ChatThread) {
        if let index = root.threads.firstIndex(where: { $0.id == thread.id }) {
            root.threads[index] = thread
        } else {
            root.threads.insert(thread, at: 0)
        }
        root.selectedThreadID = thread.id
        root.selectedProjectID = knownProjectID(thread.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
    }

    public func setComputerUseStatus(_ status: ComputerUseStatus) {
        root.topBar.computerUseStatus = status
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    public func setComputerUseBackend(_ backend: any ComputerUseBackend) {
        computerUseBackend = backend
        setComputerUseStatus(backend.status)
    }

    public func refreshSelectedProjectInstructions() {
        refreshSelectedProjectContext()
    }

    public func refreshSelectedProjectContext() {
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshGlobalMemories()
        refreshProjectMetadata(projectID)
        let refreshedInstructions = instructions(for: projectID)
        let refreshedMemories = memoryNotes(for: projectID)
        mutateSelectedThread { thread in
            thread.instructions = refreshedInstructions
            thread.memories = refreshedMemories
        }
        saveProjects()
    }

    private func refreshTopBar(agentStatus: String? = nil) {
        let thread = selectedThread
        let projectID = thread?.projectID ?? root.selectedProjectID
        let project = projectID.flatMap { id in root.projects.first { $0.id == id } }
        root.topBar = TopBarState(
            projectName: project?.name,
            threadTitle: thread?.title,
            model: thread?.model ?? root.config.defaultModel,
            mode: thread?.mode ?? root.config.mode,
            agentStatus: agentStatus ?? root.topBar.agentStatus,
            computerUseStatus: root.topBar.computerUseStatus
        )
    }

    private func touchProject(_ id: UUID?) {
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        root.projects[index].lastOpenedAt = Date()
    }

    private func refreshProjectInstructions(_ id: UUID?) {
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        guard !root.projects[index].isRemote else { return }
        let rootURL = URL(fileURLWithPath: root.projects[index].path)
        root.projects[index].instructions = ProjectInstructionLoader.load(from: rootURL)
        root.projects[index].memories = MemoryNoteLoader.loadProject(from: rootURL)
    }

    private func refreshProjectMetadata(_ id: UUID?) {
        refreshGlobalMemories()
        guard let id, let index = root.projects.firstIndex(where: { $0.id == id }) else { return }
        guard !root.projects[index].isRemote else { return }
        let rootURL = URL(fileURLWithPath: root.projects[index].path)
        root.projects[index].instructions = ProjectInstructionLoader.load(from: rootURL)
        root.projects[index].localActions = LocalEnvironmentActionLoader.load(from: rootURL)
        root.projects[index].extensionManifests = ProjectExtensionManifestLoader.load(from: rootURL)
        root.projects[index].memories = MemoryNoteLoader.loadProject(from: rootURL)
    }

    private func refreshRemoteProjectContext(_ id: UUID) -> Bool {
        refreshGlobalMemories()
        guard let index = root.projects.firstIndex(where: { $0.id == id }),
              root.projects[index].isRemote
        else {
            return false
        }

        do {
            let context = try SSHRemoteProjectContextLoader.load(
                connection: root.projects[index].connection,
                executor: sshRemoteShellExecutor
            )
            root.projects[index].instructions = context.instructions
            root.projects[index].memories = context.memories
            root.projects[index].localActions = []
            root.projects[index].extensionManifests = []
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func refreshGlobalMemories() {
        guard let globalMemoryDirectory else { return }
        root.globalMemories = MemoryNoteLoader.loadGlobal(from: globalMemoryDirectory)
    }

    private func syncThreadContext(into thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        thread.instructions = instructions(for: projectID)
        thread.memories = memoryNotes(for: projectID)
    }

    private func refreshThreadMemoryContext(_ thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        thread.memories = memoryNotes(for: projectID)
    }

    private func instructions(for projectID: UUID?) -> [ProjectInstruction] {
        guard let projectID,
              let project = root.projects.first(where: { $0.id == projectID })
        else {
            return []
        }
        return project.instructions
    }

    private func memoryNotes(for projectID: UUID?) -> [MemoryNote] {
        let projectMemories: [MemoryNote]
        if let projectID,
           let project = root.projects.first(where: { $0.id == projectID }) {
            projectMemories = project.memories
        } else {
            projectMemories = []
        }
        return root.globalMemories + projectMemories
    }

    private func localAction(withID id: String) -> LocalEnvironmentAction? {
        selectedProject?.localActions.first { $0.id == id }
    }

    private func localAction(matching query: String) -> LocalEnvironmentAction? {
        let normalizedQuery = Self.normalizedActionName(query)
        return selectedProject?.localActions.first { action in
            action.id.caseInsensitiveCompare(query) == .orderedSame
                || action.title.caseInsensitiveCompare(query) == .orderedSame
                || action.relativePath.caseInsensitiveCompare(query) == .orderedSame
                || Self.normalizedActionName(action.title) == normalizedQuery
                || Self.normalizedActionName(action.relativePath) == normalizedQuery
        }
    }

    private static func normalizedActionName(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func instructionStatusLabel(for instructions: [ProjectInstruction]) -> String {
        guard !instructions.isEmpty else { return "No project instructions" }
        let truncated = instructions.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(instructions.count) instruction file\(instructions.count == 1 ? "" : "s") loaded\(truncated)"
    }

    static func memoryStatusLabel(for memories: [MemoryNote]) -> String {
        guard !memories.isEmpty else { return "No memories" }
        let truncated = memories.contains { $0.wasTruncated } ? ", truncated" : ""
        return "\(memories.count) memor\(memories.count == 1 ? "y" : "ies")\(truncated)"
    }

    private func knownProjectID(_ id: UUID?) -> UUID? {
        guard let id, root.projects.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func saveProjects() {
        try? projectStore?.save(root.projects)
    }

    private func saveAutomations() {
        try? automationStore?.save(automations.items)
    }

    private static func defaultProjectName(for url: URL) -> String {
        let lastPathComponent = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? url.path : lastPathComponent
    }

    private static func defaultSSHProjectName(for connection: ProjectConnection) -> String {
        let pathName = URL(fileURLWithPath: connection.path).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let host = connection.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host, !host.isEmpty, !pathName.isEmpty {
            return "\(host) · \(pathName)"
        }
        if let host, !host.isEmpty {
            return host
        }
        return connection.displayLabel
    }

    private static func normalizedBrowserURL(_ rawValue: String, workspaceRoot: URL?) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return url
        }

        if trimmed.hasPrefix("localhost")
            || trimmed.hasPrefix("127.0.0.1")
            || trimmed.hasPrefix("[::1]") {
            return URL(string: "http://\(trimmed)")
        }

        if let workspaceRoot,
           let fileURL = projectFileBrowserURL(trimmed, workspaceRoot: workspaceRoot) {
            return fileURL
        }

        if trimmed.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL.standardizedFileURL
            }
        }

        if trimmed.contains(".") {
            return URL(string: "https://\(trimmed)")
        }

        return nil
    }

    private static func canFetchBrowserSnapshot(for url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func browserSnapshotFetchMessage(for error: any Error) -> String {
        if let failure = error as? BrowserPageFetchFailure {
            return failure.description
        }
        return error.localizedDescription
    }

    private static func projectFileBrowserURL(_ relativePath: String, workspaceRoot: URL) -> URL? {
        guard !relativePath.contains("..") else { return nil }
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard (fileURL.path == root.path || fileURL.path.hasPrefix(root.path + "/")),
              FileManager.default.fileExists(atPath: fileURL.path)
        else {
            return nil
        }
        return fileURL
    }

    private static func updateCard(
        _ cards: inout [ToolCardState],
        at index: Int,
        status: ToolCardStatus,
        subtitle: String,
        outputJSON: String? = nil
    ) {
        guard cards.indices.contains(index) else { return }
        cards[index].status = status
        cards[index].subtitle = subtitle
        cards[index].density = ToolCardState.defaultDensity(status: status, isExpanded: cards[index].isExpanded)
        cards[index].isExpanded = cards[index].density == .expanded
        if let outputJSON {
            cards[index].outputJSON = outputJSON
            cards[index].artifacts = artifacts(from: outputJSON)
        }
    }

    private static func artifacts(from outputJSON: String) -> [ToolArtifactState] {
        guard let result = try? JSONHelpers.decode(ToolResult.self, from: outputJSON) else {
            return []
        }
        return result.artifacts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { value in
                ToolArtifactState(value: value, textPreview: ToolArtifactPreviewBuilder.textPreview(for: value))
            }
    }

    private nonisolated static func decode<T: Decodable>(_ type: T.Type, _ payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}

private extension WorkspaceReviewActionSurface {
    var toolCall: ToolCall {
        switch kind {
        case .stage:
            return ToolCall(
                name: ToolDefinition.gitStage.name,
                argumentsJSON: ToolArguments.json(["path": path])
            )
        case .restore:
            return ToolCall(
                name: ToolDefinition.gitRestore.name,
                argumentsJSON: ToolArguments.json(["path": path])
            )
        case .stageHunk:
            return ToolCall(
                name: ToolDefinition.gitStageHunk.name,
                argumentsJSON: ToolArguments.json([
                    "path": path,
                    "patch": patch ?? ""
                ])
            )
        case .restoreHunk:
            return ToolCall(
                name: ToolDefinition.gitRestoreHunk.name,
                argumentsJSON: ToolArguments.json([
                    "path": path,
                    "patch": patch ?? ""
                ])
            )
        }
    }
}
