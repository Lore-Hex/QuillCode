import Foundation
import QuillCodeCore

struct WorktreeThreadPlan: Sendable, Hashable {
    var request: WorkspaceWorktreeCreateRequest
    var title: String
}

/// Plans a Codex-style managed worktree for a new Worktree thread. Managed task worktrees start
/// detached, so a short unique path component provides isolation without creating repository branches.
enum WorktreeThreadPlanner {
    static func plan(
        projectRoot: URL,
        baseBranch: String,
        name: String?,
        identifier: String = UUID().uuidString
    ) -> WorktreeThreadPlan {
        let slug = slug(from: name) ?? "work"
        let suffix = identifier
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(8)
        let safeSuffix = suffix.isEmpty ? "managed" : String(suffix)
        let dirName = "\(projectRoot.lastPathComponent)-\(slug)-\(safeSuffix)"
        let path = projectRoot.deletingLastPathComponent().appendingPathComponent(dirName).path
        return WorktreeThreadPlan(
            request: WorkspaceWorktreeCreateRequest(
                path: path,
                base: baseBranch,
                managed: true
            ),
            title: "Worktree: \(slug)"
        )
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
}
