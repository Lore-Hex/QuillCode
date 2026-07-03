import QuillCodeCore

enum SlashGitCommandParser {
    static func parse(_ argument: String) -> SlashCommand {
        let tokens = argument
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let subcommand = tokens.first?.lowercased() else {
            return .workspaceCommand("git-status")
        }

        let rest = Array(tokens.dropFirst())
        switch subcommand {
        case "status", "st":
            return .workspaceCommand("git-status")
        case "diff", "changes":
            return .workspaceCommand("git-diff")
        case "fetch":
            return fetch(rest)
        case "pull", "sync":
            return pull(rest)
        default:
            return .invalid("Unknown git command. Try /git status, /git fetch, or /git pull.")
        }
    }

    private static func fetch(_ tokens: [String]) -> SlashCommand {
        var remote = ""
        var prune = false
        for token in tokens {
            switch token.lowercased() {
            case "--prune", "-p":
                prune = true
            default:
                if remote.isEmpty {
                    remote = token
                } else {
                    return .invalid("Unexpected git fetch argument '\(token)'. Try /git fetch [remote] [--prune].")
                }
            }
        }

        var arguments: [String: Any] = [:]
        if !remote.isEmpty {
            arguments["remote"] = remote
        }
        if prune {
            arguments["prune"] = true
        }
        return .toolCall(ToolCall(
            name: ToolDefinition.gitFetch.name,
            argumentsJSON: ToolArguments.json(arguments)
        ))
    }

    private static func pull(_ tokens: [String]) -> SlashCommand {
        var remote = ""
        var branch = ""
        var ffOnly = true
        for token in tokens {
            switch token.lowercased() {
            case "--ff-only":
                ffOnly = true
            case "--no-ff-only", "--merge":
                ffOnly = false
            default:
                if remote.isEmpty {
                    remote = token
                } else if branch.isEmpty {
                    branch = token
                } else {
                    return .invalid("Unexpected git pull argument '\(token)'. Try /git pull [remote] [branch].")
                }
            }
        }

        if !ffOnly, remote.isEmpty, branch.isEmpty {
            return .invalid("Non-fast-forward git pull needs a remote or branch. Try /git pull origin main --merge.")
        }

        var arguments: [String: Any] = ["ffOnly": ffOnly]
        if !remote.isEmpty {
            arguments["remote"] = remote
        }
        if !branch.isEmpty {
            arguments["branch"] = branch
        }
        return .toolCall(ToolCall(
            name: ToolDefinition.gitPull.name,
            argumentsJSON: ToolArguments.json(arguments)
        ))
    }
}
