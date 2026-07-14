import Foundation

public enum PullRequestLifecycleStatus: String, Codable, Sendable, Hashable {
    case draft
    case open
    case queued
    case merged
    case closed

    public var label: String {
        switch self {
        case .draft:
            return "Draft"
        case .open:
            return "Open"
        case .queued:
            return "Queued"
        case .merged:
            return "Merged"
        case .closed:
            return "Closed"
        }
    }

    public var isTerminal: Bool {
        self == .merged || self == .closed
    }
}

/// Durable GitHub pull-request identity for a task. The latest status is cached so task rows remain
/// truthful across relaunches; explicit refresh and landing actions replace it with GitHub's current
/// state before making lifecycle decisions.
public struct PullRequestLink: Codable, Sendable, Hashable {
    public var number: Int
    public var title: String
    public var url: String
    public var status: PullRequestLifecycleStatus
    public var baseBranch: String
    public var headBranch: String
    public var headCommit: String
    public var mergeState: String?
    public var updatedAt: Date

    public init(
        number: Int,
        title: String,
        url: String,
        status: PullRequestLifecycleStatus,
        baseBranch: String,
        headBranch: String,
        headCommit: String,
        mergeState: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.status = status
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.headCommit = headCommit
        self.mergeState = mergeState
        self.updatedAt = updatedAt
    }

    public var compactLabel: String {
        "PR #\(number) · \(status.label)"
    }
}
