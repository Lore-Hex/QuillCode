import Foundation
import QuillCodeCore

struct StaticSafetyPolicy: Sendable {
    private let hardDenyRules: [StaticSafetyHardDenyRule]
    private let intentRules: [StaticSafetyIntentRule]

    init(
        hardDenyRules: [StaticSafetyHardDenyRule] = StaticSafetyPolicy.defaultHardDenyRules,
        intentRules: [StaticSafetyIntentRule] = StaticSafetyPolicy.defaultIntentRules
    ) {
        self.hardDenyRules = hardDenyRules
        self.intentRules = intentRules
    }

    func hardDenyReason(_ context: SafetyContext) -> String? {
        let haystack = normalizedHaystack(for: context)
        guard let rule = hardDenyRules.first(where: { $0.matches(haystack) }) else {
            return nil
        }
        return rule.rationale
    }

    func userIntentMatches(_ context: SafetyContext) -> Bool {
        let request = StaticSafetyRequest(context.userMessage)
        let toolName = context.toolCall.name

        if request.containsAffirmedAny(["remember", "memorize"]) {
            return toolName.contains("memory")
        }
        if StaticSafetyPullRequestPolicy.requestMatches(request) {
            return StaticSafetyPullRequestPolicy.intentMatches(request: request, toolName: toolName)
        }
        if StaticSafetyDownloadPolicy.intentMatches(request: request, context: context) {
            return true
        }
        if StaticSafetyReadOnlyShellPolicy.intentMatches(request: request, context: context) {
            return true
        }
        if intentRules.contains(where: { $0.matches(request: request) && $0.allows(toolName: toolName) }) {
            return true
        }
        if toolName.contains("computer"),
           request.containsAffirmedAny(StaticSafetyPolicy.computerUseTriggers) {
            return true
        }
        guard context.toolDefinition?.risk == .read else {
            return false
        }
        return request.significantWords.contains { word in
            context.toolCall.argumentsJSON.lowercased().contains(word)
        }
    }

    private func normalizedHaystack(for context: SafetyContext) -> String {
        // Match against the DECODED argument values, not the raw JSON wire form. The tool executor
        // runs the decoded arguments, so the denylist should inspect the same decoded value — not a
        // wire encoding. A raw-blob match misses any JSON escape (`/` -> `/`, ` ` -> space), so a
        // blob like `{"cmd":"rm -rf /"}` would slip past the hard-deny and then execute as `rm -rf /`.
        // Today the model pipeline reserializes tool arguments through JSONSerialization before this
        // check (AgentActionJSONParser), so escapes are already normalized and no live path delivers
        // such a blob; matching the decoded value here is defense-in-depth that keeps the denylist
        // correct on its own rather than depending on that upstream reserialization (e.g. a future
        // streaming/partial path that carries raw model bytes). It also subsumes the one-off `\/` patch.
        let arguments = Self.decodedArgumentText(context.toolCall.argumentsJSON)
            ?? context.toolCall.argumentsJSON.replacingOccurrences(of: "\\/", with: "/")
        return "\(context.toolCall.name) \(arguments)".lowercased()
    }

    /// Flattens a JSON argument blob into its decoded string content (keys and values, recursively)
    /// so the denylist sees what the tool will actually run. Returns nil when the blob is not
    /// decodable JSON, so the caller falls back to the raw string (no regression for malformed input).
    private static func decodedArgumentText(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            return nil
        }
        var parts: [String] = []
        collectStrings(from: object, into: &parts)
        return parts.joined(separator: " ")
    }

    private static func collectStrings(from object: Any, into parts: inout [String]) {
        // Keys are included so a deny pattern that names an argument can match; no current schema key
        // collides with a deny substring, but a future key (e.g. one containing "mkfs"/"ddif") could
        // false-deny a benign call — keep deny patterns specific to command text, not bare arg names.
        switch object {
        case let string as String:
            parts.append(string)
        case let dictionary as [String: Any]:
            for (key, value) in dictionary {
                parts.append(key)
                collectStrings(from: value, into: &parts)
            }
        case let array as [Any]:
            for value in array {
                collectStrings(from: value, into: &parts)
            }
        default:
            break
        }
    }

    private static let defaultHardDenyRules: [StaticSafetyHardDenyRule] = [
        .all(
            ["curl ", "| sh"],
            rationale: "Auto mode blocks piping remote downloads into a shell."
        ),
        .all(
            ["curl ", "| bash"],
            rationale: "Auto mode blocks piping remote downloads into a shell."
        ),
        .contains("rm -rf /"),
        .contains("mkfs"),
        .contains("dd if="),
        .contains("security find-generic-password"),
        .contains("cat ~/.ssh"),
        .contains("aws_secret_access_key"),
        .contains("chmod -r 777 /"),
        .contains(":(){")
    ]

    private static let defaultIntentRules: [StaticSafetyIntentRule] = [
        .init(
            requestTriggers: ["run", "execute"],
            allowedToolNames: ["shell.run"]
        ),
        .init(
            requestTriggers: ["mcp"],
            allowedToolNames: ["mcp.call"]
        ),
        .init(
            requestTriggers: commonDiagnosticTriggers,
            allowedToolNames: ["shell.run"]
        ),
        .init(
            requestTriggers: ["apply patch", "apply this patch", "patch"],
            allowedToolNames: ["apply_patch"]
        ),
        .init(
            requestTriggers: ["make", "create", "write"],
            allowedToolNames: ["file", "shell", "git.worktree"]
        ),
        .init(
            requestTriggers: ["commit"],
            allowedToolNames: ["git.commit", "git.stage", "git.status", "git.diff"]
        ),
        .init(
            requestTriggers: ["push", "publish branch"],
            allowedToolNames: ["git.push", "git.status"]
        ),
        .init(
            requestTriggers: ["worktree"],
            allowedToolNames: ["git.worktree", "git.status", "git.diff"]
        )
    ]

    private static let computerUseTriggers = [
        "screenshot",
        "screen",
        "click",
        "type",
        "scroll",
        "cursor",
        "mouse",
        "press",
        "key"
    ]

    private static let commonDiagnosticTriggers = [
        "hd",
        "openclaw",
        "whoami",
        "disk",
        "storage"
    ]
}

struct StaticSafetyHardDenyRule: Sendable {
    private var matcher: StaticSafetyStringMatcher
    var rationale: String

    static func contains(_ pattern: String) -> StaticSafetyHardDenyRule {
        StaticSafetyHardDenyRule(
            matcher: .contains(pattern),
            rationale: "Auto mode blocks high-risk command pattern: \(pattern)."
        )
    }

    static func all(_ patterns: [String], rationale: String) -> StaticSafetyHardDenyRule {
        StaticSafetyHardDenyRule(matcher: .all(patterns), rationale: rationale)
    }

    func matches(_ haystack: String) -> Bool {
        matcher.matches(haystack)
    }
}

struct StaticSafetyIntentRule: Sendable {
    var requestTriggers: [String]
    var allowedToolNames: [String]

    func matches(request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(requestTriggers)
    }

    func allows(toolName: String) -> Bool {
        allowedToolNames.contains { toolName.contains($0) }
    }
}

enum StaticSafetyStringMatcher: Sendable {
    case contains(String)
    case all([String])

    func matches(_ haystack: String) -> Bool {
        switch self {
        case .contains(let pattern):
            return haystack.contains(pattern)
        case .all(let patterns):
            return patterns.allSatisfy { haystack.contains($0) }
        }
    }
}

struct StaticSafetyRequest: Sendable {
    private let text: String

    init(_ text: String) {
        self.text = text.lowercased()
    }

    var significantWords: [String] {
        tokens
            .filter { $0.count >= 3 }
    }

    var requestedDownloadHosts: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`()[]{}<>"))
        return text
            .components(separatedBy: separators)
            .compactMap(Self.normalizedHostCandidate)
    }

    var requestedDownloadFileURLs: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\"'`()[]{}<>"))
        return text
            .components(separatedBy: separators)
            .compactMap(Self.normalizedFileURLCandidate)
    }

    func containsAffirmedAny(_ phrases: [String]) -> Bool {
        phrases.contains { containsAffirmed($0) }
    }

    func containsToken(_ token: String) -> Bool {
        let normalized = token.lowercased()
        return tokens.contains { $0 == normalized }
    }

    private var tokens: [String] {
        indexedTokens.map(\.value)
    }

    private var indexedTokens: [IndexedToken] {
        Self.tokenizeWithClauseStarts(text)
    }

    private func containsAffirmed(_ phrase: String) -> Bool {
        guard text.contains(phrase.lowercased()) else {
            return false
        }
        let phraseTokens = Self.tokenize(phrase)
        guard !phraseTokens.isEmpty else {
            return false
        }
        let requestTokens = indexedTokens
        guard requestTokens.count >= phraseTokens.count else {
            return false
        }
        for start in 0...(requestTokens.count - phraseTokens.count) {
            let end = start + phraseTokens.count
            let tokenValues = requestTokens[start..<end].map(\.value)
            guard tokenValues == phraseTokens else {
                continue
            }
            if !hasNegationBefore(start, in: requestTokens) {
                return true
            }
        }
        return false
    }

    private func hasNegationBefore(_ index: Int, in tokens: [IndexedToken]) -> Bool {
        guard index > 0 else {
            return false
        }
        let clauseStart = stride(from: index, through: 0, by: -1)
            .first { tokens[$0].startsClause } ?? 0
        let start = max(clauseStart, index - 4)
        let prefix = tokens[start..<index].map(\.value)
        if prefix.contains(where: { ["dont", "never", "without"].contains($0) }) {
            return true
        }
        if prefix.last == "no" {
            return true
        }
        return containsAdjacent("do", "not", in: prefix)
            || containsAdjacent("does", "not", in: prefix)
            || containsAdjacent("did", "not", in: prefix)
    }

    private struct IndexedToken: Sendable {
        var value: String
        var startsClause: Bool
    }

    private func containsAdjacent(_ first: String, _ second: String, in tokens: [String]) -> Bool {
        guard tokens.count >= 2 else {
            return false
        }
        return zip(tokens, tokens.dropFirst()).contains { $0 == first && $1 == second }
    }

    private static func tokenize(_ value: String) -> [String] {
        tokenizeWithClauseStarts(value).map(\.value)
    }

    private static func tokenizeWithClauseStarts(_ value: String) -> [IndexedToken] {
        var tokens: [IndexedToken] = []
        var current = ""
        var nextStartsClause = true
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")

        func flushToken() {
            guard !current.isEmpty else {
                return
            }
            tokens.append(.init(value: current, startsClause: nextStartsClause))
            current = ""
            nextStartsClause = false
        }

        for character in normalized {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                flushToken()
                if isClauseBoundary(character) {
                    nextStartsClause = true
                }
            }
        }
        flushToken()
        return tokens
    }

    private static func isClauseBoundary(_ character: Character) -> Bool {
        character == ";" || character == "." || character == "!" || character == "?" || character == "\n"
    }

    private static func normalizedHostCandidate(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: ",:;!?"))
        let lowerCandidate = candidate.lowercased()
        guard !lowerCandidate.hasPrefix("file://"),
              candidate.contains("."),
              !candidate.contains("@")
        else {
            return nil
        }
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard let host = URL(string: candidate)?.host?.lowercased(),
              host.contains(".")
        else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func normalizedFileURLCandidate(_ value: String) -> String? {
        let candidate = value
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;!?"))
            .lowercased()
        return candidate.hasPrefix("file://") ? candidate : nil
    }
}

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
        let requestedHosts = request.requestedDownloadHosts
        return requestedHosts.contains { host in
            lowerCommand.contains(host)
        }
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

enum StaticSafetyReadOnlyShellPolicy {
    static func intentMatches(request: StaticSafetyRequest, context: SafetyContext) -> Bool {
        guard context.toolCall.name.contains("shell.run"),
              let command = shellCommand(from: context.toolCall)
        else {
            return false
        }
        let normalized = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard isSingleReadCommand(normalized) else {
            return false
        }

        if isPwdCommand(normalized) {
            return isCurrentDirectoryRequest(request)
        }
        if isLsCommand(normalized) {
            return isFileListingRequest(request)
        }
        if isGitStatusCommand(normalized) {
            return isGitStatusRequest(request)
        }
        return false
    }

    private static func shellCommand(from call: ToolCall) -> String? {
        try? ToolArguments(call.argumentsJSON).requiredString("cmd")
    }

    private static func isSingleReadCommand(_ command: String) -> Bool {
        [";", "&&", "||", "|", "`", "$(", ">", "<"].allSatisfy { !command.contains($0) }
    }

    private static func isPwdCommand(_ command: String) -> Bool {
        command == "pwd" || command == "/bin/pwd" || command == "command pwd"
    }

    private static func isLsCommand(_ command: String) -> Bool {
        let parts = command.split(separator: " ").map(String.init)
        guard parts.first == "ls", parts.count <= 3 else {
            return false
        }
        return parts.dropFirst().allSatisfy { part in
            if part.hasPrefix("-") {
                return part.dropFirst().allSatisfy { "1aAlLh".contains($0) }
            }
            return isSafeRelativePath(part)
        }
    }

    private static func isGitStatusCommand(_ command: String) -> Bool {
        let parts = command.split(separator: " ").map(String.init)
        guard parts.count >= 2,
              parts[0] == "git",
              parts[1] == "status"
        else {
            return false
        }
        return parts.dropFirst(2).allSatisfy { part in
            part == "--short" || part == "-s" || part == "--porcelain" || part == "--branch" || part == "-b"
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && !path.hasPrefix("~")
            && !path.contains("..")
    }

    private static func isCurrentDirectoryRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "current directory",
            "working directory",
            "current folder",
            "workspace path",
            "where am i",
            "pwd"
        ])
    }

    private static func isFileListingRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(["list files", "list the files", "show files", "show the files"])
            || ((request.containsToken("files") || request.containsToken("directory") || request.containsToken("folder"))
                && (request.containsToken("list") || request.containsToken("show") || request.containsToken("what")))
    }

    private static func isGitStatusRequest(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny([
            "git status",
            "repo status",
            "repository status",
            "working tree status",
            "working directory status"
        ])
            || (request.containsToken("status") && (request.containsToken("git") || request.containsToken("repo")))
    }
}

enum StaticSafetyPullRequestPolicy {
    static let requestTriggers = [
        "pull request",
        "open pr",
        "open a pr",
        "create pr",
        "create a pr",
        "submit pr",
        "submit a pr",
        "checkout pr",
        "check out pr",
        "switch to pr",
        "merge pr",
        "automerge pr",
        "auto merge pr",
        "inline comment",
        "review thread",
        "review threads",
        "thread ids",
        "resolve thread",
        "unresolve thread"
    ]

    private static let specificRules: [StaticSafetyIntentRule] = [
        .init(
            requestTriggers: ["checkout", "check out", "switch"],
            allowedToolNames: ["git.pr.checkout", "git.status"]
        ),
        .init(
            requestTriggers: ["reviewer", "reviewers", "request review from"],
            allowedToolNames: ["git.pr.reviewers", "git.status"]
        ),
        .init(
            requestTriggers: ["label", "labels", "unlabel"],
            allowedToolNames: ["git.pr.labels", "git.status"]
        ),
        .init(
            requestTriggers: ["merge", "automerge"],
            allowedToolNames: ["git.pr.merge", "git.pr.checks", "git.status"]
        ),
        .init(
            requestTriggers: ["list", "show", "browse", "find", "unresolved", "thread ids", "comment ids"],
            allowedToolNames: ["git.pr.review_threads", "git.pr.view", "git.status"]
        ),
        .init(
            requestTriggers: ["resolve", "unresolve", "reopen"],
            allowedToolNames: ["git.pr.review_thread", "git.status"]
        ),
        .init(
            requestTriggers: ["approve", "request changes", "needs changes", "review"],
            allowedToolNames: ["git.pr.review", "git.status"]
        ),
        .init(
            requestTriggers: ["comment", "reply"],
            allowedToolNames: ["git.pr.comment", "git.pr.review_comment", "git.pr.review_reply"]
        ),
        .init(
            requestTriggers: ["check", "ci", "status"],
            allowedToolNames: ["git.pr.checks", "git.status"]
        ),
        .init(
            requestTriggers: ["view", "show", "inspect", "read"],
            allowedToolNames: ["git.pr.view", "git.status"]
        )
    ]

    private static let defaultAllowedToolNames = [
        "git.pr.create",
        "git.pr.comment",
        "git.push",
        "git.status"
    ]

    static func requestMatches(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(requestTriggers)
            || (request.containsToken("pr") && specificRules.contains { $0.matches(request: request) })
    }

    static func intentMatches(request: StaticSafetyRequest, toolName: String) -> Bool {
        let matchingRules = specificRules.filter { $0.matches(request: request) }
        if !matchingRules.isEmpty {
            return matchingRules.contains { $0.allows(toolName: toolName) }
        }
        return defaultAllowedToolNames.contains { toolName.contains($0) }
    }
}
