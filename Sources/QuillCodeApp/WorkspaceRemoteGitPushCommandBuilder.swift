import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitPushCommandBuilder {
    static func command(arguments args: ToolArguments) throws -> String {
        try command(
            remote: args.string("remote"),
            branch: args.string("branch"),
            setUpstream: args.bool("setUpstream") ?? false
        )
    }

    private static func command(
        remote: String?,
        branch: String?,
        setUpstream: Bool
    ) throws -> String {
        let remoteName = try GitInputValidator.safeName(
            GitInputValidator.trimmedNonEmpty(remote) ?? "origin"
        )
        let upstreamArguments = setUpstream ? "-u " : ""
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            let branchName = try GitInputValidator.safeName(branch)
            return "git push \(upstreamArguments)\(quoted(remoteName)) \(quoted(branchName))"
        }

        let invalidBranchMessage = quoted(String(describing: GitToolError.invalidGitName("$branch")))
        let invalidBranchPattern = "*[!\(GitInputValidator.safeNameCharacters)]*"
        return [
            "branch=$(git branch --show-current)",
            "test -n \"$branch\" || { printf '%s\\n' \(quoted(String(describing: GitToolError.noCurrentBranch))) >&2; exit 1; }",
            "case \"$branch\" in -*|*..*|\(invalidBranchPattern)) printf '%s\\n' \(invalidBranchMessage) >&2; exit 1;; esac",
            "git push \(upstreamArguments)\(quoted(remoteName)) \"$branch\""
        ].joined(separator: " && ")
    }

    private static func quoted(_ value: String) -> String {
        WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(value)
    }
}
