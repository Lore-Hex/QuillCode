import Foundation
import QuillCodeCore

public enum WorkspaceReviewScope: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case unstaged
    case staged
    case commit
    case branch
    case lastTurn = "last_turn"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unstaged:
            return "Unstaged"
        case .staged:
            return "Staged"
        case .commit:
            return "Commit"
        case .branch:
            return "Branch"
        case .lastTurn:
            return "Last turn"
        }
    }

    public func emptySubtitle(reference: String? = nil) -> String {
        switch self {
        case .unstaged:
            return "No unstaged changes"
        case .staged:
            return "No staged changes"
        case .commit:
            return reference.map { "No changes in commit \($0)" } ?? "No commit selected"
        case .branch:
            return reference.map { "No changes against \($0)" } ?? "No base branch selected"
        case .lastTurn:
            return "No changes in the last turn"
        }
    }

    public var requiresReference: Bool {
        switch self {
        case .unstaged, .staged, .lastTurn:
            return false
        case .commit, .branch:
            return true
        }
    }

    public var referenceLabel: String? {
        switch self {
        case .unstaged, .staged, .lastTurn:
            return nil
        case .commit:
            return "Commit"
        case .branch:
            return "Base branch"
        }
    }

    public var referencePlaceholder: String? {
        switch self {
        case .unstaged, .staged, .lastTurn:
            return nil
        case .commit:
            return "HEAD or commit SHA"
        case .branch:
            return "main or origin/main"
        }
    }
}

public enum WorkspaceReviewSelection: Sendable, Hashable {
    case unstaged
    case staged
    case commit(String)
    case branch(String)
    case lastTurn

    public var scope: WorkspaceReviewScope {
        switch self {
        case .unstaged:
            return .unstaged
        case .staged:
            return .staged
        case .commit:
            return .commit
        case .branch:
            return .branch
        case .lastTurn:
            return .lastTurn
        }
    }

    public var reference: String? {
        switch self {
        case .unstaged, .staged, .lastTurn:
            return nil
        case .commit(let reference), .branch(let reference):
            return reference
        }
    }

    public init?(scope: WorkspaceReviewScope, reference: String? = nil) {
        let normalizedReference = reference?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch scope {
        case .unstaged:
            self = .unstaged
        case .staged:
            self = .staged
        case .commit:
            guard let normalizedReference, !normalizedReference.isEmpty else { return nil }
            self = .commit(normalizedReference)
        case .branch:
            guard let normalizedReference, !normalizedReference.isEmpty else { return nil }
            self = .branch(normalizedReference)
        case .lastTurn:
            self = .lastTurn
        }
    }

    var gitDiffArgumentsJSON: String {
        switch self {
        case .unstaged:
            return "{}"
        case .staged:
            return ToolArguments.json(["staged": true])
        case .commit(let reference):
            return ToolArguments.json(["commit": reference])
        case .branch(let reference):
            return ToolArguments.json(["baseBranch": reference])
        case .lastTurn:
            return "{}"
        }
    }
}
