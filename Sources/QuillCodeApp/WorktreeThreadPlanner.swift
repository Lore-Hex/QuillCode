import Foundation
import QuillCodeCore

/// Plans the git worktree for a new "Worktree" thread (the Codex Local-vs-Worktree choice): a
/// collision-free branch off the current base and a sibling directory to check it out in. Pure so the
/// naming is deterministic and unit-testable; the model runs the resulting create request.
enum WorktreeThreadPlanner {
    static func plan(
        projectRoot: URL,
        baseBranch: String,
        name: String?,
        existingBranches: [String]
    ) -> WorkspaceWorktreeCreateRequest {
        let slug = slug(from: name) ?? "work"
        let branch = uniqueBranch(preferred: "quill/\(slug)", taken: Set(existingBranches))
        // Sibling of the project root, named "<project>-<branch-leaf>", so worktrees sit next to the
        // repo (the worktree tool already enforces sibling-in-parent).
        let leaf = branch.split(separator: "/").last.map(String.init) ?? slug
        let dirName = "\(projectRoot.lastPathComponent)-\(leaf)"
        let path = projectRoot.deletingLastPathComponent().appendingPathComponent(dirName).path
        return WorkspaceWorktreeCreateRequest(path: path, branch: branch, base: baseBranch)
    }

    /// Lowercased, hyphen-separated, alphanumerics-and-hyphens only; nil when nothing usable remains.
    static func slug(from name: String?) -> String? {
        guard let name else { return nil }
        let lowered = name.lowercased()
        var out = ""
        var lastWasHyphen = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                out.append("-")
                lastWasHyphen = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? nil : String(trimmed.prefix(40))
    }

    /// `preferred`, else `preferred-2`, `-3`, … until it's not in `taken`.
    static func uniqueBranch(preferred: String, taken: Set<String>) -> String {
        guard taken.contains(preferred) else { return preferred }
        var n = 2
        while taken.contains("\(preferred)-\(n)") { n += 1 }
        return "\(preferred)-\(n)"
    }
}
