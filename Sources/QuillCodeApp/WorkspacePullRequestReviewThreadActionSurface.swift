import Foundation

public enum WorkspacePullRequestReviewThreadActionKind: String, Codable, Sendable, Hashable {
    case resolve
    case unresolve

    public var title: String {
        switch self {
        case .resolve:
            return "Resolve"
        case .unresolve:
            return "Unresolve"
        }
    }

    public var systemImage: String {
        switch self {
        case .resolve:
            return "checkmark.circle"
        case .unresolve:
            return "arrow.uturn.backward.circle"
        }
    }
}

public struct WorkspacePullRequestReviewThreadActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: WorkspacePullRequestReviewThreadActionKind
    public var threadID: String
    public var selector: String?

    public var id: String {
        "\(kind.rawValue):\(threadID)"
    }

    public init(
        kind: WorkspacePullRequestReviewThreadActionKind,
        threadID: String,
        selector: String? = nil
    ) {
        self.kind = kind
        self.threadID = threadID
        self.selector = selector
    }
}
