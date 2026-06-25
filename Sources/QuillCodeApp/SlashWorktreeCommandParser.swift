import Foundation

enum SlashWorktreeCommandParser {
    static func parse(_ argument: String) -> SlashCommand {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .workspaceCommand("git-worktree-list")
        }
        guard let tokens = tokenize(trimmed) else {
            return .invalid("Unclosed quote in worktree command.")
        }
        guard let action = tokens.first?.lowercased() else {
            return .workspaceCommand("git-worktree-list")
        }

        switch action {
        case "list", "ls":
            guard tokens.count == 1 else {
                return .invalid("Usage: /worktree list.")
            }
            return .workspaceCommand("git-worktree-list")
        case "create", "add", "new":
            return parseCreate(Array(tokens.dropFirst()))
        case "open", "switch":
            return parseOpen(Array(tokens.dropFirst()))
        case "remove", "rm", "delete":
            return parseRemove(Array(tokens.dropFirst()))
        case "prune", "cleanup":
            return parsePrune(Array(tokens.dropFirst()))
        default:
            return .invalid("Unknown worktree action '\(action)'. Try /worktree create, /worktree open, /worktree remove, /worktree prune, or /worktree list.")
        }
    }

    private static func parseCreate(_ tokens: [String]) -> SlashCommand {
        var path = ""
        var branch = ""
        var base = ""
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "--branch", "-b":
                guard let value = value(after: token, in: tokens, index: &index) else {
                    return .invalid("Missing branch after \(token).")
                }
                branch = value
            case "--base", "--from":
                guard let value = value(after: token, in: tokens, index: &index) else {
                    return .invalid("Missing base ref after \(token).")
                }
                base = value
            default:
                if token.hasPrefix("-") {
                    return .invalid("Unknown worktree create option '\(token)'.")
                }
                guard path.isEmpty else {
                    return .invalid("Too many worktree create paths. Quote paths with spaces.")
                }
                path = token
            }
            index += 1
        }

        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalid("Missing worktree path. Try /worktree create ../feature --branch feature/name.")
        }
        return .worktreeCreate(WorkspaceWorktreeCreateRequest(path: path, branch: branch, base: base))
    }

    private static func parseOpen(_ tokens: [String]) -> SlashCommand {
        parseSinglePath(
            tokens,
            action: "open",
            missing: "Missing worktree path. Try /worktree open ../feature.",
            extra: "Too many worktree open paths. Quote paths with spaces."
        ) { .worktreeOpen(WorkspaceWorktreeOpenRequest(path: $0)) }
    }

    private static func parseRemove(_ tokens: [String]) -> SlashCommand {
        var path = ""
        var force = false
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            switch token {
            case "--force", "-f":
                force = true
            default:
                if token.hasPrefix("-") {
                    return .invalid("Unknown worktree remove option '\(token)'.")
                }
                guard path.isEmpty else {
                    return .invalid("Too many worktree remove paths. Quote paths with spaces.")
                }
                path = token
            }
            index += 1
        }

        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalid("Missing worktree path. Try /worktree remove ../feature.")
        }
        return .worktreeRemove(WorkspaceWorktreeRemoveRequest(path: path, force: force))
    }

    private static func parsePrune(_ tokens: [String]) -> SlashCommand {
        var dryRun = false
        var verbose = false

        for token in tokens {
            switch token {
            case "--dry-run", "-n":
                dryRun = true
            case "--verbose", "-v":
                verbose = true
            default:
                if token.hasPrefix("-") {
                    return .invalid("Unknown worktree prune option '\(token)'.")
                }
                return .invalid("Worktree prune does not take a path. Try /worktree prune --dry-run.")
            }
        }

        return .worktreePrune(WorkspaceWorktreePruneRequest(dryRun: dryRun, verbose: verbose))
    }

    private static func parseSinglePath(
        _ tokens: [String],
        action: String,
        missing: String,
        extra: String,
        command: (String) -> SlashCommand
    ) -> SlashCommand {
        guard let path = tokens.first, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .invalid(missing)
        }
        guard !path.hasPrefix("-") else {
            return .invalid("Unknown worktree \(action) option '\(path)'.")
        }
        guard tokens.count == 1 else {
            return .invalid(extra)
        }
        return command(path)
    }

    private static func value(after flag: String, in tokens: [String], index: inout Int) -> String? {
        let valueIndex = index + 1
        guard valueIndex < tokens.count, !tokens[valueIndex].hasPrefix("-") else {
            return nil
        }
        index = valueIndex
        return tokens[valueIndex]
    }

    private static func tokenize(_ text: String) -> [String]? {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in text {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" {
                escaping = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character.isWhitespace {
                appendToken(&tokens, current: &current)
            } else {
                current.append(character)
            }
        }

        if escaping {
            current.append("\\")
        }
        guard quote == nil else { return nil }
        appendToken(&tokens, current: &current)
        return tokens
    }

    private static func appendToken(_ tokens: inout [String], current: inout String) {
        guard !current.isEmpty else { return }
        tokens.append(current)
        current = ""
    }
}
