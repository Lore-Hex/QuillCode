import QuillCodeCore

enum SlashBranchCommandParser {
    static func parse(_ argument: String) -> SlashCommand {
        let tokens = argument
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let subcommand = tokens.first?.lowercased() else {
            return .workspaceCommand("git-branch-list")
        }

        let rest = Array(tokens.dropFirst())
        switch subcommand {
        case "list", "ls", "branches":
            return list(rest)
        case "switch", "checkout", "co":
            return switchBranch(rest)
        case "create", "new":
            return createBranch(rest)
        default:
            guard rest.isEmpty else {
                return .invalid("Unknown branch command. Try /branch list, /branch switch name, or /branch create name.")
            }
            return branchSwitchCall(branch: subcommand)
        }
    }

    private static func list(_ tokens: [String]) -> SlashCommand {
        var includeRemote = true
        for token in tokens {
            switch token.lowercased() {
            case "--local":
                includeRemote = false
            case "--all", "--remote", "--remotes":
                includeRemote = true
            default:
                return .invalid("Unknown branch list option '\(token)'. Try /branch list [--local].")
            }
        }
        guard includeRemote else {
            return .toolCall(ToolCall(
                name: ToolDefinition.gitBranchList.name,
                argumentsJSON: ToolArguments.json(["includeRemote": false])
            ))
        }
        return .workspaceCommand("git-branch-list")
    }

    private static func switchBranch(_ tokens: [String]) -> SlashCommand {
        guard let branch = tokens.first else {
            return .invalid("Missing branch name. Try /branch switch feature/name.")
        }
        guard tokens.count == 1 else {
            return .invalid("Too many branch switch arguments. Branch names cannot contain spaces.")
        }
        return branchSwitchCall(branch: branch)
    }

    private static func createBranch(_ tokens: [String]) -> SlashCommand {
        guard let branch = tokens.first else {
            return .invalid("Missing branch name. Try /branch create feature/name --from main.")
        }
        var startPoint: String?
        var index = 1
        while index < tokens.count {
            let token = tokens[index].lowercased()
            switch token {
            case "--from", "--start-point":
                guard index + 1 < tokens.count else {
                    return .invalid("Missing start point after \(tokens[index]).")
                }
                startPoint = tokens[index + 1]
                index += 2
            default:
                if startPoint == nil {
                    startPoint = tokens[index]
                    index += 1
                } else {
                    return .invalid("Unexpected branch create argument '\(tokens[index])'.")
                }
            }
        }

        var arguments: [String: Any] = [
            "branch": branch,
            "create": true
        ]
        if let startPoint {
            arguments["startPoint"] = startPoint
        }
        return .toolCall(ToolCall(
            name: ToolDefinition.gitBranchSwitch.name,
            argumentsJSON: ToolArguments.json(arguments)
        ))
    }

    private static func branchSwitchCall(branch: String) -> SlashCommand {
        .toolCall(ToolCall(
            name: ToolDefinition.gitBranchSwitch.name,
            argumentsJSON: ToolArguments.json(["branch": branch])
        ))
    }
}
