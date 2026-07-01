import Foundation

public enum WorkspaceContextSummaryPurpose: String, Codable, Sendable, Hashable {
    case compact
    case forkSummary

    var promptTitle: String {
        switch self {
        case .compact:
            return "compact this QuillCode thread"
        case .forkSummary:
            return "summarize this QuillCode thread for a fork"
        }
    }
}
