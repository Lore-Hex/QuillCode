import Foundation

/// The data-driven lexicon of what a "test / verify" command looks like.
///
/// The single precision rule that governs everything here: a command is a test command only when the
/// test RUNNER is in COMMAND POSITION — the actual program being run (argv[0]) in one of the command's
/// `&&`/`||`/`;`/`|`-separated segments — never when a runner name merely appears buried in the
/// arguments. So `pytest tests/` is a test command, but `grep -rn pytest .`, `which pytest`, and
/// `grep -q 'go test' Makefile` are NOT (their argv[0] is `grep`/`which`). This is what keeps a
/// genuinely-good `grep` that happens to mention a runner from being classified as a failed test.
public enum TestCommandLexicon {
    /// The parsed test-command identity for a command line. `scope` is the identity used to decide
    /// "the SAME test was re-run" — the runner plus its normalized target arguments — so a green run of
    /// an UNRELATED suite cannot clear a different suite's failure.
    public struct Match: Sendable, Hashable {
        /// The recognized runner in command position (e.g. "pytest", "swift test", "xcodebuild test").
        public var runner: String
        /// A normalized identity for the specific test invocation (runner + target path/args in the
        /// matched segment), used for same-scope re-run matching.
        public var scope: String
    }

    /// Single-program test runners: argv[0]'s basename alone means "running tests" (no subcommand
    /// needed). Matched against the command basename, case-insensitively.
    public static let runnerBasenames: [String] = [
        "pytest",
        "py.test",
        "nosetests",
        "jest",
        "vitest",
        "mocha",
        "ava",
        "rspec",
        "phpunit",
        "gotestsum",
        "ctest",
        "tox",
        "nose2",
        "xctest",
        "karma",
        "cypress",
        "playwright",
    ]

    /// Build/package drivers where a `test`/`check` SUBCOMMAND (as an argument in the same segment) means
    /// "running tests" — e.g. `swift test`, `go test`, `cargo test`, `npm test`, `make test`,
    /// `xcodebuild -scheme X test`. Keyed by the driver's argv[0] basename → the subcommand tokens that
    /// turn it into a test run.
    public static let driverSubcommands: [String: Set<String>] = [
        "swift": ["test"],
        "go": ["test"],
        "cargo": ["test", "nextest"],
        "npm": ["test", "t"],
        "yarn": ["test"],
        "pnpm": ["test"],
        "bun": ["test"],
        "make": ["test", "check"],
        "gradle": ["test", "check"],
        "gradlew": ["test", "check"],
        "mvn": ["test", "verify"],
        "dotnet": ["test"],
        "rake": ["test", "spec"],
        "rails": ["test"],
        "bazel": ["test"],
        "ninja": ["test"],
        "xcodebuild": ["test", "test-without-building", "build-for-testing"],
        "nx": ["test", "e2e"],
    ]

    /// Drivers that legitimately place FLAGS before the test subcommand, so the subcommand is matched
    /// anywhere in the args (e.g. `xcodebuild -scheme App test`). Every other driver requires the
    /// subcommand to be the first non-flag argument, which prevents a `test`-looking FILE argument
    /// (`go run test.go`, `make build test-data`) from being read as the subcommand.
    public static let flagsBeforeSubcommandDrivers: Set<String> = ["xcodebuild"]

    /// `npm`/`yarn`/`pnpm run <script>` where the script name is test-shaped (`test`, `test:unit`, …).
    public static let scriptRunnerBasenames: Set<String> = ["npm", "yarn", "pnpm", "bun"]

    /// Test SCRIPT paths: a command whose argv[0] basename is itself a test script (e.g. `./scripts/
    /// test.sh`, `bin/run-tests`, `tools/runtests`). Matched on the basename (path stripped).
    public static let testScriptBasenames: [String] = [
        "test.sh",
        "tests.sh",
        "runtests",
        "runtests.sh",
        "run-tests",
        "run-tests.sh",
        "run_tests",
        "run_tests.sh",
        "test.py",
        "runtests.py",
        "test.bat",
        "check.sh",
    ]

    /// Command wrappers that pass through to the REAL command: `sudo pytest`, `env FOO=1 pytest`,
    /// `time swift test`, `nice -n10 go test`, `xargs -0 pytest`, `npx jest`. Stripped (with their own
    /// flags) before reading argv[0]. Deliberately EXCLUDES the package drivers `npm`/`yarn`/`pnpm`/`bun`
    /// — those are test drivers in their own right (`yarn test`), so stripping them would lose the match.
    public static let passthroughWrappers: Set<String> = [
        "sudo", "env", "time", "nice", "nohup", "stdbuf", "xargs", "command", "exec",
        "npx", "pnpx",
    ]

    /// Wrappers of the shape `<wrapper> run/exec <program>` (e.g. `poetry run pytest`, `pipenv run
    /// pytest`, `uv run pytest`, `bundle exec rspec`). The wrapper AND the `run`/`exec` verb are stripped
    /// so argv[0] becomes the wrapped program.
    public static let runVerbWrappers: [String: Set<String>] = [
        "poetry": ["run"],
        "pipenv": ["run"],
        "uv": ["run"],
        "rye": ["run"],
        "hatch": ["run"],
        "bundle": ["exec"],
        "pdm": ["run"],
    ]

    /// Classifies a shell command line, returning a `Match` when a test runner is in command position in
    /// any of its segments, else nil. Pure and bounded.
    public static func classify(_ command: String) -> Match? {
        let lowered = command.lowercased()
        guard !lowered.isEmpty else { return nil }
        for segment in commandSegments(in: lowered) {
            if let match = classifySegment(segment) {
                return match
            }
        }
        return nil
    }

    /// Back-compat boolean wrapper.
    public static func looksLikeTestCommand(_ command: String) -> Bool {
        classify(command) != nil
    }

    /// Splits a command line into the segments separated by shell control operators `&&`, `||`, `;`,
    /// `|`, `&`. Each segment is classified independently (its own argv[0]).
    ///
    /// QUOTE-AWARE: an operator inside single/double quotes OR backticks (command substitution) does NOT
    /// split, so a runner name inside a quoted argument of a non-runner command — `echo "run && pytest
    /// tests"`, `git commit -m "fix; pytest later"`, `echo \`pytest\`` — is never carved into a synthetic
    /// `pytest …` segment (which would falsely classify it as a test). If quotes are UNBALANCED (a parse
    /// we can't trust), we conservatively do NOT split at all and treat the whole line as one segment —
    /// better to miss a real `&&`-chained test (false negative, safe) than to manufacture a phantom test
    /// in a non-command position.
    static func commandSegments(in lowered: String) -> [String] {
        let scalars = Array(lowered)
        guard quotesAreBalanced(scalars) else {
            let trimmed = lowered.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        var segments: [String] = []
        var current = ""
        var quote: Character?
        var i = 0
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { segments.append(trimmed) }
            current = ""
        }
        while i < scalars.count {
            let c = scalars[i]
            if let open = quote {
                current.append(c)
                if c == open { quote = nil }
                i += 1
                continue
            }
            if isQuoteChar(c) {
                quote = c; current.append(c); i += 1; continue
            }
            let next: Character? = i + 1 < scalars.count ? scalars[i + 1] : nil
            if (c == "&" && next == "&") || (c == "|" && next == "|") {
                flush(); i += 2; continue
            }
            if c == ";" || c == "|" || c == "&" || c == "\n" {
                flush(); i += 1; continue
            }
            current.append(c)
            i += 1
        }
        flush()
        return segments
    }

    static func isQuoteChar(_ c: Character) -> Bool {
        c == "'" || c == "\"" || c == "`"
    }

    /// Whether single/double quotes and backticks are balanced (naive, quote-nesting-aware: a `"` inside
    /// `'…'` is literal and vice-versa). Used to decide whether the quote-aware split can be trusted.
    static func quotesAreBalanced(_ scalars: [Character]) -> Bool {
        var quote: Character?
        for c in scalars {
            if let open = quote {
                if c == open { quote = nil }
            } else if isQuoteChar(c) {
                quote = c
            }
        }
        return quote == nil
    }

    /// Presence-probe commands: the following program is DESCRIBED, not executed, so a nonzero exit is
    /// "not installed", never a test failure. `which pytest`, `type pytest`, `command -v pytest`,
    /// `command -V pytest`, `hash pytest`. These must NEVER classify as a test.
    static let presenceProbePrograms: Set<String> = ["which", "type", "hash", "whereis"]

    /// Classifies one already-lowercased segment by reading its argv[0] (after stripping env-assignments
    /// and passthrough wrappers) and, for build drivers, checking for a test subcommand.
    static func classifySegment(_ segment: String) -> Match? {
        let rawTokens = strippingLeadingEnv(tokenize(segment))
        // Presence probes describe a program rather than run it — never a test, even if the argument is a
        // runner name. `command -v pytest`, `which pytest`, `type -a pytest`.
        if isPresenceProbe(rawTokens) { return nil }

        let tokens = strippingLeadingWrappers(rawTokens)
        guard let head = tokens.first else { return nil }
        let program = basename(head)

        // 0. `python -m <testmodule>` / `python3 -m pytest`: the module after `-m` is the real runner
        //    (argv[0] is only the interpreter). Recognized in command position, not by substring.
        if let match = pythonModuleMatch(tokens) {
            return match
        }

        // 1. Bare single-program runners: argv[0] basename alone is enough.
        if runnerBasenames.contains(program) {
            return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
        }

        // 2. Test SCRIPT paths (argv[0] basename is a known test script).
        if testScriptBasenames.contains(program) {
            return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
        }

        // 3. Build/package drivers with a test/check subcommand.
        //    For most drivers the subcommand is the FIRST non-flag argument (`go test`, `make check`) —
        //    requiring that avoids a false positive when the token appears as a FILE arg later
        //    (`go run test.go`, `make build test-data`). A few tools (xcodebuild) legitimately put flags
        //    BEFORE the subcommand (`xcodebuild -scheme X test`), so those match the token anywhere.
        if let subcommands = driverSubcommands[program] {
            let argTokens = Array(tokens.dropFirst())
            let subcommandMatches: Bool
            if flagsBeforeSubcommandDrivers.contains(program) {
                subcommandMatches = argTokens.contains(where: { subcommands.contains($0) })
            } else {
                subcommandMatches = firstNonFlagArgument(argTokens).map { subcommands.contains($0) } ?? false
            }
            if subcommandMatches {
                return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
            }
            if scriptRunnerBasenames.contains(program), isTestScriptRun(argTokens) {
                return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
            }
        }

        // 4. `npm run test:unit` shape not covered by a plain `test` token.
        if scriptRunnerBasenames.contains(program), isTestScriptRun(tokens.dropFirst()) {
            return Match(runner: program, scope: scopeKey(runner: program, tokens: tokens))
        }

        return nil
    }

    /// Test modules invoked via `python -m <module>` (or `python3`/`py`). The module IS the runner.
    public static let pythonTestModules: Set<String> = [
        "pytest", "unittest", "nose", "nose2", "tox", "green", "ward", "behave", "trial",
    ]

    /// The Python interpreters that front a `-m <module>` invocation.
    static let pythonInterpreters: Set<String> = ["python", "python3", "python2", "py", "pypy", "pypy3"]

    /// Recognizes `python[3] -m <testmodule> …`: the interpreter is argv[0], `-m` selects a module, and
    /// when that module is a known test runner the command IS a test run. The scope keys off the module
    /// plus its target args so different `-m pytest tests/x` vs `tests/y` stay distinct.
    static func pythonModuleMatch(_ tokens: [String]) -> Match? {
        guard let head = tokens.first, pythonInterpreters.contains(basename(head)) else { return nil }
        // Find `-m` and the module token immediately after it.
        var index = 1
        while index < tokens.count {
            if tokens[index] == "-m", index + 1 < tokens.count {
                let module = tokens[index + 1]
                guard pythonTestModules.contains(module) else { return nil }
                // Scope: the module + the arguments AFTER it (targets), so `-m pytest tests/auth` and
                // `-m pytest tests/utils` differ. Reuse scopeKey over [module, targets…].
                let moduleAndTargets = [module] + tokens[(index + 2)...]
                return Match(runner: "python -m \(module)", scope: scopeKey(runner: module, tokens: moduleAndTargets))
            }
            index += 1
        }
        return nil
    }

    /// Whether the (env-stripped) tokens are a presence probe rather than an execution: `which pytest`,
    /// `type pytest`, `hash pytest`, `command -v pytest`, `command -V pytest`.
    static func isPresenceProbe(_ tokens: [String]) -> Bool {
        guard let head = tokens.first else { return false }
        let program = basename(head)
        if presenceProbePrograms.contains(program) { return true }
        // `command -v`/`-V <program>`: describes, does not run.
        if program == "command", tokens.count >= 2 {
            let flag = tokens[1]
            if flag == "-v" || flag == "-V" { return true }
        }
        return false
    }

    /// Strips only leading `NAME=value` env-assignments (not wrappers) — used before the presence-probe
    /// check so `FOO=1 which pytest` is still recognized as a probe.
    static func strippingLeadingEnv(_ tokens: [String]) -> [String] {
        var remaining = tokens
        while let head = remaining.first, isEnvAssignment(head) {
            remaining.removeFirst()
        }
        return remaining
    }

    /// A `run <script>` invocation where the script name is test-shaped: `test`, `test:unit`,
    /// `unit-test`, `test-integration`, etc. — the script token immediately follows `run`.
    static func isTestScriptRun<S: Sequence>(_ argTokens: S) -> Bool where S.Element == String {
        var previous: String?
        for token in argTokens {
            if previous == "run", isTestScriptName(token) { return true }
            previous = token
        }
        return false
    }

    /// The first argument that is not a `-flag`. Used to read a driver's subcommand position: `go test`
    /// → `test`; `go -C dir test` → `test`; `go run test.go` → `run` (so it does NOT match the `test`
    /// subcommand).
    static func firstNonFlagArgument(_ argTokens: [String]) -> String? {
        argTokens.first { !$0.hasPrefix("-") }
    }

    static func isTestScriptName(_ name: String) -> Bool {
        // Word-boundary "test"/"spec" inside a script name (test, test:unit, unit-test, tests), but not a
        // random word merely containing the substring (e.g. "attestation").
        let separators = CharacterSet(charactersIn: ":-_./")
        let parts = name.components(separatedBy: separators)
        return parts.contains("test") || parts.contains("tests") || parts.contains("spec")
    }

    /// Strips leading `NAME=value` env-assignments and passthrough wrappers (with their flags) so argv[0]
    /// is the real program. `FOO=1 sudo -E pytest -q` → argv[0] `pytest`.
    static func strippingLeadingWrappers(_ tokens: [String]) -> [String] {
        var remaining = tokens
        var progressed = true
        while progressed, let head = remaining.first {
            progressed = false
            // Env-assignment: NAME=value (NAME is an identifier).
            if isEnvAssignment(head) {
                remaining.removeFirst(); progressed = true; continue
            }
            let program = basename(head)
            // `<wrapper> run/exec <program>`: strip the wrapper AND the run/exec verb.
            if let verbs = runVerbWrappers[program], remaining.count >= 2, verbs.contains(remaining[1]) {
                remaining.removeFirst(2)
                progressed = true
                continue
            }
            if passthroughWrappers.contains(program) {
                remaining.removeFirst()
                // Drop the wrapper's own leading flags/args conservatively: only obvious ones so we do
                // not accidentally consume the real program. `nice -n 10`, `env -i`, `xargs -0`.
                remaining = droppingWrapperFlags(remaining)
                progressed = true
                continue
            }
        }
        return remaining
    }

    /// Drops leading `-flag` tokens (and a following value for the few flags that take one) belonging to
    /// a stripped wrapper. Conservative: stops at the first non-flag token (the real program).
    static func droppingWrapperFlags(_ tokens: [String]) -> [String] {
        var remaining = tokens
        while let head = remaining.first, head.hasPrefix("-") {
            remaining.removeFirst()
            // `nice -n 10`: a bare short flag may take the next token as its value — but only a pure
            // number, and never a known program (so `time -p go test` does not swallow `go`).
            if head.count == 2, let next = remaining.first, !next.hasPrefix("-"), isFlagValue(next) {
                remaining.removeFirst()
            }
        }
        return remaining
    }

    /// A conservative "looks like a flag value, not a program" test — a pure number (`nice -n 10`) — and
    /// NEVER a token that is itself a known program name, so a short driver like `go` (`time -p go test`)
    /// is not swallowed as if it were a flag's value.
    static func isFlagValue(_ token: String) -> Bool {
        guard !isKnownProgram(basename(token)) else { return false }
        return token.allSatisfy { $0.isNumber }
    }

    /// Whether a basename is one of the programs the lexicon recognizes (runner, driver, wrapper, or test
    /// script) — used to avoid mistaking the real program for a flag's value.
    static func isKnownProgram(_ program: String) -> Bool {
        runnerBasenames.contains(program)
            || driverSubcommands.keys.contains(program)
            || passthroughWrappers.contains(program)
            || runVerbWrappers.keys.contains(program)
            || scriptRunnerBasenames.contains(program)
            || testScriptBasenames.contains(program)
    }

    static func isEnvAssignment(_ token: String) -> Bool {
        guard let eq = token.firstIndex(of: "="), eq != token.startIndex else { return false }
        let name = token[token.startIndex..<eq]
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Whitespace tokenizer (quote-naive, bounded). Good enough for reading argv[0]/subcommands.
    static func tokenize(_ segment: String) -> [String] {
        segment.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    /// The trailing path component of a token, so `./scripts/test.sh` → `test.sh`, `/usr/bin/pytest` →
    /// `pytest`, `bin/rails` → `rails`.
    static func basename(_ token: String) -> String {
        let stripped = token.hasPrefix("./") ? String(token.dropFirst(2)) : token
        return stripped.split(separator: "/").last.map(String.init) ?? stripped
    }

    /// Selector flags whose VALUE names the specific suite/target being run. Their value MUST enter the
    /// scope key — otherwise `cargo test --test=auth_it` and `--test=utils_it` collapse to the same
    /// scope and an unrelated green run falsely clears a red one (the trust hole). Both attached
    /// (`--test=auth`) and separated (`--test auth`, `-k auth`) forms are handled.
    static let selectorFlags: Set<String> = [
        "--test", "--package", "-p", "--bin", "--example", "--features",
        "--testpathpattern", "--testnamepattern", "--config", "-c",
        "-k", "--filter", "--group", "--suite", "--only", "--scheme", "--target",
        "--project", "--spec", "--grep", "-g", "--name", "--tests", "--run",
    ]

    /// Identity for same-scope re-run matching: runner + the target-ish arguments (positional paths AND
    /// selector-flag VALUES) normalized. Two invocations of the same suite share a scope; two different
    /// suites — whether selected positionally (`pytest tests/auth` vs `tests/utils`) or by flag
    /// (`cargo test --test=auth` vs `--test=utils`, `pytest -k auth` vs `-k utils`) — do NOT.
    ///
    /// CONSERVATIVE: non-selector flags are ignored (so a bare re-run with extra `-v` still matches), but
    /// every selector value is INCLUDED. When in doubt we prefer MORE distinct scopes — a scope that is
    /// too fine only means the RED rule falls back to exact-command identity (which never falsely
    /// clears), whereas a scope that is too coarse would hide a standing failure.
    static func scopeKey(runner: String, tokens: [String]) -> String {
        var parts: [String] = []
        let args = Array(tokens.dropFirst())
        var index = 0
        while index < args.count {
            let token = args[index]
            if token.hasPrefix("-") {
                // Attached form: `--test=auth`, `-kauth`, `-k=auth`.
                if let (flag, value) = attachedSelector(token) {
                    parts.append("\(flag)=\(value)")
                    index += 1
                    continue
                }
                // Separated form: `--test auth`, `-k auth`.
                if selectorFlags.contains(token), index + 1 < args.count, !args[index + 1].hasPrefix("-") {
                    parts.append("\(token)=\(args[index + 1])")
                    index += 2
                    continue
                }
                index += 1 // a non-selector flag — ignored
                continue
            }
            // Positional target (path, scheme name, subcommand).
            parts.append(token)
            index += 1
        }
        return "\(runner)|\(parts.joined(separator: " "))"
    }

    /// Parses an attached-value selector flag: `--test=auth` → ("--test", "auth"); `-kauth` →
    /// ("-k", "auth"); `-k=auth` → ("-k", "auth"). Returns nil for non-selector or valueless flags.
    static func attachedSelector(_ token: String) -> (flag: String, value: String)? {
        // Long form `--flag=value`.
        if token.hasPrefix("--"), let eq = token.firstIndex(of: "=") {
            let flag = String(token[token.startIndex..<eq])
            let value = String(token[token.index(after: eq)...])
            if selectorFlags.contains(flag), !value.isEmpty { return (flag, value) }
            return nil
        }
        // Short form `-kVALUE` or `-k=VALUE`.
        if token.hasPrefix("-"), !token.hasPrefix("--"), token.count > 2 {
            let flag = String(token.prefix(2)) // e.g. "-k"
            guard selectorFlags.contains(flag) else { return nil }
            var value = String(token.dropFirst(2))
            if value.hasPrefix("=") { value = String(value.dropFirst()) }
            if !value.isEmpty { return (flag, value) }
        }
        return nil
    }

    /// Substring match with cheap word-ish boundaries. Retained for `SuccessClaimLexicon` reuse so there
    /// is a single word-boundary implementation.
    static func containsToken(_ token: String, in haystack: String) -> Bool {
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: token, options: [], range: searchRange) {
            let beforeOK = found.lowerBound == haystack.startIndex
                || !isWordScalar(haystack[haystack.index(before: found.lowerBound)])
            let afterOK = found.upperBound == haystack.endIndex
                || !isWordScalar(haystack[found.upperBound])
            if beforeOK && afterOK { return true }
            if found.upperBound >= haystack.endIndex { break }
            searchRange = haystack.index(after: found.lowerBound)..<haystack.endIndex
        }
        return false
    }

    static func isWordScalar(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

/// The data-driven lexicon of assistant success claims. Anchored so an incidental "passes" in prose
/// does not trip UNVERIFIED; every phrase reads as a claim about tests/checks passing.
public enum SuccessClaimLexicon {
    public static let claimPhrases: [String] = [
        "tests pass",
        "tests passed",
        "tests are passing",
        "all tests pass",
        "all tests passed",
        "all tests passing",
        "all tests are passing",
        "test suite passes",
        "test suite passed",
        "tests are green",
        "all green",
        "everything passes",
        "everything is passing",
        "all checks pass",
        "all checks passed",
        "checks pass",
        "build passes",
        "build passed",
        "verified the tests",
        "tests now pass",
        "the tests pass",
    ]

    /// Matches a claim phrase only when it appears WORD-BOUNDED in the text — reusing the single
    /// word-boundary implementation in `TestCommandLexicon.containsToken`. This is what makes the phrases
    /// truly "anchored" as the docs promise: "all green" no longer matches "instALL GREEN-tea-cli", and
    /// "checks pass" no longer matches "preCHECKS PASS through", because a word scalar sits on the phrase
    /// boundary in those.
    public static func matchedClaim(in loweredText: String) -> String? {
        guard !loweredText.isEmpty else { return nil }
        for phrase in claimPhrases where TestCommandLexicon.containsToken(phrase, in: loweredText) {
            return phrase
        }
        return nil
    }
}
