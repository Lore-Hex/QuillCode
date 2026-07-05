import Foundation
import QuillCodeCore
import QuillCodeTools

enum AgentGitBranchMutationRequestParser {
    static func toolCall(for request: String, tools: [ToolDefinition]) -> ToolCall? {
        guard tools.contains(where: { $0.name == ToolDefinition.gitBranchSwitch.name }),
              let arguments = arguments(from: request)
        else {
            return nil
        }
        return ToolCall(
            name: ToolDefinition.gitBranchSwitch.name,
            argumentsJSON: ToolArguments.json(arguments)
        )
    }

    static func arguments(from request: String) -> [String: Any]? {
        let lower = request.lowercased()
        guard lower.contains("branch")
            || lower.contains("git switch")
            || lower.contains("git checkout")
            || lower.contains("checkout") else {
            return nil
        }
        guard !lower.contains("delete branch"),
              !lower.contains("remove branch") else {
            return nil
        }

        let tokens = request.split { $0.isWhitespace }.map(String.init)
        if lower.contains("create")
            || lower.contains("new branch")
            || lower.contains("git switch -c") {
            guard let branch = tokenAfterPreferredMarkers(["branch", "-c"], in: tokens) else {
                return nil
            }
            var arguments: [String: Any] = ["branch": branch, "create": true]
            if let startPoint = tokenAfterPreferredMarkers(["from", "--from", "--start-point"], in: tokens) {
                arguments["startPoint"] = startPoint
            }
            return arguments
        }

        if lower.contains("switch") || lower.contains("checkout") {
            guard let branch = tokenAfterPreferredMarkers(["branch", "to", "checkout", "switch"], in: tokens) else {
                return nil
            }
            return ["branch": branch]
        }
        return nil
    }

    private static func tokenAfterPreferredMarkers(_ markers: [String], in tokens: [String]) -> String? {
        for marker in markers {
            for (index, token) in tokens.enumerated() where token.lowercased() == marker {
                guard index + 1 < tokens.count else { continue }
                let candidate = tokens[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(CharacterSet(charactersIn: "`\"'")))
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }
        return nil
    }
}
