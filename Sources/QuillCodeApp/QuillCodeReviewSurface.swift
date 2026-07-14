import Foundation

public struct WorkspaceReviewSurface: Codable, Sendable, Hashable {
    public var isPresented: Bool
    public var title: String
    public var subtitle: String
    public var activeScope: WorkspaceReviewScope?
    public var scopeReference: String?
    public var scopeNotice: String?
    public var lastTurnMessageID: UUID?
    public var files: [WorkspaceReviewFileSurface]
    public var pullRequestThreads: [WorkspacePullRequestReviewThreadSurface]
    public var pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface?
    public var totalInsertions: Int
    public var totalDeletions: Int
    public var totalHunks: Int

    public var hasContent: Bool {
        activeScope != nil || !files.isEmpty || !pullRequestThreads.isEmpty || pullRequestReviewDraft != nil
    }

    public var isVisible: Bool {
        isPresented && hasContent
    }

    public var availableScopes: [WorkspaceReviewScope] {
        activeScope == nil ? [] : WorkspaceReviewScope.allCases
    }

    public var activeSelection: WorkspaceReviewSelection? {
        activeScope.flatMap { WorkspaceReviewSelection(scope: $0, reference: scopeReference) }
    }

    /// Whole-diff actions operate on exactly the paths currently visible in Review. Historical
    /// commit/branch comparisons stay read-only; Last turn gets a provenance-based reverse patch.
    public var wholeDiffActions: [WorkspaceReviewActionSurface] {
        guard let activeScope, !files.isEmpty else { return [] }
        let paths = files.map(\.path)
        switch activeScope {
        case .unstaged:
            return [
                WorkspaceReviewActionSurface(
                    kind: .stageAll,
                    path: "",
                    targetID: "all",
                    scope: activeScope,
                    paths: paths
                ),
                WorkspaceReviewActionSurface(
                    kind: .restoreAll,
                    path: "",
                    targetID: "all",
                    scope: activeScope,
                    paths: paths
                )
            ]
        case .staged:
            return [
                WorkspaceReviewActionSurface(
                    kind: .unstageAll,
                    path: "",
                    targetID: "all",
                    scope: activeScope,
                    paths: paths
                )
            ]
        case .lastTurn:
            guard let lastTurnMessageID else { return [] }
            return [
                WorkspaceReviewActionSurface(
                    kind: .revertTurn,
                    path: "",
                    targetID: "last-turn",
                    scope: activeScope,
                    paths: paths,
                    turnMessageID: lastTurnMessageID
                )
            ]
        case .commit, .branch:
            return []
        }
    }

    public var badgeLabel: String {
        let threadCount = pullRequestThreads.count
        let threadLabel = "\(threadCount) thread\(threadCount == 1 ? "" : "s")"
        let parts = [
            files.isEmpty ? nil : "\(totalHunks) hunk\(totalHunks == 1 ? "" : "s")",
            pullRequestThreads.isEmpty ? nil : threadLabel,
            pullRequestReviewDraft == nil ? nil : "review draft"
        ].compactMap(\.self)
        return parts.isEmpty ? "Review" : parts.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case isPresented
        case title
        case subtitle
        case activeScope
        case scopeReference
        case scopeNotice
        case lastTurnMessageID
        case files
        case pullRequestThreads
        case pullRequestReviewDraft
        case totalInsertions
        case totalDeletions
        case totalHunks
    }

    public init(
        isPresented: Bool = true,
        title: String = "Review changes",
        subtitle: String = "Latest git diff",
        activeScope: WorkspaceReviewScope? = nil,
        scopeReference: String? = nil,
        scopeNotice: String? = nil,
        lastTurnMessageID: UUID? = nil,
        files: [WorkspaceReviewFileSurface] = [],
        pullRequestThreads: [WorkspacePullRequestReviewThreadSurface] = [],
        pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface? = nil
    ) {
        self.isPresented = isPresented
        self.title = files.isEmpty
            && pullRequestThreads.isEmpty
            && pullRequestReviewDraft != nil
            && title == "Review changes"
            ? "Review pull request"
            : title
        self.activeScope = activeScope
        self.scopeReference = scopeReference
        self.scopeNotice = scopeNotice
        self.lastTurnMessageID = lastTurnMessageID
        self.files = files
        self.pullRequestThreads = pullRequestThreads
        self.pullRequestReviewDraft = pullRequestReviewDraft
        self.totalInsertions = files.reduce(0) { $0 + $1.insertions }
        self.totalDeletions = files.reduce(0) { $0 + $1.deletions }
        self.totalHunks = files.reduce(0) { $0 + $1.hunks }
        if !files.isEmpty {
            let fileLabel = "\(files.count) file\(files.count == 1 ? "" : "s") changed"
            self.subtitle = "\(fileLabel), +\(totalInsertions) -\(totalDeletions)"
        } else if !pullRequestThreads.isEmpty {
            let threadCount = pullRequestThreads.count
            let threadLabel = "\(threadCount) review thread\(threadCount == 1 ? "" : "s")"
            let unresolvedCount = pullRequestThreads.filter { !$0.isResolved }.count
            let resolvedCount = pullRequestThreads.count - unresolvedCount
            self.subtitle = "\(threadLabel), \(unresolvedCount) unresolved, \(resolvedCount) resolved"
        } else if let pullRequestReviewDraft {
            self.subtitle = pullRequestReviewDraft.subtitle
        } else if let activeScope {
            self.subtitle = activeScope.emptySubtitle(reference: scopeReference)
        } else {
            self.subtitle = subtitle
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isPresented = try container.decodeIfPresent(Bool.self, forKey: .isPresented) ?? true
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.activeScope = try container.decodeIfPresent(WorkspaceReviewScope.self, forKey: .activeScope)
        self.scopeReference = try container.decodeIfPresent(String.self, forKey: .scopeReference)
        self.scopeNotice = try container.decodeIfPresent(String.self, forKey: .scopeNotice)
        self.lastTurnMessageID = try container.decodeIfPresent(UUID.self, forKey: .lastTurnMessageID)
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
