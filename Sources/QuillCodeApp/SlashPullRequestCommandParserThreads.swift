import Foundation
import QuillCodeTools

extension SlashPullRequestCommandParser {
    static func parseReviewThread(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let rawAction = parts.first?.lowercased(),
              parts.count > 1
        else {
            return .invalid("Usage: /pr review-thread resolve threadId or /pr review-thread unresolve threadId")
        }
        switch rawAction.replacingOccurrences(of: "-", with: "_") {
        case "resolve", "resolved":
            return parseReviewThreadID(String(parts[1]), action: "resolve")
        case "unresolve", "unresolved", "reopen", "open":
            return parseReviewThreadID(String(parts[1]), action: "unresolve")
        default:
            return .invalid("Unknown pull request review thread action '\(rawAction)'. Use resolve or unresolve.")
        }
    }

    static func parseReviewThreadID(_ argument: String, action: String) -> SlashCommand {
        let threadID = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadID.isEmpty else {
            return .invalid("Usage: /pr \(action)-thread threadId")
        }
        return pullRequestTool(
            .gitPullRequestReviewThread,
            arguments: ["threadId": threadID, "action": action]
        )
    }
}
