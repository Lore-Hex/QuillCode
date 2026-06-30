import Foundation

public struct WorkspaceReviewSurface: Codable, Sendable, Hashable {
    public var title: String
    public var subtitle: String
    public var files: [WorkspaceReviewFileSurface]
    public var pullRequestThreads: [WorkspacePullRequestReviewThreadSurface]
    public var pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface?
    public var totalInsertions: Int
    public var totalDeletions: Int
    public var totalHunks: Int

    public var isVisible: Bool {
        !files.isEmpty || !pullRequestThreads.isEmpty || pullRequestReviewDraft != nil
    }

    public var badgeLabel: String {
        let parts = [
            files.isEmpty ? nil : "\(totalHunks) hunk\(totalHunks == 1 ? "" : "s")",
            pullRequestThreads.isEmpty ? nil : "\(pullRequestThreads.count) thread\(pullRequestThreads.count == 1 ? "" : "s")",
            pullRequestReviewDraft == nil ? nil : "review draft"
        ].compactMap(\.self)
        return parts.isEmpty ? "Review" : parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case subtitle
        case files
        case pullRequestThreads
        case pullRequestReviewDraft
        case totalInsertions
        case totalDeletions
        case totalHunks
    }

    public init(
        title: String = "Review changes",
        subtitle: String = "Latest git diff",
        files: [WorkspaceReviewFileSurface] = [],
        pullRequestThreads: [WorkspacePullRequestReviewThreadSurface] = [],
        pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface? = nil
    ) {
        self.title = files.isEmpty
            && pullRequestThreads.isEmpty
            && pullRequestReviewDraft != nil
            && title == "Review changes"
            ? "Review pull request"
            : title
        self.files = files
        self.pullRequestThreads = pullRequestThreads
        self.pullRequestReviewDraft = pullRequestReviewDraft
        self.totalInsertions = files.reduce(0) { $0 + $1.insertions }
        self.totalDeletions = files.reduce(0) { $0 + $1.deletions }
        self.totalHunks = files.reduce(0) { $0 + $1.hunks }
        if !files.isEmpty {
            self.subtitle = "\(files.count) file\(files.count == 1 ? "" : "s") changed, +\(totalInsertions) -\(totalDeletions)"
        } else if !pullRequestThreads.isEmpty {
            let unresolvedCount = pullRequestThreads.filter { !$0.isResolved }.count
            let resolvedCount = pullRequestThreads.count - unresolvedCount
            self.subtitle = "\(pullRequestThreads.count) review thread\(pullRequestThreads.count == 1 ? "" : "s"), \(unresolvedCount) unresolved, \(resolvedCount) resolved"
        } else if let pullRequestReviewDraft {
            self.subtitle = pullRequestReviewDraft.subtitle
        } else {
            self.subtitle = subtitle
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.files = try container.decode([WorkspaceReviewFileSurface].self, forKey: .files)
        self.pullRequestThreads = try container.decodeIfPresent(
            [WorkspacePullRequestReviewThreadSurface].self,
            forKey: .pullRequestThreads
        ) ?? []
        self.pullRequestReviewDraft = try container.decodeIfPresent(
            WorkspacePullRequestReviewDraftSurface.self,
            forKey: .pullRequestReviewDraft
        )
        self.totalInsertions = try container.decode(Int.self, forKey: .totalInsertions)
        self.totalDeletions = try container.decode(Int.self, forKey: .totalDeletions)
        self.totalHunks = try container.decode(Int.self, forKey: .totalHunks)
    }
}

public enum WorkspacePullRequestReviewActionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case approve
    case comment
    case requestChanges = "request_changes"

    public var title: String {
        switch self {
        case .approve:
            return "Approve"
        case .comment:
            return "Comment"
        case .requestChanges:
            return "Request changes"
        }
    }

    public var requiresBody: Bool {
        switch self {
        case .approve:
            return false
        case .comment, .requestChanges:
            return true
        }
    }

    public var bodyPlaceholder: String {
        switch self {
        case .approve:
            return "Optional approval note"
        case .comment:
            return "Review comment"
        case .requestChanges:
            return "Explain the changes needed"
        }
    }
}

public struct WorkspacePullRequestReviewDraftSurface: Codable, Sendable, Hashable {
    public var action: WorkspacePullRequestReviewActionKind
    public var selector: String
    public var body: String
    public var includeInlineComments: Bool
    public var inlineComments: [WorkspacePullRequestReviewDraftCommentSurface]

    public var subtitle: String {
        if inlineCommentCount > 0 {
            let selectedCount = selectedInlineCommentCount
            if selectedCount == 0 {
                return "Submit \(action.title.lowercased()) review without inline notes"
            }
            if selectedCount == inlineCommentCount {
                return "Submit \(action.title.lowercased()) review with \(selectedCount) inline note\(selectedCount == 1 ? "" : "s")"
            }
            return "Submit \(action.title.lowercased()) review with \(selectedCount) of \(inlineCommentCount) inline notes"
        }
        return "Submit \(action.title.lowercased()) review through GitHub CLI"
    }

    public var normalizedSelector: String? {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var normalizedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canSubmit: Bool {
        (!action.requiresBody || !normalizedBody.isEmpty) && invalidSelectedInlineComments.isEmpty
    }

    public var inlineCommentCount: Int {
        inlineComments.count
    }

    public var selectedInlineCommentCount: Int {
        selectedInlineComments.count
    }

    public var selectedInlineComments: [WorkspacePullRequestReviewDraftCommentSurface] {
        includeInlineComments ? inlineComments.filter(\.isIncluded) : []
    }

    public var invalidSelectedInlineComments: [WorkspacePullRequestReviewDraftCommentSurface] {
        selectedInlineComments.filter { $0.normalizedBody.isEmpty }
    }

    public var submitSummary: WorkspacePullRequestReviewDraftSubmitSummarySurface {
        WorkspacePullRequestReviewDraftSubmitSummarySurface(draft: self)
    }

    public mutating func setInlineComment(id: UUID, isIncluded: Bool) {
        updateInlineComment(id: id, isIncluded: isIncluded)
    }

    public mutating func updateInlineComment(id: UUID, isIncluded: Bool? = nil, body: String? = nil) {
        guard let index = inlineComments.firstIndex(where: { $0.id == id }) else { return }
        if let isIncluded {
            inlineComments[index].isIncluded = isIncluded
        }
        if let body {
            inlineComments[index].body = body
        }
    }

    public mutating func moveInlineComment(id: UUID, offset: Int) {
        guard offset != 0, let sourceIndex = inlineComments.firstIndex(where: { $0.id == id }) else {
            return
        }
        let destinationIndex = max(0, min(inlineComments.count - 1, sourceIndex + offset))
        guard destinationIndex != sourceIndex else { return }
        let comment = inlineComments.remove(at: sourceIndex)
        inlineComments.insert(comment, at: destinationIndex)
    }

    public init(
        action: WorkspacePullRequestReviewActionKind = .approve,
        selector: String = "",
        body: String = "",
        includeInlineComments: Bool = true,
        inlineComments: [WorkspacePullRequestReviewDraftCommentSurface] = []
    ) {
        self.action = action
        self.selector = selector
        self.body = body
        self.includeInlineComments = includeInlineComments
        self.inlineComments = inlineComments
    }
}

public struct WorkspacePullRequestReviewDraftSubmitSummarySurface: Sendable, Hashable {
    public enum Status: String, Sendable, Hashable {
        case ready
        case blocked
    }

    public var status: Status
    public var title: String
    public var detail: String
    public var items: [String]

    public init(draft: WorkspacePullRequestReviewDraftSurface) {
        let target = draft.normalizedSelector.map { "PR \($0)" } ?? "current pull request"
        let selectedInlineCount = draft.selectedInlineCommentCount
        let skippedInlineCount = max(0, draft.inlineCommentCount - selectedInlineCount)
        let invalidInlineCount = draft.invalidSelectedInlineComments.count
        let bodyItem = Self.bodyItem(for: draft)
        let inlineItem = Self.inlineItem(
            total: draft.inlineCommentCount,
            selected: selectedInlineCount,
            skipped: skippedInlineCount,
            invalid: invalidInlineCount,
            includeInlineComments: draft.includeInlineComments
        )
        let isReady = draft.canSubmit

        self.status = isReady ? .ready : .blocked
        self.title = isReady ? "Ready to submit" : "Needs attention"
        self.detail = isReady
            ? "\(draft.action.title) review for \(target)"
            : "Resolve required fields before submitting"
        self.items = [
            "Action: \(draft.action.title)",
            "Target: \(target)",
            bodyItem,
            inlineItem
        ] + (invalidInlineCount > 0 ? [
            "\(invalidInlineCount) selected inline note\(invalidInlineCount == 1 ? "" : "s") \(invalidInlineCount == 1 ? "needs" : "need") text"
        ] : [])
    }

    private static func bodyItem(for draft: WorkspacePullRequestReviewDraftSurface) -> String {
        if draft.normalizedBody.isEmpty {
            return draft.action.requiresBody ? "Body: required" : "Body: optional"
        }
        return "Body: ready"
    }

    private static func inlineItem(
        total: Int,
        selected: Int,
        skipped: Int,
        invalid: Int,
        includeInlineComments: Bool
    ) -> String {
        guard total > 0 else {
            return "Inline notes: none"
        }
        if !includeInlineComments {
            return "Inline notes: skipped \(total)"
        }
        let selectedLabel = "\(selected) selected"
        let skippedLabel = skipped > 0 ? ", \(skipped) skipped" : ""
        let invalidLabel = invalid > 0 ? ", \(invalid) missing text" : ""
        return "Inline notes: \(selectedLabel)\(skippedLabel)\(invalidLabel)"
    }
}

public struct WorkspacePullRequestReviewDraftCommentSurface: Codable, Sendable, Hashable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case line
        case startLine
        case side
        case body
        case isIncluded
    }

    public var id: UUID
    public var path: String
    public var line: Int
    public var startLine: Int?
    public var side: String
    public var body: String
    public var isIncluded: Bool

    public var locationLabel: String {
        if let startLine, startLine != line {
            return "\(path):\(startLine)-\(line)"
        }
        return "\(path):\(line)"
    }

    public var normalizedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public init(
        id: UUID = UUID(),
        path: String,
        line: Int,
        startLine: Int? = nil,
        side: String = "RIGHT",
        body: String,
        isIncluded: Bool = true
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.startLine = startLine
        self.side = side
        self.body = body
        self.isIncluded = isIncluded
    }

    public init?(comment: WorkspaceReviewCommentSurface) {
        guard let lineNumber = comment.lineNumber else {
            return nil
        }
        let endLineNumber = comment.endLineNumber ?? lineNumber
        let body = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return nil
        }
        self.init(
            id: comment.id,
            path: comment.path,
            line: max(lineNumber, endLineNumber),
            startLine: lineNumber == endLineNumber ? nil : min(lineNumber, endLineNumber),
            side: Self.side(for: comment.lineKind),
            body: body
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.path = try container.decode(String.self, forKey: .path)
        self.line = try container.decode(Int.self, forKey: .line)
        self.startLine = try container.decodeIfPresent(Int.self, forKey: .startLine)
        self.side = try container.decode(String.self, forKey: .side)
        self.body = try container.decode(String.self, forKey: .body)
        self.isIncluded = try container.decodeIfPresent(Bool.self, forKey: .isIncluded) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(line, forKey: .line)
        try container.encodeIfPresent(startLine, forKey: .startLine)
        try container.encode(side, forKey: .side)
        try container.encode(body, forKey: .body)
        try container.encode(isIncluded, forKey: .isIncluded)
    }

    public static func collect(from review: WorkspaceReviewSurface) -> [WorkspacePullRequestReviewDraftCommentSurface] {
        review.files
            .flatMap { file in
                file.hunkItems.flatMap(\.lines)
            }
            .flatMap(\.comments)
            .compactMap(Self.init(comment:))
    }

    private static func side(for lineKind: WorkspaceReviewLineKind?) -> String {
        lineKind == .deletion ? "LEFT" : "RIGHT"
    }
}

public struct WorkspaceReviewCommentSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var path: String
    public var lineNumber: Int?
    public var endLineNumber: Int?
    public var lineKind: WorkspaceReviewLineKind?
    public var text: String
    public var createdAt: Date

    public var lineRangeLabel: String? {
        guard let lineNumber else { return nil }
        let endLineNumber = endLineNumber ?? lineNumber
        return lineNumber == endLineNumber
            ? "Line \(lineNumber)"
            : "Lines \(lineNumber)-\(endLineNumber)"
    }

    public init(comment: WorkspaceReviewCommentState) {
        self.id = comment.id
        self.path = comment.path
        self.lineNumber = comment.lineNumber
        self.endLineNumber = comment.endLineNumber
        self.lineKind = comment.lineKind
        self.text = comment.text
        self.createdAt = comment.createdAt
    }
}

public struct WorkspaceReviewFileSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var insertions: Int
    public var deletions: Int
    public var hunks: Int
    public var isBinary: Bool
    public var hunkItems: [WorkspaceReviewHunkSurface]
    public var comments: [WorkspaceReviewCommentSurface]

    public var changeLabel: String {
        var parts = ["+\(insertions)", "-\(deletions)"]
        if hunks > 0 {
            parts.append("\(hunks) hunk\(hunks == 1 ? "" : "s")")
        }
        if isBinary {
            parts.append("binary")
        }
        return parts.joined(separator: " · ")
    }

    public var actions: [WorkspaceReviewActionSurface] {
        [
            WorkspaceReviewActionSurface(kind: .open, path: path),
            WorkspaceReviewActionSurface(kind: .stage, path: path),
            WorkspaceReviewActionSurface(kind: .restore, path: path)
        ]
    }

    public init(
        path: String,
        insertions: Int,
        deletions: Int,
        hunks: Int,
        isBinary: Bool = false,
        hunkItems: [WorkspaceReviewHunkSurface] = [],
        comments: [WorkspaceReviewCommentSurface] = []
    ) {
        self.path = path
        self.insertions = insertions
        self.deletions = deletions
        self.hunks = hunks
        self.isBinary = isBinary
        self.hunkItems = hunkItems
        self.comments = comments
    }
}

public enum WorkspaceReviewLineKind: String, Codable, Sendable, Hashable {
    case context
    case insertion
    case deletion

    public var marker: String {
        switch self {
        case .context:
            return " "
        case .insertion:
            return "+"
        case .deletion:
            return "-"
        }
    }
}

public struct WorkspaceReviewLineSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var hunkID: String
    public var oldLineNumber: Int?
    public var newLineNumber: Int?
    public var kind: WorkspaceReviewLineKind
    public var content: String
    public var comments: [WorkspaceReviewCommentSurface]

    public var displayLineNumber: Int? {
        newLineNumber ?? oldLineNumber
    }

    public var lineLabel: String {
        displayLineNumber.map(String.init) ?? ""
    }

    public init(
        id: String,
        path: String,
        hunkID: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        kind: WorkspaceReviewLineKind,
        content: String,
        comments: [WorkspaceReviewCommentSurface] = []
    ) {
        self.id = id
        self.path = path
        self.hunkID = hunkID
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.kind = kind
        self.content = content
        self.comments = comments
    }
}

public struct WorkspaceReviewHunkSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var header: String
    public var insertions: Int
    public var deletions: Int
    public var patch: String
    public var lines: [WorkspaceReviewLineSurface]

    public var changeLabel: String {
        "+\(insertions) · -\(deletions)"
    }

    public var actions: [WorkspaceReviewActionSurface] {
        [
            WorkspaceReviewActionSurface(kind: .stageHunk, path: path, patch: patch, targetID: id),
            WorkspaceReviewActionSurface(kind: .restoreHunk, path: path, patch: patch, targetID: id)
        ]
    }

    public init(
        id: String,
        path: String,
        header: String,
        insertions: Int,
        deletions: Int,
        patch: String,
        lines: [WorkspaceReviewLineSurface] = []
    ) {
        self.id = id
        self.path = path
        self.header = header
        self.insertions = insertions
        self.deletions = deletions
        self.patch = patch
        self.lines = lines
    }
}

public enum WorkspaceReviewActionKind: String, Codable, Sendable, Hashable {
    case open
    case stage
    case restore
    case stageHunk = "stage_hunk"
    case restoreHunk = "restore_hunk"

    public var title: String {
        switch self {
        case .open:
            return "Open"
        case .stage:
            return "Stage"
        case .restore:
            return "Restore"
        case .stageHunk:
            return "Stage hunk"
        case .restoreHunk:
            return "Restore hunk"
        }
    }

    public var systemImage: String {
        switch self {
        case .open:
            return "doc.text"
        case .stage:
            return "plus.rectangle.on.folder"
        case .restore:
            return "arrow.uturn.backward"
        case .stageHunk:
            return "plus.square.on.square"
        case .restoreHunk:
            return "arrow.uturn.left.square"
        }
    }

    /// Whether the action changes the working tree/index and therefore needs a diff
    /// refresh. `.open` only reads a file, so it pairs no refresh and never clears
    /// the review pane.
    public var isMutating: Bool {
        switch self {
        case .open:
            return false
        case .stage, .restore, .stageHunk, .restoreHunk:
            return true
        }
    }
}

public struct WorkspaceReviewActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: WorkspaceReviewActionKind
    public var path: String
    public var patch: String?
    public var targetID: String?

    public var id: String {
        "\(kind.rawValue):\(path):\(targetID ?? "file")"
    }

    public init(
        kind: WorkspaceReviewActionKind,
        path: String,
        patch: String? = nil,
        targetID: String? = nil
    ) {
        self.kind = kind
        self.path = path
        self.patch = patch
        self.targetID = targetID
    }
}
