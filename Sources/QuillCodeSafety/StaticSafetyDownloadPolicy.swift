import Foundation
import QuillCodeCore

enum StaticSafetyDownloadPolicy {
    static func intentMatches(request: StaticSafetyRequest, context: SafetyContext) -> Bool {
        guard context.toolCall.name.contains("shell.run"),
              request.containsAffirmedAny(["download", "save", "fetch"]),
              let command = shellCommand(from: context.toolCall)
        else {
            return false
        }
        let lowerCommand = command.lowercased()
        // isScopedToDownload takes the ORIGINAL command: curl flags are case-sensitive (`-O` remote-name
        // vs `-o` output, `-L` vs `-l`), so the allowlist must not see a lowercased blob.
        guard containsDownloadSegment(lowerCommand),
              isScopedToDownload(command),
              outputPath(from: lowerCommand) != nil,
              allOutputTargetsWorkspaceRelative(lowerCommand),
              !hasConfigFileFlag(command),
              !lowerCommand.contains("|")
        else {
            return false
        }
        let requestedFileURLs = request.requestedDownloadFileURLs
        // A `file://` fetch reads a LOCAL file into the workspace. Only allow it when the user
        // explicitly named that exact `file://` URL — otherwise a "download from <host>" intent whose
        // host gate is satisfied by a referer/header could be turned into an arbitrary local-file read
        // (`curl -e 'https://host' --output x 'file:///etc/passwd'`).
        if lowerCommand.contains("file://") {
            return requestedFileURLs.contains { fileURL in
                lowerCommand.contains(fileURL)
            }
        }
        if !requestedFileURLs.isEmpty {
            return requestedFileURLs.contains { fileURL in
                lowerCommand.contains(fileURL)
            }
        }
        // The host gate must match the ACTUAL fetched URL(s), not a substring anywhere in the command.
        // A substring match is satisfiable by an `-e` referer / `-H` header carrying the authorized
        // host while the real target is an internal/other host — an SSRF (e.g. the cloud-metadata
        // endpoint `http://169.254.169.254/…`, which would land cloud credentials in the workspace).
        // Require EVERY http(s) URL in the command to resolve to a user-requested host.
        let requestedHosts = request.requestedDownloadHosts
        guard let urlHosts = Self.httpURLHosts(in: command), !urlHosts.isEmpty else {
            return false
        }
        return urlHosts.allSatisfy { host in
            requestedHosts.contains { requested in
                !requested.isEmpty && (host == requested || host.hasSuffix(".\(requested)"))
            }
        }
    }

    /// Extracts the host of every `http(s)://` URL in the command (quoted or bare), normalized
    /// (lowercased, `www.` stripped) for comparison with `requestedDownloadHosts`. Returns nil if ANY
    /// matched URL fails host extraction — fail-closed, so a URL that curl would fetch but `URLComponents`
    /// cannot parse (a parser differential) drops the whole command to human approval rather than
    /// slipping through unchecked.
    private static func httpURLHosts(in command: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s'"`]+"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(command.startIndex..., in: command)
        var hosts: [String] = []
        for match in regex.matches(in: command, range: range) {
            // `URL(string:).host` matches the requested side's parser (same punycode/Unicode treatment),
            // and `normalizedHost` strips the FQDN-root trailing dot + `www.` so `169.254.169.254.` and
            // `169.254.169.254` compare equal — closing the trailing-dot parser differential curl exploits.
            guard let matchRange = Range(match.range, in: command),
                  let rawHost = URL(string: String(command[matchRange]))?.host,
                  let host = StaticSafetyRequest.normalizedHost(rawHost)
            else {
                return nil
            }
            hosts.append(host)
        }
        return hosts
    }

    private static func shellCommand(from call: ToolCall) -> String? {
        try? ToolArguments(call.argumentsJSON).requiredString("cmd")
    }

    private static func containsDownloadSegment(_ command: String) -> Bool {
        commandSegments(command).contains { segment in
            segment.hasPrefix("curl ") || segment.hasPrefix("wget ")
        }
    }

    /// Auto-approval here is a NARROW carve-out — "download to a workspace file" — so the command must
    /// be ONLY the download plus harmless scaffolding, with no shell machinery that could write
    /// elsewhere or run something else. Single-quoted spans (a URL/path) are literal, so they are
    /// neutralized first; then ANY active redirect / substitution / expansion / double-quote — on the
    /// curl/wget segment too, not just companions — drops the call to human approval. What remains must
    /// segment into the download (`curl`/`wget`) plus safe companions, nothing more.
    private static func isScopedToDownload(_ command: String) -> Bool {
        let structural = neutralizingSingleQuotedSpans(command)
        guard !containsActiveShellMetacharacters(structural) else {
            return false
        }
        return commandSegments(structural).allSatisfy { segment in
            if segment.hasPrefix("curl ") {
                return curlInvocationUsesOnlySafeFlags(segment)
            }
            // `wget` is intentionally NOT auto-approved: its flag set has too many file-writing traps
            // (`-O`/`-o` log vs output, `-P` prefix, `--*-cookies`); a wget download falls through to
            // human approval. Everything else must be a safe companion.
            return isSafeCompanionHead(segment)
        }
    }

    /// An ALLOWLIST of curl flags, not a denylist: curl honors hundreds of options, several of which
    /// write a server-controlled file to a caller-chosen path (`-c`/`--cookie-jar`, `-D`/`--dump-header`,
    /// `--trace*`, `--etag-save`, `--output-dir`, `-O`/`--remote-name`) or read/upload one (`-T`, `-d @`,
    /// `-K`/`--config`). Enumerating the dangerous ones is allow-by-omission and always lags curl; instead
    /// accept ONLY known-safe flags and drop anything else to human approval. Operates on the
    /// single-quote-neutralized segment, so a flag's quoted value cannot masquerade as a flag.
    private static func curlInvocationUsesOnlySafeFlags(_ segment: String) -> Bool {
        let tokens = segment.split(separator: " ").map(String.init)
        for token in tokens.dropFirst() where token.hasPrefix("-") {
            if !token.hasPrefix("--") && token.count > 2 {
                // A bundle of short flags (`-fsSL`). Allow it only if EVERY letter is a known-safe
                // boolean (no-argument) short flag — an argument-taking one (`-o`, `-H`) can't be
                // bundled safely (its value would be ambiguous), so such a bundle falls to approval.
                guard token.dropFirst().allSatisfy({ Self.safeBooleanShortCurlFlags.contains("-\($0)") }) else {
                    return false
                }
                continue
            }
            let flag = token.split(separator: "=", maxSplits: 1).first.map(String.init) ?? token
            guard Self.safeCurlFlags.contains(flag) else {
                return false
            }
        }
        return true
    }

    /// The argument-LESS short flags from `safeCurlFlags`, used to validate bundled short flags
    /// (`-fsSL`). Argument-taking short flags (`-o`, `-H`, `-A`, `-e`, `-m`, `-C`) are intentionally
    /// absent so they cannot hide inside a bundle.
    private static let safeBooleanShortCurlFlags: Set<String> = ["-L", "-f", "-s", "-S", "-R", "-#"]

    /// Known-safe curl flags for a workspace download. Deliberately excludes every file-writing /
    /// file-reading / config flag (`-O`, `-c`, `-D`, `--trace*`, `--output-dir`, `-T`, `-d`, `-K`, …)
    /// AND every protocol/URL-manipulation flag (`--proto`, `--proto-default`, `--url`, `-G`/`--get`):
    /// `--proto-default file` turns a schemeless path argument into a `file://` read of an arbitrary
    /// local file, defeating the "this is a network download" assumption the carve-out rests on.
    /// `-o`/`--output` is allowed but its target is still validated workspace-relative separately.
    private static let safeCurlFlags: Set<String> = [
        "-L", "--location",
        "-f", "--fail", "--fail-with-body",
        "-s", "--silent", "-S", "--show-error",
        "--compressed", "--create-dirs", "-#", "--progress-bar", "--no-progress-meter",
        "-o", "--output",
        "-H", "--header",
        "-A", "--user-agent", "-e", "--referer",
        "-C", "--continue-at", "-R", "--remote-time",
        "--connect-timeout", "-m", "--max-time",
        "--retry", "--retry-delay", "--retry-max-time", "--retry-connrefused", "--retry-all-errors",
        "--max-filesize", "--limit-rate"
    ]

    /// Replaces the *contents* of single-quoted spans with nothing (keeping the quotes), so a URL or
    /// path that legitimately contains an operator or metacharacter (`'…?a=1&b=2'`, `'…/$(x)'`) is not
    /// mistaken for command structure. Single quotes suppress every shell expansion, so their contents
    /// are always inert. Double quotes do NOT suppress `$()`/backticks, so they are left intact and
    /// rejected as metacharacters below.
    private static func neutralizingSingleQuotedSpans(_ command: String) -> String {
        var result = ""
        var inSingleQuote = false
        for character in command {
            if character == "'" {
                result.append(character)
                inSingleQuote.toggle()
            } else if !inSingleQuote {
                result.append(character)
            }
        }
        return result
    }

    /// Active shell machinery that must never ride a download auto-approval: redirects (`>` `<`, which
    /// also covers process substitution `<(…)`/`>(…)`), command substitution (backtick), any expansion
    /// or `$( … )` (`$`), double quotes (which would re-enable `$()`/backticks inside), backslash
    /// (an escaped quote like `\'` could otherwise desync the single-quote neutralizer and hide a `$()`),
    /// glob metacharacters (`*` `?` — the shell rewrites the path before the tool sees it), and
    /// subshell / brace groups (`(` `)` `{` `}`). Checked on the single-quote-neutralized command, so
    /// these only fire when active (outside `'…'`).
    private static func containsActiveShellMetacharacters(_ command: String) -> Bool {
        // `@` is included because curl reads a file when an argument is `@path` (e.g. `-H @/etc/passwd`,
        // `-d @secret`) — an exfiltration indirection even on an allowlisted flag.
        let metacharacters = [">", "<", "`", "$", "\"", "\\", "*", "?", "(", ")", "{", "}", "@"]
        return metacharacters.contains { command.contains($0) }
    }

    private static func isSafeCompanionHead(_ segment: String) -> Bool {
        // Read-only / scaffolding helpers that legitimately accompany a download: make the target dir,
        // list/confirm it. `cd` is deliberately excluded — it changes the cwd, which would relocate the
        // download's "workspace-relative" output (`cd /etc && curl --output passwd …`). Anything else
        // (rm, mv, git, chmod, …) means the command does more than download.
        let head = segment.split(separator: " ", maxSplits: 1).first.map(String.init) ?? segment
        let allowed: Set<String> = ["mkdir", "ls", "pwd", "test", "[", ":", "true", "echo"]
        return allowed.contains(head)
    }

    /// `curl -K file` / `--config file` reads arbitrary options (extra `--output`/urls) from a file the
    /// policy never inspects — a config-file injection that would defeat the output-path checks. Takes
    /// the ORIGINAL (case-sensitive) command: `-K` (config) must not be confused with `-k` (insecure),
    /// which the lowercased command would conflate. Also covers `-Kfile` / `--config=file` forms.
    private static func hasConfigFileFlag(_ command: String) -> Bool {
        let tokens: [String] = command.split(separator: " ").map(String.init)
        return tokens.contains { token in
            token.hasPrefix("-K") || token.hasPrefix("--config")
        }
    }

    /// Every `--output`/`-o` target must be workspace-relative — curl honors them ALL, so validating
    /// only the first (as `outputPath` does) lets a second `--output '/etc/evil'` write outside.
    private static func allOutputTargetsWorkspaceRelative(_ command: String) -> Bool {
        let patterns = [
            #"--output\s+('[^']+'|"[^"]+"|\S+)"#,
            #"\s-o\s+('[^']+'|"[^"]+"|\S+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(command.startIndex..., in: command)
            for match in regex.matches(in: command, range: range) {
                guard let targetRange = Range(match.range(at: 1), in: command) else {
                    continue
                }
                if !isWorkspaceRelativePath(unquoted(String(command[targetRange]))) {
                    return false
                }
            }
        }
        return true
    }

    /// Splits a command on every shell sequencing/background/pipe operator so each runnable piece is
    /// checked independently. (`|` is also rejected outright by the caller, but splitting on it keeps
    /// this self-contained.) `&&` / `||` are normalized before the single-char `&` / `|`.
    private static func commandSegments(_ command: String) -> [String] {
        command
            .replacingOccurrences(of: "&&", with: "\n")
            .replacingOccurrences(of: "||", with: "\n")
            .replacingOccurrences(of: ";", with: "\n")
            .replacingOccurrences(of: "|", with: "\n")
            .replacingOccurrences(of: "&", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func outputPath(from command: String) -> String? {
        let patterns = [
            #"--output\s+('[^']+'|"[^"]+"|\S+)"#,
            #"\s-o\s+('[^']+'|"[^"]+"|\S+)"#,
            #">\s*('[^']+'|"[^"]+"|\S+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
                  let range = Range(match.range(at: 1), in: command)
            else {
                continue
            }
            return unquoted(String(command[range]))
        }
        return nil
    }

    private static func isWorkspaceRelativePath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.hasPrefix("/")
            && !trimmed.hasPrefix("~")
            && !trimmed.contains("..")
    }

    private static func unquoted(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("'") && trimmed.hasSuffix("'"))
            || (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) {
            trimmed.removeFirst()
            trimmed.removeLast()
        }
        return trimmed
    }
}
