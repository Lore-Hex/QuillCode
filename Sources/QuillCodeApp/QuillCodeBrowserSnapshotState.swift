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
        self.sourceLabel = WorkspaceBrowserRetentionPolicy.bounded(
            sourceLabel,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumSnapshotLabelCharacters
        )
        self.inspectionDepth = inspectionDepth
        self.summary = WorkspaceBrowserRetentionPolicy.bounded(
            summary,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumSnapshotSummaryCharacters
        )
        self.details = WorkspaceBrowserRetentionPolicy.boundedLines(
            details,
            maximumCount: WorkspaceBrowserRetentionPolicy.maximumSnapshotDetailCount,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumSnapshotDetailCharacters
        )
        self.outline = WorkspaceBrowserRetentionPolicy.boundedLines(
            outline,
            maximumCount: WorkspaceBrowserRetentionPolicy.maximumSnapshotOutlineCount,
            maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumSnapshotOutlineCharacters
        )
        self.textSnippet = textSnippet.map {
            WorkspaceBrowserRetentionPolicy.bounded(
                $0,
                maximumCharacters: WorkspaceBrowserRetentionPolicy.maximumSnapshotTextCharacters
            )
        }
    }
}
