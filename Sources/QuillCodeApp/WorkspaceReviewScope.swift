import Foundation

public enum WorkspaceReviewScope: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case unstaged
    case staged

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unstaged:
            return "Unstaged"
        case .staged:
            return "Staged"
        }
    }

    public var emptySubtitle: String {
        switch self {
        case .unstaged:
            return "No unstaged changes"
        case .staged:
            return "No staged changes"
        }
    }

    var gitDiffArgumentsJSON: String {
        switch self {
        case .unstaged:
            return "{}"
        case .staged:
            return #"{"staged":true}"#
        }
    }
}
