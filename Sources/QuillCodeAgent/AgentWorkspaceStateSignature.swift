import Foundation
import QuillCodeTools

extension AgentRunner {
    /// The default workspace-state signature: a git hash over status + diff, so "nothing changed" is
    /// judged by the actual tree, not by what the tools claimed. A non-git workspace degrades to a
    /// constant without launching a shell.
    static func defaultWorkspaceStateSignature(_ root: URL) -> String {
        guard AgentWorkspaceStateSignature.hasGitMetadata(atOrAbove: root) else {
            return "no-git"
        }
        return AgentWorkspaceStateSignature.gitStatusDiffHash(root: root)
    }
}

private enum AgentWorkspaceStateSignature {
    static func hasGitMetadata(atOrAbove root: URL) -> Bool {
        let fileManager = FileManager.default
        var current = root.standardizedFileURL

        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return true
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { return false }
            current = parent
        }
    }

    static func gitStatusDiffHash(root: URL) -> String {
        let command = "{ git status --porcelain; git diff HEAD; } 2>/dev/null "
            + "| git hash-object --stdin 2>/dev/null || echo no-git"
        let result = ShellToolExecutor().run(.init(
            command: command,
            cwd: root,
            timeoutSeconds: 10
        ))
        let signature = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return signature.isEmpty ? "no-git" : signature
    }
}
