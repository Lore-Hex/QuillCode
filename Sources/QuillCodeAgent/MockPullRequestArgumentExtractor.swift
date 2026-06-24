import Foundation

enum MockPullRequestArgumentExtractor {
    static func createArguments(from request: String) -> [String: String] {
        var arguments: [String: String] = [:]
        arguments["title"] = pullRequestTitle(from: request) ?? "QuillCode changes"

        let tokens = tokenizeArguments(request)
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

    static func selectorArguments(from request: String) -> [String: String] {
        guard let selector = pullRequestSelector(from: request) else { return [:] }
        return ["selector": selector]
    }

    static func commentArguments(from request: String) -> [String: String] {
        var arguments = selectorArguments(from: request)
        arguments["body"] = pullRequestCommentBody(from: request) ?? request
        return arguments
    }

    static func mergeArguments(from request: String) -> [String: String] {
        var arguments = selectorArguments(from: request)
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

    static func reviewArguments(from request: String) -> [String: String] {
        var arguments = selectorArguments(from: request)
        let action = pullRequestReviewAction(from: request)
        arguments["action"] = action
        if let body = pullRequestCommentBody(from: request) {
            arguments["body"] = body
        } else if action != "approve" {
            arguments["body"] = request
        }
        return arguments
    }

    static func reviewerArguments(from request: String) -> [String: String] {
        var arguments = selectorArguments(from: request)
        let reviewers = pullRequestReviewers(from: request)
        if request.lowercased().contains("remove reviewer")
            || request.lowercased().contains("remove reviewers")
            || request.lowercased().contains("unrequest") {
            arguments["remove"] = reviewers.joined(separator: ",")
        } else {
            arguments["add"] = reviewers.joined(separator: ",")
        }
        return arguments
    }

    static func labelArguments(from request: String) -> [String: String] {
        var arguments = selectorArguments(from: request)
        let labels = pullRequestLabels(from: request)
        if request.lowercased().contains("remove label")
            || request.lowercased().contains("remove labels")
            || request.lowercased().contains("unlabel") {
            arguments["remove"] = labels.joined(separator: ",")
        } else {
            arguments["add"] = labels.joined(separator: ",")
        }
        return arguments
    }

    static func pullRequestLabels(from request: String) -> [String] {
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
        if let range = firstMarkerRange(in: lower, markers: markers) {
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

    static func pullRequestReviewers(from request: String) -> [String] {
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
        if let range = firstMarkerRange(in: lower, markers: markers) {
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

    static func pullRequestReviewAction(from request: String) -> String {
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

    static func pullRequestCommentBody(from request: String) -> String? {
        if let quoted = backtickQuotedText(from: request) {
            return quoted
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

    static func pullRequestSelector(from request: String) -> String? {
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

    static func pullRequestTitle(from request: String) -> String? {
        if let quoted = backtickQuotedText(from: request) {
            return quoted
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

    private static func tokenizeArguments(_ request: String) -> [String] {
        request
            .split { !$0.isLetter && !$0.isNumber && $0 != "/" && $0 != "-" && $0 != "_" && $0 != "." }
            .map(String.init)
    }

    private static func firstMarkerRange(in lowercasedText: String, markers: [String]) -> Range<String.Index>? {
        markers
            .compactMap { lowercasedText.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }

    private static func backtickQuotedText(from request: String) -> String? {
        guard let first = request.firstIndex(of: "`"),
              let last = request[request.index(after: first)...].lastIndex(of: "`"),
              first < last
        else {
            return nil
        }
        let quoted = String(request[request.index(after: first)..<last])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return quoted.isEmpty ? nil : quoted
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

    private static func trimTrailingPullRequestClauses(from title: String) -> String {
        let lower = title.lowercased()
        let markers = [" base ", " head "]
        let end = markers
            .compactMap { lower.range(of: $0)?.lowerBound }
            .min() ?? title.endIndex
        return String(title[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
