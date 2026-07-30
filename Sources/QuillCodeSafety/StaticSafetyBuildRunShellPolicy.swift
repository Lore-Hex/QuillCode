import Foundation
import QuillCodeCore

/// Verify-after-edit is the coworker move Auto mode most needs and least covered: the model writes a
/// file (now statically approved) and immediately wants to RUN it — `python3 greeting.py`, `pytest`,
/// `npm test`, `./run_service.sh` — to prove the change works. That run matched no static rule, so the
/// model safety reviewer was the only approver; when it was momentarily unavailable the whole headless
/// run died at the verify step (observed live on use cases #8 and #14). Auto mode already grants
/// file-write AND (reviewer permitting) execution, so running the project's own build/test/run tool on
/// workspace-relative paths is squarely inside the promise the mode makes.
///
/// The approval is deliberately narrow:
/// - ONE command — no `;`, `&&`, `||`, `|`, `` ` ``, `$(…)`, redirects, or backgrounding (the same
///   guard the read-only diagnostics use). No chaining means no "verify … then exfiltrate".
/// - the executable's basename must be a recognized runner (see `runnerExecutables`). `rm`, `curl`,
///   `nc`, `ssh` are not runners, so "name a user file" cannot smuggle a destructive/network command.
/// - no argument may be an absolute path, a `~` path, contain `..`, or be an inline-eval flag
///   (`-c`/`-e`/`--eval`): the command must run FILES IN THE WORKSPACE, not arbitrary inline code or
///   anything outside the tree.
/// - the request must actually be asking for a run/build/test/verify (an intent verb) OR the command
///   must target a path the user named — so an unrelated task can't ride along.
///
/// Hard-deny floors still run BEFORE intent matching in Auto mode, so `rm -rf`, pipe-to-shell, sudo,
/// and system-path writes stay denied no matter what this returns.
enum StaticSafetyBuildRunShellPolicy {
    static func intentMatches(request: StaticSafetyRequest, context: SafetyContext) -> Bool {
        guard context.toolCall.name.contains("shell.run"),
              let command = shellCommand(from: context.toolCall)
        else {
            return false
        }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSingleCommand(trimmed) else { return false }

        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let head = tokens.first else { return false }
        guard isRunnerExecutable(head) else { return false }

        let arguments = Array(tokens.dropFirst())
        guard arguments.allSatisfy(isSafeRunArgument) else { return false }

        return requestExpressesRunIntent(request)
            || commandTargetsRequestedPath(arguments, userMessage: context.userMessage)
    }

    private static func shellCommand(from call: ToolCall) -> String? {
        try? ToolArguments(call.argumentsJSON).requiredString("cmd")
    }

    /// A single foreground command — shared with the run-intent policy.
    private static func isSingleCommand(_ command: String) -> Bool {
        StaticSafetyShellCommandSafety.isSingleCommand(command)
    }

    /// The basename of the executable must be a known build/test/run tool. `./gradlew`, `/usr/bin/python3`,
    /// and `python3` all reduce to their last path component before the check.
    private static func isRunnerExecutable(_ head: String) -> Bool {
        let base = head.split(separator: "/").last.map(String.init) ?? head
        // `./script.sh` and `bin/script` reach here as their basename; a bare `./` relative script is
        // allowed only when it ends in a script extension, so `./deploy` is NOT auto-approved.
        if head.hasPrefix("./") || head.contains("/") {
            if scriptExtensions.contains(where: { base.hasSuffix($0) }) { return true }
        }
        return runnerExecutables.contains(base)
    }

    private static let scriptExtensions = [".sh", ".bash", ".py", ".rb", ".js", ".ts", ".mjs"]

    private static let runnerExecutables: Set<String> = [
        "python", "python3", "py", "node", "deno", "bun", "ruby", "php", "perl",
        "pytest", "tox", "nox", "unittest",
        "npm", "pnpm", "yarn", "npx", "jest", "vitest", "mocha",
        "go", "cargo", "rustc", "swift", "make", "cmake", "ninja",
        "gradle", "gradlew", "mvn", "dotnet", "rake", "rspec", "bundle",
        "bash", "sh", "zsh", "just", "task",
    ]

    private static func isSafeRunArgument(_ argument: String) -> Bool {
        // Shared workspace-path safety (no absolute / `~` / `..`) plus a runner-specific rule:
        // reject inline-eval flags — `python -c "..."` runs code, it does not verify a project file.
        guard StaticSafetyShellCommandSafety.isSafeArgument(argument) else { return false }
        return !inlineEvalFlags.contains(argument)
    }

    /// Interpreter flags that execute code supplied on the command line instead of running a project
    /// file. `python -c "..."`, `node -e "..."`, `ruby -e "..."`, `perl -e "..."` are NOT verify-a-file.
    private static let inlineEvalFlags: Set<String> = ["-c", "-e", "--eval", "--exec", "-"]

    private static func requestExpressesRunIntent(_ request: StaticSafetyRequest) -> Bool {
        request.containsAffirmedAny(runIntentPhrases)
    }

    private static let runIntentPhrases = [
        "run", "runs", "running", "re-run", "rerun",
        "test", "tests", "testing", "pytest", "unit test",
        "build", "builds", "compile", "compiles", "compiling",
        "verify", "verifies", "verifying", "check that", "make sure",
        "execute", "executes", "passing", "pass", "works",
    ]

    /// True when any path-like argument to the command appears VERBATIM in the user's message — the
    /// same "the user named this target" signal that vouches for a typed URL. Checked as a raw
    /// case-insensitive substring, NOT a token match: the request tokenizer splits `greeting.py`
    /// into `greeting`/`py`, so "In greeting.py, add …" only vouches for `python3 greeting.py`
    /// when the whole filename is matched as a substring. A short/extensionless argument is ignored
    /// (a bare `test`/`build` subcommand must not be treated as a named file).
    private static func commandTargetsRequestedPath(_ arguments: [String], userMessage: String) -> Bool {
        let haystack = userMessage.lowercased()
        let named = arguments.filter { arg in
            guard !arg.hasPrefix("-") else { return false }
            guard arg.contains(".") || arg.contains("/") else { return false }
            return arg.count >= 4
        }
        guard !named.isEmpty else { return false }
        return named.contains { haystack.contains($0.lowercased()) }
    }
}
