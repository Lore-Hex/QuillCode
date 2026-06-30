import Foundation

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
            let reviewAction = action.title.lowercased()
            let noteLabel = "inline note\(selectedCount == 1 ? "" : "s")"
            if selectedCount == inlineCommentCount {
                return "Submit \(reviewAction) review with \(selectedCount) \(noteLabel)"
            }
            return "Submit \(reviewAction) review with \(selectedCount) of \(inlineCommentCount) inline notes"
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
        ] + Self.invalidInlineItems(count: invalidInlineCount)
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

    private static func invalidInlineItems(count: Int) -> [String] {
        guard count > 0 else { return [] }
        let noteLabel = "selected inline note\(count == 1 ? "" : "s")"
        let verb = count == 1 ? "needs" : "need"
        return ["\(count) \(noteLabel) \(verb) text"]
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
