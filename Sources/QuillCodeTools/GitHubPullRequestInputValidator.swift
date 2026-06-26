import Foundation

public enum GitHubPullRequestInputValidator {
    public static func safeSelector(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 300,
              !trimmed.hasPrefix("-"),
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw GitToolError.invalidPullRequestSelector(value)
        }
        return trimmed
    }

    public static func safeReviewers(_ values: [String]?) throws -> [String] {
        var reviewers: [String] = []
        var seen = Set<String>()
        for value in values ?? [] {
            let reviewer = try safeReviewer(value)
            guard seen.insert(reviewer).inserted else { continue }
            reviewers.append(reviewer)
        }
        return reviewers
    }

    public static func safeReviewer(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 80,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil,
              !trimmed.hasPrefix("-")
        else {
            throw GitToolError.invalidPullRequestReviewer(value)
        }
        if trimmed == "@copilot" {
            return trimmed
        }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ isSafeGitHubReviewerComponent(String($0)) })
        else {
            throw GitToolError.invalidPullRequestReviewer(value)
        }
        return trimmed
    }

    public static func safeLabels(_ values: [String]?) throws -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for value in values ?? [] {
            let label = try safeLabel(value)
            guard seen.insert(label).inserted else { continue }
            labels.append(label)
        }
        return labels
    }

    public static func safeLabel(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 100,
              trimmed.rangeOfCharacter(from: .newlines) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil,
              !trimmed.contains(","),
              !trimmed.hasPrefix("-")
        else {
            throw GitToolError.invalidPullRequestLabel(value)
        }
        return trimmed
    }

    public static func safeReviewFlag(_ value: String) throws -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") {
        case "approve", "approved":
            return "--approve"
        case "comment", "comments":
            return "--comment"
        case "request_changes", "request_change", "changes":
            return "--request-changes"
        default:
            throw GitToolError.invalidPullRequestReviewAction(value)
        }
    }

    public static func safeReviewLine(_ value: Int) throws -> Int {
        guard value > 0 else {
            throw GitToolError.invalidPullRequestReviewLine(value)
        }
        return value
    }

    public static func safeReviewStartLine(_ value: Int?, line: Int) throws -> Int? {
        guard let value else { return nil }
        guard value > 0 else {
            throw GitToolError.invalidPullRequestReviewLine(value)
        }
        guard value <= line else {
            throw GitToolError.invalidPullRequestReviewLineRange(startLine: value, line: line)
        }
        return value
    }

    public static func safeReviewSide(_ value: String?) throws -> String {
        let normalized = (GitInputValidator.trimmedNonEmpty(value) ?? "RIGHT")
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "RIGHT":
            return "RIGHT"
        case "LEFT":
            return "LEFT"
        default:
            throw GitToolError.invalidPullRequestReviewSide(value ?? "")
        }
    }

    public static func safeMergeFlag(_ value: String?) throws -> String {
        let normalized = (GitInputValidator.trimmedNonEmpty(value) ?? "squash")
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "merge", "merge_commit":
            return "--merge"
        case "squash", "squash_merge":
            return "--squash"
        case "rebase":
            return "--rebase"
        default:
            throw GitToolError.invalidPullRequestMergeMethod(value ?? "")
        }
    }

    private static func isSafeGitHubReviewerComponent(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= 39,
              value.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]$|^[A-Za-z0-9]$"#, options: .regularExpression) != nil
        else {
            return false
        }
        return true
    }
}
