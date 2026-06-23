import Foundation
import QuillCodeCore
import QuillCodeTools

public struct MockLLMClient: LLMClient {
    public init() {}

    public func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        if let lastToolOutput = thread.messages.last(where: { $0.role == .tool })?.content,
           let feedback = try? JSONHelpers.decode(AgentToolFeedback.self, from: lastToolOutput) {
            return .say(AgentRunner.finalAnswer(
                for: feedback.toolCall,
                result: feedback.result,
                followUpReviewResult: feedback.followUpResult
            ))
        }

        let request = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = request.lowercased()

        if let command = Self.extractExplicitRunCommand(from: request), !command.isEmpty {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": command])
            ))
        }

        if let memory = Self.extractMemoryContent(from: request),
           tools.contains(where: { $0.name == ToolDefinition.memoryRemember.name }) {
            return .tool(.init(
                name: ToolDefinition.memoryRemember.name,
                argumentsJSON: ToolArguments.json(["content": memory])
            ))
        }

        if lower.contains("plan"),
           tools.contains(where: { $0.name == ToolDefinition.planUpdate.name }) {
            let update = AgentPlanUpdate(
                explanation: "Model-authored plan for the current request.",
                plan: [
                    AgentPlanItem(step: "Inspect current state", status: .completed),
                    AgentPlanItem(step: "Implement requested change", status: .inProgress),
                    AgentPlanItem(step: "Validate and summarize", status: .pending)
                ]
            )
            return .tool(.init(
                name: ToolDefinition.planUpdate.name,
                argumentsJSON: try JSONHelpers.encodePretty(update)
            ))
        }

        if lower.contains("whoami") {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "whoami"])
            ))
        }

        if lower.contains("openclaw") {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "command -v openclaw || which openclaw || echo 'not found'"
                ])
            ))
        }

        if Self.isBrowserInspectionRequest(lower), tools.contains(where: { $0.name == ToolDefinition.browserInspect.name }) {
            return .tool(.init(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}"))
        }

        if lower.contains("disk") || lower.contains("storage") || lower.contains("how much hd") {
            return .tool(.init(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "df -h / /Quill 2>/dev/null || df -h /"
                ])
            ))
        }

        if (lower.contains("make") || lower.contains("create") || lower.contains("write")),
           lower.contains("file") {
            let content = lower.contains("hello world") ? "hello world\n" : "\(request)\n"
            if tools.contains(where: { $0.name == ToolDefinition.fileWrite.name }) {
                return .tool(.init(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "hello.txt",
                        "content": content
                    ])
                ))
            }
            if tools.contains(where: { $0.name == ToolDefinition.shellRun.name }) {
                let command = "printf %s \(Self.shellSingleQuoted(content)) > hello.txt"
                return .tool(.init(
                    name: ToolDefinition.shellRun.name,
                    argumentsJSON: ToolArguments.json(["cmd": command])
                ))
            }
            return .tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "hello.txt",
                    "content": content
                ])
            ))
        }

        if lower.contains("git status") {
            return .tool(.init(name: ToolDefinition.gitStatus.name, argumentsJSON: "{}"))
        }

        if lower.contains("git diff") {
            return .tool(.init(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"))
        }

        if Self.isPullRequestCheckoutRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestCheckout.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestSelectorArguments(from: request))
            ))
        }

        if Self.isPullRequestReviewerRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestReviewers.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestReviewerArguments(from: request))
            ))
        }

        if Self.isPullRequestLabelRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestLabels.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestLabelArguments(from: request))
            ))
        }

        if Self.isPullRequestMergeRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestMerge.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestMergeArguments(from: request))
            ))
        }

        if Self.isPullRequestReviewActionRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestReview.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestReviewArguments(from: request))
            ))
        }

        if Self.isPullRequestCommentRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestComment.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestCommentArguments(from: request))
            ))
        }

        if Self.isPullRequestChecksRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestChecks.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestSelectorArguments(from: request))
            ))
        }

        if Self.isPullRequestViewRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestView.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestSelectorArguments(from: request))
            ))
        }

        if Self.isPullRequestRequest(lower) {
            return .tool(.init(
                name: ToolDefinition.gitPullRequestCreate.name,
                argumentsJSON: ToolArguments.json(Self.extractPullRequestArguments(from: request))
            ))
        }

        if lower.contains("commit") {
            return .tool(.init(
                name: ToolDefinition.gitCommit.name,
                argumentsJSON: ToolArguments.json([
                    "message": Self.extractCommitMessage(from: request) ?? "QuillCode changes"
                ])
            ))
        }

        if lower.contains("push") || lower.contains("publish branch") {
            return .tool(.init(
                name: ToolDefinition.gitPush.name,
                argumentsJSON: ToolArguments.json(Self.extractPushArguments(from: request))
            ))
        }

        return .say("I can inspect and edit this project, run shell commands, review git diffs, and use Computer Use as the platform backends come online.")
    }

    static func extractExplicitRunCommand(from request: String) -> String? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("run ") else { return nil }
        if let first = trimmed.firstIndex(of: "`"),
           let last = trimmed[trimmed.index(after: first)...].lastIndex(of: "`"),
           first < last {
            return String(trimmed[trimmed.index(after: first)..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractMemoryContent(from request: String) -> String? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let markers = [
            "remember that ",
            "remember to ",
            "remember ",
            "please remember that ",
            "please remember to ",
            "please remember ",
            "memorize that ",
            "memorize "
        ]
        guard let marker = markers.first(where: { lower.hasPrefix($0) }) else { return nil }
        let start = trimmed.index(trimmed.startIndex, offsetBy: marker.count)
        let content = String(trimmed[start...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    static func extractCommitMessage(from request: String) -> String? {
        if let first = request.firstIndex(of: "`"),
           let last = request[request.index(after: first)...].lastIndex(of: "`"),
           first < last {
            let quoted = String(request[request.index(after: first)..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return quoted.isEmpty ? nil : quoted
        }

        let lower = request.lowercased()
        guard let range = lower.range(of: "message") else { return nil }
        var message = String(request[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if message.hasPrefix(":") {
            message.removeFirst()
            message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        message = message.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return message.isEmpty ? nil : message
    }

    static func extractPushArguments(from request: String) -> [String: String] {
        let tokens = request
            .split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "-" && $0 != "_" && $0 != "." }
            .map(String.init)
        var arguments: [String: String] = [:]
        if let remoteIndex = tokens.firstIndex(where: { $0.lowercased() == "remote" }),
           tokens.indices.contains(tokens.index(after: remoteIndex)) {
            arguments["remote"] = tokens[tokens.index(after: remoteIndex)]
        }
        if let branchIndex = tokens.firstIndex(where: { $0.lowercased() == "branch" }),
           tokens.indices.contains(tokens.index(after: branchIndex)) {
            arguments["branch"] = tokens[tokens.index(after: branchIndex)]
        }
        return arguments
    }

    static func isPullRequestRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        let creationTerms = tokens.contains("create")
            || tokens.contains("submit")
            || tokens.contains("new")
            || (tokens.contains("open") && !tokens.contains("current") && !tokens.contains("existing"))
        return mentionsPullRequest && creationTerms
    }

    static func isPullRequestChecksRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        let checkTerms = tokens.contains("check")
            || tokens.contains("checks")
            || tokens.contains("ci")
            || tokens.contains("status")
        return mentionsPullRequest && checkTerms
    }

    static func isPullRequestCommentRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        let commentTerms = tokens.contains("comment")
            || tokens.contains("comments")
            || tokens.contains("reply")
        let readTerms = tokens.contains("show")
            || tokens.contains("view")
            || tokens.contains("read")
            || tokens.contains("inspect")
            || tokens.contains("summarize")
        return mentionsPullRequest && commentTerms && !readTerms
    }

    static func isPullRequestMergeRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        guard mentionsPullRequest else { return false }
        return tokens.contains("merge")
            || tokens.contains("automerge")
            || lowercasedRequest.contains("auto merge")
            || lowercasedRequest.contains("merge train")
    }

    static func isPullRequestCheckoutRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        guard mentionsPullRequest else { return false }
        return tokens.contains("checkout")
            || lowercasedRequest.contains("check out")
            || tokens.contains("switch")
            || tokens.contains("open")
    }

    static func isPullRequestReviewActionRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        guard mentionsPullRequest else { return false }
        if tokens.contains("approve") || tokens.contains("approved") {
            return true
        }
        if lowercasedRequest.contains("request changes")
            || lowercasedRequest.contains("needs changes")
            || lowercasedRequest.contains("reject pr") {
            return true
        }
        return (tokens.contains("submit") || tokens.contains("leave") || tokens.contains("add"))
            && tokens.contains("review")
    }

    static func isPullRequestReviewerRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        guard mentionsPullRequest else { return false }
        if lowercasedRequest.contains("request review from")
            || lowercasedRequest.contains("request reviewer")
            || lowercasedRequest.contains("request reviewers")
            || lowercasedRequest.contains("add reviewer")
            || lowercasedRequest.contains("add reviewers")
            || lowercasedRequest.contains("re-request reviewer")
            || lowercasedRequest.contains("remove reviewer")
            || lowercasedRequest.contains("remove reviewers") {
            return true
        }
        return (tokens.contains("reviewer") || tokens.contains("reviewers"))
            && (tokens.contains("request") || tokens.contains("add") || tokens.contains("remove"))
    }

    static func isPullRequestLabelRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        guard mentionsPullRequest else { return false }
        if lowercasedRequest.contains("add label")
            || lowercasedRequest.contains("add labels")
            || lowercasedRequest.contains("remove label")
            || lowercasedRequest.contains("remove labels")
            || lowercasedRequest.contains("label this")
            || lowercasedRequest.contains("label the pr")
            || lowercasedRequest.contains("label pr")
            || lowercasedRequest.contains("unlabel") {
            return true
        }
        return (tokens.contains("label") || tokens.contains("labels"))
            && (tokens.contains("add") || tokens.contains("remove") || tokens.contains("set"))
    }

    static func isPullRequestViewRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let mentionsPullRequest = lowercasedRequest.contains("pull request") || tokens.contains("pr")
        let viewTerms = tokens.contains("view")
            || tokens.contains("show")
            || tokens.contains("inspect")
            || tokens.contains("current")
            || tokens.contains("comments")
            || tokens.contains("reviews")
            || tokens.contains("review")
        let createTerms = tokens.contains("create")
            || tokens.contains("submit")
            || tokens.contains("new")
        return mentionsPullRequest && viewTerms && !createTerms
    }

    static func isBrowserInspectionRequest(_ lowercasedRequest: String) -> Bool {
        let browserTerms = lowercasedRequest.contains("browser")
            || lowercasedRequest.contains("page")
            || lowercasedRequest.contains("preview")
            || lowercasedRequest.contains("localhost")
        let inspectionTerms = lowercasedRequest.contains("inspect")
            || lowercasedRequest.contains("look at")
            || lowercasedRequest.contains("what is on")
            || lowercasedRequest.contains("summarize")
            || lowercasedRequest.contains("snapshot")
        return browserTerms && inspectionTerms
    }

    static func extractPullRequestArguments(from request: String) -> [String: String] {
        var arguments: [String: String] = [:]
        arguments["title"] = extractPullRequestTitle(from: request) ?? "QuillCode changes"

        let tokens = request
            .split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "-" && $0 != "_" && $0 != "." }
            .map(String.init)
        if let baseIndex = tokens.firstIndex(where: { $0.lowercased() == "base" }),
           tokens.indices.contains(tokens.index(after: baseIndex)) {
            arguments["base"] = tokens[tokens.index(after: baseIndex)]
        }
        if let headIndex = tokens.firstIndex(where: { $0.lowercased() == "head" }),
           tokens.indices.contains(tokens.index(after: headIndex)) {
            arguments["head"] = tokens[tokens.index(after: headIndex)]
        }
        return arguments
    }

    static func extractPullRequestSelectorArguments(from request: String) -> [String: String] {
        guard let selector = extractPullRequestSelector(from: request) else { return [:] }
        return ["selector": selector]
    }

    static func extractPullRequestCommentArguments(from request: String) -> [String: String] {
        var arguments = extractPullRequestSelectorArguments(from: request)
        arguments["body"] = extractPullRequestCommentBody(from: request) ?? request
        return arguments
    }

    static func extractPullRequestMergeArguments(from request: String) -> [String: String] {
        var arguments = extractPullRequestSelectorArguments(from: request)
        let lower = request.lowercased()
        if lower.contains("rebase") {
            arguments["method"] = "rebase"
        } else if lower.contains("merge commit") {
            arguments["method"] = "merge"
        } else {
            arguments["method"] = "squash"
        }
        if lower.contains("auto merge")
            || lower.contains("automerge")
            || lower.contains("merge train") {
            arguments["auto"] = "true"
        }
        if lower.contains("delete branch")
            || lower.contains("delete the branch")
            || lower.contains("cleanup branch") {
            arguments["deleteBranch"] = "true"
        }
        return arguments
    }

    static func extractPullRequestReviewArguments(from request: String) -> [String: String] {
        var arguments = extractPullRequestSelectorArguments(from: request)
        let action = extractPullRequestReviewAction(from: request)
        arguments["action"] = action
        if let body = extractPullRequestCommentBody(from: request) {
            arguments["body"] = body
        } else if action != "approve" {
            arguments["body"] = request
        }
        return arguments
    }

    static func extractPullRequestReviewerArguments(from request: String) -> [String: String] {
        var arguments = extractPullRequestSelectorArguments(from: request)
        let reviewers = extractPullRequestReviewers(from: request)
        if request.lowercased().contains("remove reviewer")
            || request.lowercased().contains("remove reviewers")
            || request.lowercased().contains("unrequest") {
            arguments["remove"] = reviewers.joined(separator: ",")
        } else {
            arguments["add"] = reviewers.joined(separator: ",")
        }
        return arguments
    }

    static func extractPullRequestLabelArguments(from request: String) -> [String: String] {
        var arguments = extractPullRequestSelectorArguments(from: request)
        let labels = extractPullRequestLabels(from: request)
        if request.lowercased().contains("remove label")
            || request.lowercased().contains("remove labels")
            || request.lowercased().contains("unlabel") {
            arguments["remove"] = labels.joined(separator: ",")
        } else {
            arguments["add"] = labels.joined(separator: ",")
        }
        return arguments
    }

    static func extractPullRequestLabels(from request: String) -> [String] {
        let lower = request.lowercased()
        let markers = [
            "add labels ",
            "add label ",
            "remove labels ",
            "remove label ",
            "label this ",
            "label the pr ",
            "label pr ",
            "labels ",
            "label "
        ]
        let rawList: String
        if let range = markers.compactMap({ lower.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            rawList = String(request[range.upperBound...])
        } else {
            rawList = request
        }
        let pullRequestTrimmed = trimLeadingPullRequestReference(
            from: trimTrailingPullRequestReference(from: rawList)
        )
        let labels = pullRequestTrimmed
            .replacingOccurrences(of: " and ", with: ",", options: [.caseInsensitive])
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".:;\"' ").union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .filter { $0.range(of: #"^#?\d+$"#, options: .regularExpression) == nil }
            .filter { label in
                let lowercasedLabel = label.lowercased()
                return lowercasedLabel != "pr"
                    && lowercasedLabel != "pull request"
                    && lowercasedLabel != "pull"
                    && lowercasedLabel != "request"
            }
        return labels.isEmpty ? ["needs review"] : labels
    }

    static func extractPullRequestReviewers(from request: String) -> [String] {
        let lower = request.lowercased()
        let markers = [
            "request review from ",
            "request reviewers ",
            "request reviewer ",
            "add reviewers ",
            "add reviewer ",
            "remove reviewers ",
            "remove reviewer ",
            "reviewers ",
            "reviewer "
        ]
        let rawList: String
        if let range = markers.compactMap({ lower.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            rawList = String(request[range.upperBound...])
        } else {
            rawList = request
        }
        let pullRequestTrimmed = trimLeadingPullRequestReference(
            from: trimTrailingPullRequestReference(from: rawList)
        )
        let reviewers = pullRequestTrimmed
            .replacingOccurrences(of: " and ", with: ",", options: [.caseInsensitive])
            .split { character in
                character == "," || character.isWhitespace
            }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".:;\"'")) }
            .filter { !$0.isEmpty }
            .filter { $0.range(of: #"^#?\d+$"#, options: .regularExpression) == nil }
            .filter { token in
                let lowercasedToken = token.lowercased()
                return lowercasedToken != "pr"
                    && lowercasedToken != "pull"
                    && lowercasedToken != "request"
            }
        return reviewers.isEmpty ? ["@copilot"] : reviewers
    }

    private static func trimTrailingPullRequestReference(from text: String) -> String {
        let lower = text.lowercased()
        let markers = [" on pr", " for pr", " to pr", " on pull request", " for pull request", " to pull request"]
        let end = markers
            .compactMap { lower.range(of: $0)?.lowerBound }
            .min() ?? text.endIndex
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimLeadingPullRequestReference(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("pull request ") {
            trimmed = String(trimmed.dropFirst("pull request ".count))
        } else if lower.hasPrefix("pr ") {
            trimmed = String(trimmed.dropFirst("pr ".count))
        }
        if let range = trimmed.range(of: #"^#?\d+\s+"#, options: .regularExpression) {
            trimmed.removeSubrange(range)
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractPullRequestReviewAction(from request: String) -> String {
        let lower = request.lowercased()
        if lower.contains("request changes")
            || lower.contains("needs changes")
            || lower.contains("reject pr") {
            return "request_changes"
        }
        if lower.contains("approve") || lower.contains("approved") {
            return "approve"
        }
        return "comment"
    }

    static func extractPullRequestCommentBody(from request: String) -> String? {
        if let first = request.firstIndex(of: "`"),
           let last = request[request.index(after: first)...].lastIndex(of: "`"),
           first < last {
            let quoted = String(request[request.index(after: first)..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return quoted.isEmpty ? nil : quoted
        }

        let lower = request.lowercased()
        for marker in [" saying ", " with comment ", " comment: ", " comment ", " says "] {
            guard let range = lower.range(of: marker) else { continue }
            let body = String(request[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return body.isEmpty ? nil : body
        }
        return nil
    }

    static func extractPullRequestSelector(from request: String) -> String? {
        let tokens = request
            .split { character in
                character.isWhitespace
                    || [",", ":", ";", "(", ")", "[", "]", "{", "}", "\"", "'"].contains(character)
            }
            .map(String.init)
        for token in tokens {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if cleaned.range(of: #"^#?\d+$"#, options: .regularExpression) != nil {
                return cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
            }
            if cleaned.hasPrefix("https://github.com/"), cleaned.contains("/pull/") {
                return cleaned
            }
        }
        return nil
    }

    static func extractPullRequestTitle(from request: String) -> String? {
        if let first = request.firstIndex(of: "`"),
           let last = request[request.index(after: first)...].lastIndex(of: "`"),
           first < last {
            let quoted = String(request[request.index(after: first)..<last])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return quoted.isEmpty ? nil : quoted
        }

        let lower = request.lowercased()
        for marker in [" titled ", " title "] {
            guard let range = lower.range(of: marker) else { continue }
            var title = String(request[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if title.hasPrefix(":") {
                title.removeFirst()
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            title = trimTrailingPullRequestClauses(from: title)
            return title.isEmpty ? nil : title
        }
        return nil
    }

    private static func trimTrailingPullRequestClauses(from title: String) -> String {
        let lower = title.lowercased()
        let markers = [" base ", " head "]
        let end = markers
            .compactMap { lower.range(of: $0)?.lowerBound }
            .min() ?? title.endIndex
        return String(title[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

