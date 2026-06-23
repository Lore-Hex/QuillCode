import Foundation
import QuillCodeCore

public struct GitHubPullRequestToolExecutor: Sendable {
    private let runner: GitProcessRunner

    public init(runner: GitProcessRunner) {
        self.runner = runner
    }

    public init(githubCLIExecutable: URL?) {
        self.runner = GitProcessRunner(githubCLIExecutable: githubCLIExecutable)
    }

    public func createPullRequest(
        cwd: URL,
        title: String? = nil,
        body: String? = nil,
        base: String? = nil,
        head: String? = nil,
        draft: Bool = false,
        fill: Bool = false
    ) -> ToolResult {
        do {
            let trimmedTitle = GitInputValidator.trimmedNonEmpty(title)
            guard fill || trimmedTitle != nil else {
                throw GitToolError.emptyPullRequestTitle
            }

            var arguments = ["pr", "create"]
            if let trimmedTitle {
                arguments += ["--title", trimmedTitle]
            }
            if let body = GitInputValidator.trimmedNonEmpty(body) {
                arguments += ["--body", body]
            }
            if let base = GitInputValidator.trimmedNonEmpty(base) {
                arguments += ["--base", try GitInputValidator.safeName(base)]
            }
            if let head = GitInputValidator.trimmedNonEmpty(head) {
                arguments += ["--head", try GitInputValidator.safeName(head)]
            }
            if draft {
                arguments.append("--draft")
            }
            if fill {
                arguments.append("--fill")
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 120))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func view(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "view"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            arguments.append("--comments")
            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 45))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func checks(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "checks"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            return runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 45)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func diff(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "diff"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            return runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 45)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func checkout(cwd: URL, selector: String? = nil, branch: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "checkout"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            if let branch = GitInputValidator.trimmedNonEmpty(branch) {
                arguments += ["--branch", try GitInputValidator.safeName(branch)]
            }
            return runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 120)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func updateReviewers(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        do {
            let reviewersToAdd = try Self.safeReviewers(add)
            let reviewersToRemove = try Self.safeReviewers(remove)
            guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
                throw GitToolError.emptyPullRequestReviewers
            }

            var arguments = ["pr", "edit"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            if !reviewersToAdd.isEmpty {
                arguments += ["--add-reviewer", reviewersToAdd.joined(separator: ",")]
            }
            if !reviewersToRemove.isEmpty {
                arguments += ["--remove-reviewer", reviewersToRemove.joined(separator: ",")]
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func updateLabels(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        do {
            let labelsToAdd = try Self.safeLabels(add)
            let labelsToRemove = try Self.safeLabels(remove)
            guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
                throw GitToolError.emptyPullRequestLabels
            }

            var arguments = ["pr", "edit"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            if !labelsToAdd.isEmpty {
                arguments += ["--add-label", labelsToAdd.joined(separator: ",")]
            }
            if !labelsToRemove.isEmpty {
                arguments += ["--remove-label", labelsToRemove.joined(separator: ",")]
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func comment(cwd: URL, selector: String? = nil, body: String) -> ToolResult {
        do {
            guard let body = GitInputValidator.trimmedNonEmpty(body) else {
                throw GitToolError.emptyPullRequestComment
            }

            var arguments = ["pr", "comment"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            arguments += ["--body", body]

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func review(
        cwd: URL,
        selector: String? = nil,
        action: String,
        body: String? = nil
    ) -> ToolResult {
        do {
            let flag = try Self.safeReviewFlag(action)
            let body = GitInputValidator.trimmedNonEmpty(body)
            guard flag == "--approve" || body != nil else {
                throw GitToolError.emptyPullRequestReviewBody
            }

            var arguments = ["pr", "review"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            arguments.append(flag)
            if let body {
                arguments += ["--body", body]
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func merge(
        cwd: URL,
        selector: String? = nil,
        method: String? = nil,
        auto: Bool = false,
        deleteBranch: Bool = false
    ) -> ToolResult {
        do {
            var arguments = ["pr", "merge"]
            if let selector = try Self.safeSelector(selector) {
                arguments.append(selector)
            }
            arguments.append(try Self.safeMergeFlag(method))
            if auto {
                arguments.append("--auto")
            }
            if deleteBranch {
                arguments.append("--delete-branch")
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 120))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

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

    public static func extractURLs(from output: String) -> [String] {
        output
            .split { $0.isWhitespace }
            .map(String.init)
            .filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
    }

    private func addURLArtifacts(to result: ToolResult) -> ToolResult {
        guard result.ok else { return result }
        return ToolResult(
            ok: true,
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            artifacts: Self.extractURLs(from: result.stdout)
        )
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
