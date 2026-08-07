import Foundation
import QuillCodeCore

/// F24 — the outside-workspace shell gate.
///
/// Live incident (2026-07-30, coworker row #104): a `quill-code exec --sandbox workspace-write`
/// run in Auto mode executed
///
///     find ~/Documents ~/Desktop -type f -exec grep -H "Project Northstar" {} \; 2>/dev/null || true
///
/// over the REAL home Documents/Desktop folders and echoed personal filenames into the run output.
/// The file tools are clamped to the workspace (`hostToolAccessScope = workspaceOnly`), but
/// `host.shell.run` escapes that clamp. The static shell policies correctly did NOT approve
/// (`StaticSafetyShellCommandSafety.isSafeArgument` rejects `~`/absolute arguments) — but "not
/// statically approved" only routed the call to the MODEL reviewer, which approved it; and in
/// headless exec the autonomous override would have converted a `.clarify` to `.approve` anyway.
/// Nothing in the pipeline treated "shell reaches outside the workspace" as something only a HUMAN
/// (or the user's own words) may authorize.
///
/// This policy is that treatment. A shell command that references a path outside the workspace root
/// (`~` paths, `$HOME`/`${HOME}` expansions, absolute paths not under the workspace, or `..`
/// traversal that escapes it) is never silently approvable in Auto mode:
///   - the static reviewer surfaces `.clarify` (interactive runs show approval_required to the human),
///   - `AutoSafetyReviewer` returns that `.clarify` WITHOUT consulting the model reviewer,
///   - `AutonomousApprovalSafetyReviewer` (headless workspace-write) denies it honestly instead of
///     waiving the clarify.
///
/// One exception, mirroring the F10 user-typed-URL rule: the user's message naming the exact path
/// verbatim authorizes it — they named the target, they own the reach. Hard-deny floors always run
/// first and are never weakened: `cat ~/.ssh/id_rsa` stays DENY, it does not soften to clarify.
enum StaticSafetyOutsideWorkspaceShellPolicy {
    struct Violation: Equatable, Sendable {
        /// The offending path references as written in the command, first-seen order, de-duplicated.
        var offendingPaths: [String]
        /// Approval-surface message for the interactive `.clarify`.
        var rationale: String
    }

    /// Write-only/interactive device endpoints every shell pipeline uses (`2>/dev/null`); they
    /// carry no personal data, so they are not treated as an escape.
    private static let harmlessDevicePaths: Set<String> = [
        "/dev/null", "/dev/stdin", "/dev/stdout", "/dev/stderr", "/dev/tty",
    ]

    /// Standard system executable directories. `/usr/bin/python3 x.py` reaches nothing that bare
    /// `python3 x.py` (via PATH) cannot, so an absolute path DIRECTLY inside one of these is not an
    /// escape. Only the binary's own directory qualifies — `/usr/bin/../../etc/passwd` has a `..`
    /// segment and never matches.
    private static let systemExecutableDirectories: Set<String> = [
        "/usr/bin", "/bin", "/usr/sbin", "/sbin", "/usr/local/bin", "/opt/homebrew/bin",
    ]

    /// Executables whose path arguments name a target WITHOUT exposing its contents or listing:
    /// `df -h /` reports mount-point statistics and cannot read a byte of any file. Their segments
    /// skip the gate (the long-standing "How much hd?" diagnostic approval). Deliberately tiny —
    /// `du`/`ls`/`stat` reveal names, sizes, or per-entry metadata and stay gated. The exemption is
    /// void when the command contains substitution (`$(`/backtick), which can smuggle any read.
    private static let contentBlindExecutables: Set<String> = ["df"]

    /// A bare `/` inside one of these executable-language heredocs is an operator, not a shell
    /// path argument. Keep scanning every other token in the body so explicit path spellings are
    /// still gated, but do not turn ordinary expressions such as `cash / burn` into root access.
    private static let executableLanguageHeredocHeads: Set<String> = [
        "node", "perl", "python", "python3", "ruby",
    ]

    /// The violation for this tool call, or nil when the gate does not apply: not a shell command,
    /// no out-of-workspace path reference, or every offending path is named verbatim in the user's
    /// message. Purely syntactic — never touches the filesystem (`homeDirectoryPath` is injectable
    /// for tests).
    static func violation(
        _ context: SafetyContext,
        homeDirectoryPath: String = NSHomeDirectory()
    ) -> Violation? {
        guard context.toolCall.name.contains("shell.run"),
              let command = try? ToolArguments(context.toolCall.argumentsJSON).requiredString("cmd")
        else {
            return nil
        }
        let home = normalizedDirectoryPath(homeDirectoryPath)
        let workspaceRoot = context.workspaceRoot.map { normalizedDirectoryPath($0.path) }

        var offending: [String] = []
        let pathScanningCommand = neutralizingExecutableHeredocOperators(in: command)
        let folded = StaticSafetyPolicy.collapseWhitespace(pathScanningCommand, foldNewlines: true)
        let substitutionFree = !folded.contains("$(") && !folded.contains("`")
        // Segments are split on any run of `;`/`&`/`|` so a content-blind head only ever vouches
        // for its OWN arguments — `df -h / && cat /etc/passwd` still gates the `cat` segment.
        for segment in folded.split(whereSeparator: { $0 == ";" || $0 == "&" || $0 == "|" }) {
            let tokens = segment.split(separator: " ").map { cleaned(String($0)) }.filter { !$0.isEmpty }
            if substitutionFree,
               let head = tokens.first,
               contentBlindExecutables.contains(StaticSafetyShellCommandSafety.basename(head)) {
                continue
            }
            for token in tokens {
                for candidate in pathCandidates(in: token) {
                    guard let escape = escapingPath(
                        candidate,
                        home: home,
                        workspaceRoot: workspaceRoot
                    ) else { continue }
                    if isNamedVerbatim(
                        written: candidate,
                        expanded: escape,
                        home: home,
                        in: context.userMessage
                    ) { continue }
                    if !offending.contains(candidate) {
                        offending.append(candidate)
                    }
                }
            }
        }
        guard !offending.isEmpty else { return nil }

        let listed = offending.prefix(4).joined(separator: ", ")
        return Violation(
            offendingPaths: offending,
            rationale: "This shell command references paths outside the workspace (\(listed)). "
                + "Auto mode requires explicit approval for out-of-workspace paths: approve it here, "
                + "or ask again naming the exact path (e.g. \"\(offending[0])\") to authorize it."
        )
    }

    // MARK: - Token cleanup

    /// Shell tokenization and executable-language tokenization disagree about a standalone `/`.
    /// Preserve the command and heredoc body for the normal safety scan, replacing only bare slash
    /// tokens in heredocs launched by known expression languages. Shell heredocs remain untouched.
    private static func neutralizingExecutableHeredocOperators(in command: String) -> String {
        var activeDelimiter: String?
        var output: [String] = []

        for lineSlice in command.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(lineSlice)
            if let delimiter = activeDelimiter {
                if line.trimmingCharacters(in: .whitespaces) == delimiter {
                    output.append(line)
                    activeDelimiter = nil
                } else {
                    output.append(neutralizingBareSlashTokens(in: line))
                }
                continue
            }

            output.append(line)
            activeDelimiter = executableLanguageHeredocDelimiter(in: line)
        }
        return output.joined(separator: "\n")
    }

    private static func executableLanguageHeredocDelimiter(in line: String) -> String? {
        guard let marker = line.range(of: "<<") else { return nil }
        let commandPrefix = line[..<marker.lowerBound]
        let commandTokens = commandPrefix.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard commandTokens.contains(where: {
            executableLanguageHeredocHeads.contains(
                StaticSafetyShellCommandSafety.basename(String($0))
            )
        }) else { return nil }

        var suffix = line[marker.upperBound...]
        if suffix.first == "-" { suffix = suffix.dropFirst() }
        suffix = suffix.drop(while: { $0 == " " || $0 == "\t" })
        guard let rawDelimiter = suffix.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
        else { return nil }
        let delimiter = rawDelimiter.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        guard !delimiter.isEmpty,
              delimiter.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { return nil }
        return delimiter
    }

    private static func neutralizingBareSlashTokens(in line: String) -> String {
        let characters = Array(line)
        var output = ""
        output.reserveCapacity(line.count)
        for index in characters.indices {
            let character = characters[index]
            guard character == "/" else {
                output.append(character)
                continue
            }
            let previousIsBoundary = index == characters.startIndex
                || characters[characters.index(before: index)].isWhitespace
            let nextIndex = characters.index(after: index)
            let nextIsBoundary = nextIndex == characters.endIndex || characters[nextIndex].isWhitespace
            output += previousIsBoundary && nextIsBoundary
                ? "__quillcode_arithmetic_slash__"
                : "/"
        }
        return output
    }

    /// Strips the shell syntax wrapped around a path spelling: quotes anywhere in the token
    /// (`"~/My"` and `"$HOME"/x` both unwrap), a redirection prefix (`2>/dev/null`, `&>/tmp/x`),
    /// a leading `(` or `$( `, and trailing sentence/subshell punctuation.
    private static func cleaned(_ rawToken: String) -> String {
        var token = rawToken
        token.removeAll { $0 == "\"" || $0 == "'" }
        token = strippingRedirectPrefix(token)
        while let first = token.first, first == "(" {
            token.removeFirst()
        }
        while let last = token.last, ");,:!?".contains(last) {
            token.removeLast()
        }
        return token
    }

    /// `2>/dev/null` → `/dev/null`, `&>>~/log` → `~/log`; a token with no redirect operator is
    /// returned unchanged (so `2fast` keeps its digit).
    private static func strippingRedirectPrefix(_ token: String) -> String {
        var index = token.startIndex
        while index < token.endIndex, token[index].isNumber {
            index = token.index(after: index)
        }
        var sawRedirect = false
        while index < token.endIndex, token[index] == ">" || token[index] == "<" || token[index] == "&" {
            sawRedirect = true
            index = token.index(after: index)
        }
        return sawRedirect ? String(token[index...]) : token
    }

    /// The path spellings a token can carry: the token itself, and — for `--flag=/path` /
    /// `VAR=~/path` forms — the value after the first `=`.
    private static func pathCandidates(in token: String) -> [String] {
        var candidates: [String] = []
        if isPathSpelling(token) {
            candidates.append(token)
        } else if let equals = token.firstIndex(of: "=") {
            let value = String(token[token.index(after: equals)...])
            if isPathSpelling(value) {
                candidates.append(value)
            }
        }
        return candidates
    }

    private static func isPathSpelling(_ token: String) -> Bool {
        token.hasPrefix("~") || token.hasPrefix("/") || hasHomeVariablePrefix(token)
            || hasEscapingTraversalSegment(token)
    }

    /// `$HOME` / `${HOME}` followed by `/` or end-of-token. The boundary check keeps
    /// `$HOMEBREW_PREFIX/bin` from false-positiving.
    private static func hasHomeVariablePrefix(_ token: String) -> Bool {
        for prefix in ["$HOME", "${HOME}"] where token.hasPrefix(prefix) {
            let rest = token.dropFirst(prefix.count)
            if rest.isEmpty || rest.hasPrefix("/") { return true }
        }
        return false
    }

    /// A relative spelling with a `..` path SEGMENT (`../x`, `a/../b`) — the same segment rule as
    /// `StaticSafetyShellCommandSafety.isSafeArgument`, so `go test ./...` and `git log a..b` pass.
    private static func hasEscapingTraversalSegment(_ token: String) -> Bool {
        token.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    // MARK: - Escape resolution

    /// The lexically-resolved absolute path when `candidate` reaches outside the workspace root,
    /// nil when it stays inside (or is a harmless device / system-binary reference). Unknowable
    /// targets (another user's `~name`, a `..` spelling with no workspace root) resolve to the
    /// spelling itself: conservatively outside.
    private static func escapingPath(
        _ candidate: String,
        home: String,
        workspaceRoot: String?
    ) -> String? {
        let expanded: String
        if candidate == "~" {
            expanded = home
        } else if candidate.hasPrefix("~/") {
            expanded = home + candidate.dropFirst(1)
        } else if candidate.hasPrefix("~") {
            // `~otheruser/...` — no portable expansion; treat as outside.
            return candidate
        } else if hasHomeVariablePrefix(candidate) {
            let suffix = candidate.hasPrefix("${HOME}")
                ? candidate.dropFirst("${HOME}".count)
                : candidate.dropFirst("$HOME".count)
            expanded = home + suffix
        } else if candidate.hasPrefix("/") {
            expanded = candidate
        } else {
            // Relative `..` traversal: resolve against the workspace root when known.
            guard let workspaceRoot else { return candidate }
            expanded = workspaceRoot + "/" + candidate
        }

        let resolved = URL(fileURLWithPath: expanded).standardized.path
        if harmlessDevicePaths.contains(resolved) { return nil }
        if !hasEscapingTraversalSegment(candidate),
           systemExecutableDirectories.contains(parentDirectory(of: resolved)) {
            return nil
        }
        if let workspaceRoot, isWithin(resolved, root: workspaceRoot) { return nil }
        return resolved
    }

    private static func parentDirectory(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    private static func normalizedDirectoryPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path
    }

    private static func isWithin(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    // MARK: - The verbatim-path exception (mirrors the F10 user-typed-URL rule)

    /// Whether the user's message names this exact path — any equivalent spelling: as written in
    /// the command (`~/Documents`), fully expanded (`/Users/x/Documents`), or the `~` spelling of
    /// the expanded path when it sits under home. Compared case-insensitively with whitespace
    /// collapsed, and the occurrence must END at a path boundary: "back up ~/Documents" vouches
    /// for `~/Documents`, but "~/Documents/old" does NOT — naming a deeper path never authorizes
    /// reading its parent. Single-character spellings other than `~` (notably `/`) are too weak to
    /// vouch.
    private static func isNamedVerbatim(
        written: String,
        expanded: String,
        home: String,
        in userMessage: String
    ) -> Bool {
        let haystack = StaticSafetyPolicy
            .collapseWhitespace(userMessage, foldNewlines: true)
            .lowercased()
        var needles = [written.lowercased(), expanded.lowercased()]
        if expanded == home {
            needles.append("~")
        } else if expanded.hasPrefix(home + "/") {
            needles.append("~" + expanded.dropFirst(home.count).lowercased())
        }
        for needle in Set(needles) {
            guard needle.count >= 2 || needle == "~" else { continue }
            guard !needle.allSatisfy({ $0 == "/" }) else { continue }
            if containsPathBounded(haystack, needle: needle) { return true }
        }
        return false
    }

    private static func containsPathBounded(_ haystack: String, needle: String) -> Bool {
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            if range.upperBound == haystack.endIndex {
                return true
            }
            let next = haystack[range.upperBound]
            let continuesPath = next == "/" || next == "." || next == "_" || next == "-"
                || next.isLetter || next.isNumber
            if !continuesPath {
                return true
            }
            searchRange = range.upperBound..<haystack.endIndex
        }
        return false
    }
}
