import QuillCodeCore

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
