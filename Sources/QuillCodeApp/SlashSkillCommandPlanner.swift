import Foundation

/// Turns the `/skill name` registry command into an agent prompt that loads and runs the named
/// skill. Skills are a dynamic, per-project set, so rather than a bespoke picker they register as a
/// single one-line entry in the slash catalog (issue #879): `/skill <name>` becomes a normal agent
/// turn instructing the agent to load the skill via `host.skill.load` and follow it. Because it
/// resolves to an ordinary agent prompt, it runs through the SAME send path as any typed message —
/// no separate, easily-dead dispatch branch.
enum SlashSkillCommandPlanner {
    /// The command names that trigger skill loading.
    static func supports(_ name: String) -> Bool {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "skill", "skills":
            return true
        default:
            return false
        }
    }

    /// The agent prompt for `/skill <name>`, or nil when no skill name was given (so the caller can
    /// surface usage instead of sending an empty, useless turn). The skill name is sanitized to a
    /// bare token — `host.skill.load` rejects paths — and embedded verbatim so the agent loads the
    /// exact skill the user named.
    static func agentPrompt(for argument: String) -> String? {
        let name = bareSkillName(from: argument)
        guard !name.isEmpty else { return nil }
        return "Load the `\(name)` skill with host.skill.load, then follow its instructions."
    }

    static let usage = "Usage: /skill name (for example /skill code-review)"

    /// Reduces the argument to the first whitespace-delimited token with path separators stripped,
    /// matching `host.skill.load`'s "bare name, no slashes or .." contract. Returns "" when nothing
    /// usable remains.
    static func bareSkillName(from argument: String) -> String {
        let firstToken = argument
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? ""
        return firstToken
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "..", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
