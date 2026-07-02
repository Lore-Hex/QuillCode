import Foundation

/// The post-run integrity verdict for a completed agent run: was "finished" honest?
///
/// This mechanizes the never-skip-tests rule so a human (or the morning-triage inbox) does not have to
/// read the transcript to trust the run. It is deliberately a THREE-state badge with a HIGH-PRECISION
/// bias: `unverified` and `red` are only raised on positive evidence of a problem, never on the mere
/// absence of tests. When in doubt the scanner prefers `verified` over a false alarm, because a badge
/// that cries wolf is a badge nobody reads.
public enum RunIntegrityVerdict: String, Codable, Sendable, Hashable {
    /// Nothing dishonest was detected: any success claim is backed by a real successful test/command
    /// result, and no test/verify command was left failing. This is also the verdict for a benign run
    /// that made no success claims and left no failing tests standing.
    case verified

    /// A success claim ("tests pass", "all green", "verified") has NO successful test/command result
    /// backing it, OR a test that was started/expected was silently skipped. An honest "we cannot vouch
    /// for this" — not necessarily a failure, but not a checked green either.
    case unverified

    /// A test/verify command exited nonzero and the failure was left standing (never re-run green). The
    /// run "finished" on top of a known-red check.
    case red

    /// Badge text surfaced in Activity and the finish notification.
    public var badgeLabel: String {
        switch self {
        case .verified: return "VERIFIED"
        case .unverified: return "UNVERIFIED"
        case .red: return "RED"
        }
    }
}

/// A single reason the scanner reached its verdict, kept for inspectability (the badge tooltip, the
/// notification body, and — crucially — debugging false positives). Each reason names the rule that
/// fired so the rule set stays auditable.
public struct RunIntegrityReason: Sendable, Hashable {
    public enum Rule: String, Sendable, Hashable {
        /// A test/verify command failed and was never re-run successfully. -> RED
        case standingTestFailure
        /// The model claimed success but no successful test/command result backs it. -> UNVERIFIED
        case unbackedSuccessClaim
        /// A test command was queued/started but produced no completed result (silently skipped). -> UNVERIFIED
        case skippedTest
        /// A success claim is backed by an actual successful test/command result. -> VERIFIED (evidence)
        case backedSuccessClaim
        /// A test/verify command failed but a later run of it (or a test command) passed. -> VERIFIED (evidence)
        case failureThenRerunGreen
    }

    public var rule: Rule
    public var detail: String

    public init(rule: Rule, detail: String) {
        self.rule = rule
        self.detail = detail
    }
}

/// The full result of a run-integrity scan: the badge verdict plus the reasons behind it.
public struct RunIntegrityReport: Sendable, Hashable {
    public var verdict: RunIntegrityVerdict
    public var reasons: [RunIntegrityReason]

    public init(verdict: RunIntegrityVerdict, reasons: [RunIntegrityReason] = []) {
        self.verdict = verdict
        self.reasons = reasons
    }

    /// A one-line, human-readable summary for the notification body / badge tooltip. Never empty.
    public var summaryLine: String {
        switch verdict {
        case .verified:
            if let backed = reasons.first(where: { $0.rule == .backedSuccessClaim || $0.rule == .failureThenRerunGreen }) {
                return backed.detail
            }
            return "No standing test failures or unbacked claims."
        case .unverified:
            return reasons.first(where: { $0.rule == .unbackedSuccessClaim || $0.rule == .skippedTest })?.detail
                ?? "A success claim is not backed by a passing test."
        case .red:
            return reasons.first(where: { $0.rule == .standingTestFailure })?.detail
                ?? "A test failure was left standing."
        }
    }
}

/// Scans a completed run's transcript (messages + tool calls/results) and classifies it VERIFIED /
/// UNVERIFIED / RED. Pure, deterministic, and bounded — it never performs I/O, never force-unwraps, and
/// caps the text it scans — so it is fully unit-testable and can never crash on a hostile transcript.
///
/// ## Rule set (high-precision, ordered by severity)
///
/// 1. **RED — standing test failure.** A *test/verify* command tool call exited nonzero and no *later*
///    test/verify command (or a re-run of the same command string) exited zero. Only test/verify
///    failures redden a run: a bare `grep`/`test -f`/`diff` returning nonzero is a normal control-flow
///    signal, not a broken build, so generic shell failures are deliberately ignored to keep precision
///    high.
///
/// 2. **UNVERIFIED — unbacked success claim.** The assistant's *text* claims success ("tests pass",
///    "all green", "everything passing", "verified") but the run contains NO successful test/command
///    result to back it. The claim phrases are anchored (they must read as a claim about tests/checks,
///    not an incidental "this class passes the token to…") to avoid false yellows.
///
/// 3. **UNVERIFIED — silently skipped test.** A test command was queued/started but never produced a
///    completed result (e.g. the run ended mid-flight, or the tool was abandoned), so the test that was
///    expected did not actually run.
///
/// 4. **VERIFIED — everything else.** Success claims are backed by real successful results; failures
///    were re-run green; or the run simply made no claims and left nothing red. Absence of tests is NOT
///    an alarm.
public enum RunIntegrityScanner {
    /// Hard cap on how much assistant text (per message) we scan for claim phrases. A pathological
    /// multi-megabyte message must not turn the scan superlinear; claims live in the first paragraphs.
    static let maxClaimScanCharacters = 20_000

    /// Hard cap on the number of tool steps we pair up, so a runaway transcript stays bounded.
    static let maxToolStepsScanned = 5_000

    public static func scan(_ thread: ChatThread) -> RunIntegrityReport {
        let steps = commandSteps(in: thread)

        // Rule 1 (RED): a standing test/verify failure dominates every other signal.
        if let standing = standingTestFailure(in: steps) {
            return RunIntegrityReport(verdict: .red, reasons: [standing])
        }

        var reasons: [RunIntegrityReason] = []

        // Evidence: did any test/verify command pass in this run? (backs success claims).
        let hasSuccessfulTestRun = steps.contains { $0.isTestCommand && $0.succeeded }

        // Rule 2 (UNVERIFIED): a success claim with no passing test/command to back it.
        if let claim = firstSuccessClaim(in: thread) {
            if hasSuccessfulTestRun {
                reasons.append(RunIntegrityReason(
                    rule: .backedSuccessClaim,
                    detail: "Success claim backed by a passing test command."
                ))
            } else {
                reasons.append(RunIntegrityReason(
                    rule: .unbackedSuccessClaim,
                    detail: "Claimed \"\(claim)\" but no passing test command backs it."
                ))
                return RunIntegrityReport(verdict: .unverified, reasons: reasons)
            }
        }

        // Rule 3 (UNVERIFIED): a test command was started but never completed (silently skipped).
        if let skipped = skippedTest(in: thread) {
            reasons.append(skipped)
            return RunIntegrityReport(verdict: .unverified, reasons: reasons)
        }

        // Rule 4 (VERIFIED): note re-run-green evidence when present, for an informative badge.
        if let rerun = failureThenRerunGreenReason(in: steps) {
            reasons.append(rerun)
        }
        return RunIntegrityReport(verdict: .verified, reasons: reasons)
    }

    /// Convenience: just the badge verdict.
    public static func verdict(for thread: ChatThread) -> RunIntegrityVerdict {
        scan(thread).verdict
    }

    // MARK: - Command step extraction

    /// A paired command tool call and its result, in transcript order. The pairing is positional: each
    /// `toolQueued` event carries the `ToolCall`; the next `toolCompleted`/`toolFailed` event carries the
    /// `ToolResult`. We only keep steps whose tool is a shell/command runner.
    struct CommandStep: Sendable, Hashable {
        var command: String
        var isTestCommand: Bool
        var succeeded: Bool
    }

    static func commandSteps(in thread: ChatThread) -> [CommandStep] {
        var steps: [CommandStep] = []
        var pendingCall: ToolCall?

        for event in thread.events {
            if steps.count >= maxToolStepsScanned { break }
            switch event.kind {
            case .toolQueued:
                pendingCall = decodeCall(event.payloadJSON)
            case .toolRunning:
                // No payload of interest; keep the pending call as-is.
                continue
            case .toolCompleted, .toolFailed:
                defer { pendingCall = nil }
                guard let call = pendingCall, isCommandTool(call.name) else { continue }
                let result = decodeResult(event.payloadJSON)
                let command = shellCommand(from: call)
                steps.append(CommandStep(
                    command: command,
                    isTestCommand: TestCommandLexicon.looksLikeTestCommand(command),
                    // A completed event means ok; a failed event OR an explicit non-ok result means not.
                    succeeded: event.kind == .toolCompleted && (result?.ok ?? true)
                ))
            default:
                continue
            }
        }
        return steps
    }

    // MARK: - Rule 1: standing test failure (RED)

    static func standingTestFailure(in steps: [CommandStep]) -> RunIntegrityReason? {
        // Find the LAST failing test command; if it was re-run green afterward the failure was
        // addressed and does not redden the run.
        guard let lastFailIndex = steps.lastIndex(where: { $0.isTestCommand && !$0.succeeded }),
              !hasLaterGreenRerun(ofFailureAt: lastFailIndex, in: steps) else {
            return nil
        }
        return RunIntegrityReason(
            rule: .standingTestFailure,
            detail: "Test command failed and was not re-run green: \(shortCommand(steps[lastFailIndex].command))."
        )
    }

    static func failureThenRerunGreenReason(in steps: [CommandStep]) -> RunIntegrityReason? {
        guard let failIndex = steps.firstIndex(where: { $0.isTestCommand && !$0.succeeded }),
              hasLaterGreenRerun(ofFailureAt: failIndex, in: steps) else {
            return nil
        }
        return RunIntegrityReason(
            rule: .failureThenRerunGreen,
            detail: "A failing test was re-run and passed."
        )
    }

    /// Whether a later step re-runs the failed test green — either any passing test command, or a
    /// passing run of the exact same command string. The single source of truth for "the failure was
    /// addressed", shared by the RED rule and the informational re-run-green reason so they never drift.
    static func hasLaterGreenRerun(ofFailureAt failIndex: Int, in steps: [CommandStep]) -> Bool {
        let failedCommand = steps[failIndex].command
        return steps[(failIndex + 1)...].contains { later in
            later.succeeded && (later.isTestCommand || sameCommand(later.command, failedCommand))
        }
    }

    // MARK: - Rule 3: silently skipped test (UNVERIFIED)

    /// A test command that was queued but for which no matching result event was ever recorded — the
    /// test the run set out to run never actually reported back.
    ///
    /// Uses a single "pending" slot, tracking only the most recent queued command; this is deliberate.
    /// The agent's tool loop is strictly sequential (queue → run → result before the next queue), so the
    /// slot is exactly right there. If tools were ever emitted interleaved/in parallel, a later queue
    /// would clobber an earlier dangling test — under-reporting a skip (a false NEGATIVE), never
    /// inventing one. That direction is consistent with the high-precision bias: silence beats a false
    /// yellow.
    static func skippedTest(in thread: ChatThread) -> RunIntegrityReason? {
        var pendingTestCommand: String?
        var scanned = 0
        for event in thread.events {
            if scanned >= maxToolStepsScanned { break }
            switch event.kind {
            case .toolQueued:
                guard let call = decodeCall(event.payloadJSON), isCommandTool(call.name) else {
                    pendingTestCommand = nil
                    continue
                }
                let command = shellCommand(from: call)
                pendingTestCommand = TestCommandLexicon.looksLikeTestCommand(command) ? command : nil
            case .toolRunning:
                continue
            case .toolCompleted, .toolFailed:
                scanned += 1
                pendingTestCommand = nil
            default:
                continue
            }
        }
        guard let dangling = pendingTestCommand else { return nil }
        return RunIntegrityReason(
            rule: .skippedTest,
            detail: "A test command was started but never completed: \(shortCommand(dangling))."
        )
    }

    // MARK: - Rule 2: success-claim detection (UNVERIFIED)

    /// The first assistant success claim found, or nil. Only the assistant's own words count (tool
    /// output echoed back is not a claim BY the model). Anchored phrases keep this high-precision.
    static func firstSuccessClaim(in thread: ChatThread) -> String? {
        for message in thread.messages where message.role == .assistant {
            let text = boundedLowercased(message.content)
            if let phrase = SuccessClaimLexicon.matchedClaim(in: text) {
                return phrase
            }
        }
        return nil
    }

    // MARK: - Decoding helpers (never throwing, never force-unwrapping)

    static func decodeCall(_ payloadJSON: String?) -> ToolCall? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(ToolCall.self, from: payloadJSON)
    }

    static func decodeResult(_ payloadJSON: String?) -> ToolResult? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(ToolResult.self, from: payloadJSON)
    }

    /// The tool that RUNs a shell command (and can therefore carry a test result / nonzero exit). The
    /// name is duplicated as a literal here rather than referencing `ToolDefinition.shellRun` (which
    /// lives in QuillCodeTools) so this scanner stays in the dependency-free Core layer. Guarded by a
    /// parity test so the two can never drift.
    public static let shellRunToolName = "host.shell.run"

    /// The set of tools that RUN a command. Kept as an inspectable predicate rather than a scattered
    /// string literal so the rule is auditable and easy to extend.
    static func isCommandTool(_ name: String) -> Bool {
        name == shellRunToolName
    }

    static func shellCommand(from call: ToolCall) -> String {
        (try? ToolArguments(call.argumentsJSON))?.string("cmd") ?? ""
    }

    static func sameCommand(_ lhs: String, _ rhs: String) -> Bool {
        normalizedCommand(lhs) == normalizedCommand(rhs) && !normalizedCommand(lhs).isEmpty
    }

    static func normalizedCommand(_ command: String) -> String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shortCommand(_ command: String) -> String {
        let trimmed = normalizedCommand(command)
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        guard firstLine.count > 60 else { return firstLine }
        let cut = firstLine.index(firstLine.startIndex, offsetBy: 60)
        return String(firstLine[..<cut]) + "…"
    }

    static func boundedLowercased(_ text: String) -> String {
        guard text.count > maxClaimScanCharacters else { return text.lowercased() }
        let cut = text.index(text.startIndex, offsetBy: maxClaimScanCharacters)
        return String(text[..<cut]).lowercased()
    }
}

/// Persists a `RunIntegrityReport` onto a thread as a `.notice` event so the badge is STABLE across
/// reloads (the thread is the run, and `JSONThreadStore` round-trips its events). Reuses the notice-event
/// convention already used for other post-hoc annotations (memory-redaction review) — no schema change.
public enum RunIntegrityRecord {
    /// The well-known summary marker that identifies the integrity notice among a thread's events.
    public static let eventSummary = "run-integrity-report"

    /// The Codable payload stored in the notice event's `payloadJSON`.
    public struct Payload: Codable, Sendable, Hashable {
        public var verdict: RunIntegrityVerdict
        public var summary: String

        public init(verdict: RunIntegrityVerdict, summary: String) {
            self.verdict = verdict
            self.summary = summary
        }
    }

    /// Builds the notice event for a report. Returns nil only if encoding somehow fails (never throws).
    public static func event(for report: RunIntegrityReport) -> ThreadEvent? {
        let payload = Payload(verdict: report.verdict, summary: report.summaryLine)
        guard let payloadJSON = try? JSONHelpers.encodePretty(payload) else { return nil }
        return ThreadEvent(kind: .notice, summary: eventSummary, payloadJSON: payloadJSON)
    }

    /// The most recently recorded integrity verdict on a thread, or nil if none was ever recorded. The
    /// LAST matching notice wins, so a re-scan after a follow-up turn supersedes an earlier badge.
    public static func latest(in thread: ChatThread) -> Payload? {
        for event in thread.events.reversed() where isRecord(event) {
            if let payloadJSON = event.payloadJSON,
               let payload = try? JSONHelpers.decode(Payload.self, from: payloadJSON) {
                return payload
            }
        }
        return nil
    }

    /// Scans the thread, then records the resulting verdict as a fresh notice event (replacing any prior
    /// integrity notices so the badge reflects only the latest scan). Returns the report that was
    /// recorded. Idempotent-ish: repeated calls collapse to a single trailing notice.
    @discardableResult
    public static func record(into thread: inout ChatThread) -> RunIntegrityReport {
        let report = RunIntegrityScanner.scan(thread)
        thread.events.removeAll(where: isRecord)
        if let event = event(for: report) {
            thread.events.append(event)
            thread.updatedAt = Date()
        }
        return report
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        event.kind == .notice && event.summary == eventSummary
    }
}

/// The data-driven lexicon of what a "test / verify" command looks like. Kept separate so the rule is
/// inspectable and easy to extend without touching the scanner's control flow. A token matches only on a
/// word boundary so `pytest` matches but `mypytesting` does not, and `test` alone is intentionally NOT a
/// token (too many false hits like `test -f`), only test *runners* and `<tool> test` sub-commands.
public enum TestCommandLexicon {
    /// Standalone test-runner invocations (word-boundary matched, case-insensitive).
    public static let runnerTokens: [String] = [
        "swift test",
        "xcodebuild test",
        "xctest",
        "pytest",
        "py.test",
        "unittest",
        "jest",
        "vitest",
        "mocha",
        "rspec",
        "phpunit",
        "gotestsum",
        "ctest",
        "tox",
        "nosetests",
    ]

    /// `<tool> test` sub-command shapes (e.g. `cargo test`, `npm test`, `go test`, `make test`).
    public static let subcommandTokens: [String] = [
        "cargo test",
        "go test",
        "npm test",
        "npm run test",
        "yarn test",
        "pnpm test",
        "bun test",
        "make test",
        "make check",
        "gradle test",
        "./gradlew test",
        "mvn test",
        "dotnet test",
        "rake test",
        "bazel test",
        "ninja test",
    ]

    public static func looksLikeTestCommand(_ command: String) -> Bool {
        let lowered = command.lowercased()
        guard !lowered.isEmpty else { return false }
        for token in runnerTokens + subcommandTokens where containsToken(token, in: lowered) {
            return true
        }
        return false
    }

    /// Substring match with cheap word-ish boundaries so `pytest` inside `pytest tests/` matches but a
    /// token embedded in a longer identifier does not. Bounded, allocation-light.
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

/// The data-driven lexicon of assistant success claims. Anchored so an incidental "passes" in prose does
/// not trip UNVERIFIED — every phrase reads as a claim ABOUT tests/checks passing. Kept public and
/// inspectable so the precision stance is auditable and tunable.
public enum SuccessClaimLexicon {
    /// Phrases that, appearing verbatim (case-insensitive) in assistant text, assert a checked green.
    /// Each is deliberately multi-word / anchored to a test/check/build noun to avoid catching the
    /// English verb "pass" used incidentally (e.g. "the function passes the argument along").
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

    public static func matchedClaim(in loweredText: String) -> String? {
        guard !loweredText.isEmpty else { return nil }
        for phrase in claimPhrases where loweredText.contains(phrase) {
            return phrase
        }
        return nil
    }
}
