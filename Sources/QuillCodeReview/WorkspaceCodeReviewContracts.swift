import Foundation
import QuillCodeCore
import QuillCodeTools

public enum WorkspaceCodeReviewScope: String, Codable, Sendable, CaseIterable, Hashable {
    case uncommitted
    case baseBranch
    case commit
    case custom

    public var title: String {
        switch self {
        case .uncommitted:
            "Uncommitted changes"
        case .baseBranch:
            "Against a base branch"
        case .commit:
            "A specific commit"
        case .custom:
            "Custom review"
        }
    }

    public var requiresReference: Bool {
        self == .baseBranch || self == .commit
    }

    public var requiresInstructions: Bool {
        self == .custom
    }
}

public struct WorkspaceCodeReviewRequest: Codable, Sendable, Hashable {
    public static let maximumTitleLength = 512

    public var scope: WorkspaceCodeReviewScope
    public var reference: String?
    public var instructions: String?
    public var title: String?
    public var delivery: CodeReviewDelivery
    public var model: String?

    public init(
        scope: WorkspaceCodeReviewScope = .uncommitted,
        reference: String? = nil,
        instructions: String? = nil,
        title: String? = nil,
        delivery: CodeReviewDelivery = .current,
        model: String? = nil
    ) {
        self.scope = scope
        self.reference = Self.nonempty(reference)
        self.instructions = Self.nonempty(instructions)
        self.title = Self.nonempty(title)
        self.delivery = delivery
        self.model = Self.normalizedModel(model)
    }

    public var validationMessage: String? {
        if scope.requiresReference {
            guard let reference = Self.nonempty(reference) else {
                return scope == .baseBranch
                    ? "Enter the base branch to review against."
                    : "Enter the commit or SHA to review."
            }
            guard (try? GitInputValidator.safeName(reference)) != nil else {
                return scope == .baseBranch
                    ? "Enter a valid base branch name."
                    : "Enter a valid commit or SHA."
            }
        }
        if scope.requiresInstructions, Self.nonempty(instructions) == nil {
            return "Describe what the reviewer should focus on."
        }
        if let title = Self.nonempty(title) {
            guard scope == .commit else { return "Commit titles require a commit review." }
            guard title.utf8.count <= Self.maximumTitleLength else {
                return "Commit titles can contain at most \(Self.maximumTitleLength) bytes."
            }
        }
        return nil
    }

    public var isValid: Bool { validationMessage == nil }

    public var transcriptPrompt: String {
        switch scope {
        case .uncommitted:
            "Review all uncommitted changes"
        case .baseBranch:
            "Review changes against base branch `\(Self.nonempty(reference) ?? "")`"
        case .commit:
            if let title = Self.nonempty(title) {
                "Review commit `\(Self.nonempty(reference) ?? "")`: \(title)"
            } else {
                "Review commit `\(Self.nonempty(reference) ?? "")`"
            }
        case .custom:
            "Review all uncommitted changes with this focus: \(Self.nonempty(instructions) ?? "")"
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedModel(_ model: String?) -> String? {
        guard let model = nonempty(model) else { return nil }
        return TrustedRouterDefaults.normalizedDefaultModelID(model)
    }
}
