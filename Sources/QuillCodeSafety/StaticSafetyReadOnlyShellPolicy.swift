import Foundation
import QuillCodeCore

enum StaticSafetyReadOnlyShellPolicy {
    static func intentMatches(request: StaticSafetyRequest, context: SafetyContext) -> Bool {
        guard context.toolCall.name.contains("shell.run"),
              let command = shellCommand(from: context.toolCall)
        else {
            return false
        }
        let normalized = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard isSingleReadCommand(normalized) else {
            return false
        }

        if isPwdCommand(normalized) {
            return isCurrentDirectoryRequest(request)
        }
        if isLsCommand(normalized) {
            return isFileListingRequest(request)
        }
        if isGitStatusCommand(normalized) {
            return isGitStatusRequest(request)
        }
        return false
    }

    private static func shellCommand(from call: ToolCall) -> String? {
        try? ToolArguments(call.argumentsJSON).requiredString("cmd")
    }

    private static func isSingleReadCommand(_ command: String) -> Bool {
        [";", "&&", "||", "|", "`", "$(", ">", "<"].allSatisfy { !command.contains($0) }
    }

    private static func isPwdCommand(_ command: String) -> Bool {
        command == "pwd" || command == "/bin/pwd" || command == "command pwd"
    }

    private static func isLsCommand(_ command: String) -> Bool {
        let parts = command.split(separator: " ").map(String.init)
        guard parts.first == "ls", parts.count <= 3 else {
            return false
        }
        return parts.dropFirst().allSatisfy { part in
            if part.hasPrefix("-") {
                return part.dropFirst().allSatisfy { "1aAlLh".contains($0) }
            }
            return isSafeRelativePath(part)
        }
    }

    private static func isGitStatusCommand(_ command: String) -> Bool {
        let parts = command.split(separator: " ").map(String.init)
        guard parts.count >= 2,
              parts[0] == "git",
              parts[1] == "status"
        else {
            return false
        }
        return parts.dropFirst(2).allSatisfy { part in
            part == "--short" || part == "-s" || part == "--porcelain" || part == "--branch" || part == "-b"
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.hasPrefix("~")
            && !path.contains("..")
    }

    private static func isCurrentDirectoryRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "current directory",
            "working directory",
            "current folder",
            "workspace path",
            "where am i",
            "pwd"
        ])
    }

    private static func isFileListingRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(["list files", "list the files", "show files", "show the files"])
            || ((request.containsToken("files") || request.containsToken("directory") || request.containsToken("folder"))
                && (request.containsToken("list") || request.containsToken("show") || request.containsToken("what")))
    }

    private static func isGitStatusRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "git status",
            "repo status",
            "repository status",
            "working tree status",
            "working directory status"
        ])
            || (request.containsToken("status") && (request.containsToken("git") || request.containsToken("repo")))
    }
}
