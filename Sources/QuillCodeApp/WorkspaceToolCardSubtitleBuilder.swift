import Foundation
import QuillCodeCore

enum WorkspaceToolCardSubtitleBuilder {
    private static let detailLimit = 72

    static func subtitle(stateLabel: String, toolName: String, inputJSON: String?) -> String {
        guard let detail = detail(toolName: toolName, inputJSON: inputJSON) else {
            return stateLabel
        }
        return "\(stateLabel) · \(detail)"
    }

    private static func detail(toolName: String, inputJSON: String?) -> String? {
        guard let inputJSON, let arguments = try? ToolArguments(inputJSON) else {
            return nil
        }

        switch toolName {
        case "host.shell.run":
            return sanitized(arguments.string("cmd"))
        case "host.file.read", "host.file.write",
             "host.git.stage", "host.git.restore",
             "host.git.stage_hunk", "host.git.restore_hunk",
             "host.git.pr.diff", "host.git.pr.review_comment",
             "host.git.worktree.remove":
            return sanitized(arguments.string("path"))
        case "host.apply_patch":
            return "patch"
        case "host.git.status":
            return nil
        case "host.git.diff":
            return arguments.bool("staged") == true ? "staged diff" : "working tree"
        case "host.git.commit":
            return sanitized(arguments.string("message"))
        case "host.git.push":
            return pushDetail(arguments)
        case "host.git.pr.create":
            return sanitized(arguments.string("title"))
        case "host.git.pr.view", "host.git.pr.checks", "host.git.pr.checkout",
             "host.git.pr.reviewers", "host.git.pr.labels", "host.git.pr.comment",
             "host.git.pr.review", "host.git.pr.review_reply", "host.git.pr.review_threads",
             "host.git.pr.merge":
            return sanitized(arguments.string("selector"))
        case "host.git.pr.review_thread":
            return sanitized(arguments.string("action")) ?? sanitized(arguments.string("threadId"))
        case "host.git.worktree.create":
            return sanitized(arguments.string("branch")) ?? sanitized(arguments.string("path"))
        case "host.plan.update":
            return "plan"
        case "host.handoff.update":
            return "handoff"
        case "host.subagents.update":
            return "subagents"
        case "host.browser.open":
            return sanitized(arguments.string("url"))
        case "host.memory.remember":
            return sanitized(arguments.string("content"))
        case "host.mcp.call":
            return sanitized(arguments.string("toolName"))
        case "host.mcp.resource.read":
            return sanitized(arguments.string("resourceName"))
                ?? sanitized(arguments.string("name"))
                ?? sanitized(arguments.string("resourceURI"))
                ?? sanitized(arguments.string("uri"))
        case "host.mcp.prompt.get":
            return sanitized(arguments.string("promptName")) ?? sanitized(arguments.string("name"))
        case "host.computer.click", "host.computer.move":
            return coordinateDetail(arguments, "x", "y")
        case "host.computer.scroll":
            return coordinateDetail(arguments, "dx", "dy")
        case "host.computer.type":
            return sanitized(arguments.string("text"))
        case "host.computer.key":
            return sanitized(arguments.string("key"))
        default:
            return nil
        }
    }

    private static func coordinateDetail(_ arguments: ToolArguments, _ xKey: String, _ yKey: String) -> String? {
        let x = sanitized(arguments.string(xKey))
        let y = sanitized(arguments.string(yKey))
        switch (x, y) {
        case (.some(let x), .some(let y)):
            return "\(x), \(y)"
        case (.some(let x), nil):
            return x
        case (nil, .some(let y)):
            return y
        case (nil, nil):
            return nil
        }
    }

    private static func pushDetail(_ arguments: ToolArguments) -> String? {
        let remote = sanitized(arguments.string("remote"))
        let branch = sanitized(arguments.string("branch"))
        switch (remote, branch) {
        case (.some(let remote), .some(let branch)):
            return "\(remote)/\(branch)"
        case (.some(let remote), nil):
            return remote
        case (nil, .some(let branch)):
            return branch
        case (nil, nil):
            return nil
        }
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > detailLimit else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: detailLimit)
        return String(collapsed[..<end]) + "..."
    }
}
