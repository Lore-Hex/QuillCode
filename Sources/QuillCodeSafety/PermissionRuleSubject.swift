import Foundation
import QuillCodeCore

/// The normalized (action, resource) pair a permission rule table is evaluated against — and the
/// pair an "always allow/deny" answer derives its saved rule from. Building BOTH through this one
/// type guarantees a saved rule and the gate agree on spelling, so a taught rule always fires.
///
/// Two concerns are deliberately separated:
/// - `resource` scopes the call for MATCHING. Deny/ask rules may target ANY tool at the action
///   level (broadening a block is safe), so a subject always has a usable `resource`.
/// - `allowScopable` gates whether an ALLOW rule may be derived from, or may match, this call.
///   An allow rule is a standing "run this unattended" — so it is only permitted for tools whose
///   resource genuinely bounds what runs. A tool with no meaningful scoping resource (e.g.
///   `host.apply_patch`, `host.git.*`, `host.computer.*`) is NOT allow-scopable: teaching one call
///   must never silently authorize every future call of that tool. See `allowMatchResource`.
///
/// Resources are normalized before matching so re-spellings cannot dodge a rule:
/// - shell commands: trimmed, spaces/tabs collapsed to single spaces (newlines PRESERVED so a
///   multi-command script never matches a single-command rule). A call carrying an environment
///   override or a non-default cwd is NOT allow-scopable (a taught bare command must not cover a
///   call that also injects PATH/DYLD_*/GIT_SSH_COMMAND or runs in another directory).
/// - workspace paths: absolute, `..`/`.` resolved, symlink-resolved via `WorkspaceBoundary`, and
///   case-folded on case-insensitive volumes so `.ENV.local` cannot dodge a deny for `.env.local`.
/// - `host.browser.open`: the normalized URL.
/// - `host.mcp.call`: `serverID/toolName`.
public struct PermissionRuleSubject: Sendable, Hashable {
    public var action: String
    public var resource: String
    /// Whether an ALLOW rule may be derived from / may match this call. False = the call has no
    /// bounding resource, so it can never carry a standing auto-run authorization.
    public var allowScopable: Bool

    public init(action: String, resource: String, allowScopable: Bool) {
        self.action = action
        self.resource = resource
        self.allowScopable = allowScopable
    }

    /// The resource an ALLOW rule matches against — nil when the call is not allow-scopable, which
    /// makes every allow rule miss (evaluation degrades to deny/ask only). Deny/ask always match on
    /// `resource`, scopable or not.
    public var allowMatchResource: String? {
        allowScopable ? resource : nil
    }

    /// Tool name → the argument key holding the path resource. These tools ARE allow-scopable by
    /// their normalized path.
    private static let pathArgumentKeyByTool: [String: String] = [
        "host.file.read": "path",
        "host.file.write": "path",
        "host.file.list": "path",
        "host.file.search": "path"
    ]

    private static let shellRunToolName = "host.shell.run"
    private static let mcpCallToolName = "host.mcp.call"
    private static let browserOpenToolName = "host.browser.open"

    public static func make(toolCall: ToolCall, workspaceRoot: URL?) -> PermissionRuleSubject {
        let arguments = try? ToolArguments(toolCall.argumentsJSON)
        if toolCall.name == shellRunToolName {
            return shellSubject(toolCall.name, arguments: arguments, workspaceRoot: workspaceRoot)
        }
        if let pathKey = pathArgumentKeyByTool[toolCall.name] {
            return PermissionRuleSubject(
                action: toolCall.name,
                resource: normalizedPath(arguments?.string(pathKey), workspaceRoot: workspaceRoot),
                allowScopable: true
            )
        }
        if toolCall.name == browserOpenToolName {
            let url = normalizedURL(arguments?.string("url"))
            return PermissionRuleSubject(
                action: toolCall.name,
                resource: url,
                allowScopable: !url.isEmpty
            )
        }
        if toolCall.name == mcpCallToolName {
            let resource = mcpResource(arguments)
            return PermissionRuleSubject(
                action: toolCall.name,
                resource: resource,
                allowScopable: !resource.isEmpty
            )
        }
        // Every other tool (apply_patch, git.*, git.pr.*, computer.*, memory.remember, …) has no
        // bounding resource we can trust for a standing allow. It is matched at the action level
        // for deny/ask only; no allow rule may cover it.
        return PermissionRuleSubject(action: toolCall.name, resource: "", allowScopable: false)
    }

    private static func shellSubject(
        _ action: String,
        arguments: ToolArguments?,
        workspaceRoot: URL?
    ) -> PermissionRuleSubject {
        let command = normalizedCommand(arguments?.string("cmd"))
        // The dispatcher honors `environment`/`env` overrides and `cwd`; either would change what a
        // bare command actually does (attacker PATH, DYLD_*, a different directory). A call that
        // carries either is NOT allow-scopable, so a taught `swift test` never authorizes
        // `swift test` with an injected environment or in an unexpected directory.
        let hasEnvironmentOverride = !(arguments?.stringDictionary("environment") ?? [:]).isEmpty
            || !(arguments?.stringDictionary("env") ?? [:]).isEmpty
        let cwd = (arguments?.string("cwd") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNonDefaultCwd = !(cwd.isEmpty || cwd == "." || cwd == "./")
        let allowScopable = !command.isEmpty && !hasEnvironmentOverride && !hasNonDefaultCwd
        return PermissionRuleSubject(action: action, resource: command, allowScopable: allowScopable)
    }

    /// Trims and collapses runs of HORIZONTAL whitespace to a single ASCII space so `rm  -rf x`
    /// cannot dodge a rule saved for `rm -rf x`. Every horizontal whitespace scalar folds — not just
    /// space/tab but exotic Unicode whitespace (NBSP U+00A0, thin space U+2009, ideographic space
    /// U+3000, …) — and zero-width scalars (U+200B/C/D, U+FEFF) are stripped, so `rm -rf<NBSP>/`
    /// normalizes to the same resource a plain-space spelling would (see `WhitespaceFolding`).
    ///
    /// NEWLINE-LIKE scalars (LF/CR and the vertical whitespace class — form-feed, vertical-tab, line/
    /// paragraph separator) are preserved verbatim: they separate commands, so folding them would
    /// let a single-command allow (`echo hi`) match a multi-command script (`echo hi\nrm -rf .`).
    /// The floor's `collapseWhitespace` folds the SAME horizontal set this does and additionally
    /// folds these separators, so the floor stays a strict superset of this normalization — no
    /// whitespace spelling can match a wildcard allow while dodging the floor.
    static func normalizedCommand(_ command: String?) -> String {
        guard let command else { return "" }
        var output = ""
        output.reserveCapacity(command.count)
        var pendingSpace = false
        var atLineStart = true
        for scalar in command.unicodeScalars {
            if WhitespaceFolding.isZeroWidth(scalar) {
                // Zero-width: strip it, joining the tokens on either side without a space.
                continue
            }
            if WhitespaceFolding.isNewlineLike(scalar) {
                // Line boundary / command separator: drop any trailing horizontal space, emit it
                // verbatim so a multi-command script never collapses into a single-command allow.
                pendingSpace = false
                output.unicodeScalars.append(scalar)
                atLineStart = true
                continue
            }
            if WhitespaceFolding.isFoldableHorizontal(scalar) {
                pendingSpace = true
                continue
            }
            if pendingSpace && !atLineStart {
                output.unicodeScalars.append(" ")
            }
            pendingSpace = false
            atLineStart = false
            output.unicodeScalars.append(scalar)
        }
        return output
    }

    /// Absolute, `..`-resolved, symlink-resolved path (via the shared `WorkspaceBoundary`
    /// normalization the file/git/patch executors enforce), case-folded on case-insensitive
    /// volumes. Relative paths resolve against the workspace root; without a root the path is
    /// lexically standardized only.
    static func normalizedPath(_ path: String?, workspaceRoot: URL?) -> String {
        let trimmed = (path ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = trimmed.isEmpty ? "." : trimmed
        let candidate: URL
        if effective.hasPrefix("/") {
            candidate = URL(fileURLWithPath: effective)
        } else if let workspaceRoot {
            candidate = workspaceRoot.appendingPathComponent(effective)
        } else {
            // No workspace root to resolve against (rule tables are per-workspace, so evaluation
            // always has one; this is a defensive fallback). Leave the spelling as-is rather than
            // absolutizing against an unrelated current directory.
            return caseFoldedIfNeeded(effective)
        }
        let resolved = WorkspaceBoundary.symlinkResolvedPath(candidate.standardizedFileURL)
        return caseFoldedIfNeeded(resolved)
    }

    /// `WorkspaceBoundary.symlinkResolvedPath` only case-canonicalizes path components that already
    /// EXIST on disk; a not-yet-created target (e.g. a first write to `.env.local`, or under a
    /// not-yet-created `LOGS/` dir) keeps the as-typed case. On a case-insensitive volume that lets
    /// `.ENV.local` name the same file a deny rule for `.env.local` targets. So on such a volume we
    /// lower-case the whole path for matching; on a case-sensitive volume the case is significant
    /// and preserved.
    static func caseFoldedIfNeeded(_ path: String) -> String {
        pathVolumeIsCaseInsensitive(path) ? path.lowercased() : path
    }

    private static func pathVolumeIsCaseInsensitive(_ path: String) -> Bool {
        // Probe the deepest existing ancestor (the target itself may not exist yet).
        var url = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        while url.path != "/" && !fileManager.fileExists(atPath: url.path) {
            url = url.deletingLastPathComponent()
        }
        if let values = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]),
           let caseSensitive = values.volumeSupportsCaseSensitiveNames {
            return !caseSensitive
        }
        // Unknown → assume case-insensitive (the safer default: it MERGES spellings, so a deny
        // rule can never be dodged by re-casing; it can only over-match, which for deny fails safe).
        return true
    }

    /// Normalizes a browser URL for scoping: trimmed, scheme + host lower-cased so `HTTP://EVIL`
    /// and `http://evil` match one rule, but the path/query stay case-exact (so `/?data=x` differs
    /// from the taught page).
    static func normalizedURL(_ url: String?) -> String {
        let trimmed = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme
        else {
            // Not a parseable absolute URL (e.g. a project-relative path). Keep as-is; a
            // project-relative page is a bounded resource.
            return trimmed
        }
        var normalized = components
        normalized.scheme = scheme.lowercased()
        normalized.host = components.host?.lowercased()
        return normalized.string ?? trimmed
    }

    /// `serverID/toolName` — the `/` separator keeps `*` scoped to one side (`github/*` allows one
    /// server's tools without allowing every server).
    private static func mcpResource(_ arguments: ToolArguments?) -> String {
        let server = arguments?.string("serverID")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tool = arguments?.string("toolName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !server.isEmpty || !tool.isEmpty else { return "" }
        return "\(server)/\(tool)"
    }
}

public enum PermissionRuleDerivation {
    /// Derives the rule an "always allow/deny" answer persists for an approval request: the EXACT
    /// tool name and the EXACT normalized resource, never auto-generalized to a wildcard — the user
    /// teaches one operation at a time; broader patterns are a deliberate hand-edit.
    ///
    /// Returns nil for an ALLOW answer on a call that is not allow-scopable (e.g. `apply_patch`, any
    /// `git.*`): there is no resource that would bound the standing authorization, so refusing to
    /// persist is safer than persisting an over-broad allow. DENY answers are always derivable —
    /// broadening a block to the whole tool is safe.
    public static func rule(
        for request: ApprovalRequest,
        decision: PermissionRuleDecision,
        workspaceRoot: URL?
    ) -> PermissionRule? {
        let subject = PermissionRuleSubject.make(toolCall: request.toolCall, workspaceRoot: workspaceRoot)
        if decision == .allow && !subject.allowScopable {
            return nil
        }
        return PermissionRule(
            action: subject.action,
            resource: subject.resource,
            match: .exact,
            decision: decision
        )
    }
}
