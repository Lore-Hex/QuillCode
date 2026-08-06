import Foundation

public enum WorkspaceContextSummaryPurpose: String, Codable, Sendable, Hashable {
    case compact
    case forkSummary

    var promptTitle: String {
        switch self {
        case .compact:
            return "compact this \(QuillCodeProduct.displayName) thread"
        case .forkSummary:
            return "summarize this \(QuillCodeProduct.displayName) thread for a fork"
        }
    }
}
