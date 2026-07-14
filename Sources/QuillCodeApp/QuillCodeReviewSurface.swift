import Foundation

public struct WorkspaceReviewSurface: Codable, Sendable, Hashable {
    public var title: String
    public var subtitle: String
    public var activeScope: WorkspaceReviewScope?
    public var scopeReference: String?
    public var files: [WorkspaceReviewFileSurface]
    public var pullRequestThreads: [WorkspacePullRequestReviewThreadSurface]
    public var pullRequestReviewDraft: WorkspacePullRequestReviewDraftSurface?
    public var totalInsertions: Int
    public var totalDeletions: Int
    public var totalHunks: Int

    public var isVisible: Bool {
        activeScope != nil || !files.isEmpty || !pullRequestThreads.isEmpty || pullRequestReviewDraft != nil
    }

    public var availableScopes: [WorkspaceReviewScope] {
        activeScope == nil ? [] : WorkspaceReviewScope.allCases
    }

    public var activeSelection: WorkspaceReviewSelection? {
        activeScope.flatMap { WorkspaceReviewSelection(scope: $0, reference: scopeReference) }
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
        case title
        case subtitle
        case activeScope
        case scopeReference
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
        activeScope: WorkspaceReviewScope? = nil,
        scopeReference: String? = nil,
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
        self.activeScope = activeScope
        self.scopeReference = scopeReference
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
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.activeScope = try container.decodeIfPresent(WorkspaceReviewScope.self, forKey: .activeScope)
        self.scopeReference = try container.decodeIfPresent(String.self, forKey: .scopeReference)
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
