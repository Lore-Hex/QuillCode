import Foundation

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

        // Rule 2b (UNVERIFIED): a fabricated quantitative result — the model reports a benchmark pass
        // rate / "N/M passed" / score whose figures appear in NO tool output of the run. This catches
        // the worst unattended failure mode (a confident, specific, FALSE result that a generic
        // success-claim check misses) — observed live when a τ-bench run that never executed reported
        // "100% (5/5), reward 1.0".
        if let fabricated = unbackedResultFigure(in: thread) {
            reasons.append(fabricated)
            return RunIntegrityReport(verdict: .unverified, reasons: reasons)
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
        /// The parsed test-command identity, or nil when this is not a test/verify command. Its `scope`
        /// key is what "re-run the SAME test" matches on, so an unrelated suite passing cannot clear an
        /// unrelated suite's failure.
        var test: TestCommandLexicon.Match?
        var succeeded: Bool

        var isTestCommand: Bool { test != nil }
    }

    static func commandSteps(in thread: ChatThread) -> [CommandStep] {
        var steps: [CommandStep] = []
        var pendingCall: ToolCall?

        for event in thread.events {
            if steps.count >= maxToolStepsScanned { break }
            switch event.kind {
            case .toolQueued:
                pendingCall = decodeCall(event.payloadJSON)
            case .toolRunning, .toolProgress:
                // No payload of interest; keep the pending call as-is.
                continue
            case .toolCompleted, .toolFailed:
                defer { pendingCall = nil }
                guard let call = pendingCall, isCommandTool(call.name) else { continue }
                let result = decodeResult(event.payloadJSON)
                let command = shellCommand(from: call)
                steps.append(CommandStep(
                    command: command,
                    test: TestCommandLexicon.classify(command),
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
        // Find the LAST failing test command; if that SAME test (same scope) was re-run green afterward
        // the failure was addressed and does not redden the run. An UNRELATED suite passing does NOT
        // clear it — that would hide a real standing failure (the trust hole).
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

    /// Whether a later step re-runs the failed test green: a later SUCCESS of the SAME test scope (or a
    /// passing run of the exact same command string). The single source of truth for "the failure was
    /// addressed", shared by the RED rule and the informational re-run-green reason so they never drift.
    /// Deliberately scope-matched — a green run of a DIFFERENT suite must not vouch for the failed one.
    static func hasLaterGreenRerun(ofFailureAt failIndex: Int, in steps: [CommandStep]) -> Bool {
        let failed = steps[failIndex]
        return steps[(failIndex + 1)...].contains { later in
            guard later.succeeded else { return false }
            if sameCommand(later.command, failed.command) { return true }
            guard let laterScope = later.test?.scope, let failedScope = failed.test?.scope else {
                return false
            }
            return laterScope == failedScope
        }
    }

    // MARK: - Rule 3: silently skipped test (UNVERIFIED)

    /// A test command that was queued but for which no matching result event was ever recorded — the
    /// test the run set out to run never actually reported back.
    ///
    /// The result event carries only the `ToolResult`, not its command, so a skip cannot be cleared by
    /// command-name match. Instead we model the whole queue↔result pairing as a STACK: every queued tool
    /// is pushed; each result pops the MOST-RECENTLY queued unresolved tool. This is exactly right for
    /// the agent's strictly sequential tool loop (queue → running → result before the next queue): if a
    /// test was queued but its result never appeared before the NEXT command was queued, that test was
    /// abandoned — it sits at the bottom of the stack while later commands push/pop above it, so an
    /// unrelated later command can never resolve it. Any still-pending test at the end is a genuine skip.
    static func skippedTest(in thread: ChatThread) -> RunIntegrityReason? {
        // Stack of EVERY queued tool call not yet resolved. We must track all tools (not just shell
        // ones), because a result event is anonymous — pairing it only against shell commands would let
        // an unrelated tool's result resolve a dangling shell test. `isTest` marks the ones that matter.
        var pending: [(command: String, isTest: Bool)] = []
        var scanned = 0
        for event in thread.events {
            if scanned >= maxToolStepsScanned { break }
            switch event.kind {
            case .toolQueued:
                guard let call = decodeCall(event.payloadJSON) else { continue }
                let command = isCommandTool(call.name) ? shellCommand(from: call) : ""
                let isTest = isCommandTool(call.name) && TestCommandLexicon.classify(command) != nil
                pending.append((command, isTest))
            case .toolRunning, .toolProgress:
                continue
            case .toolCompleted, .toolFailed:
                scanned += 1
                // Resolve the most-recently queued unresolved tool (its own result, by sequential order).
                if !pending.isEmpty { pending.removeLast() }
            default:
                continue
            }
        }
        guard let dangling = pending.first(where: { $0.isTest }) else { return nil }
        return RunIntegrityReason(
            rule: .skippedTest,
            detail: "A test command was started but never completed: \(shortCommand(dangling.command))."
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

    // MARK: - Rule 2b: fabricated quantitative result (UNVERIFIED)

    /// Hard cap on the tool-output text scanned for figure provenance, so a run that dumped megabytes
    /// (a base64 screenshot, a huge file read) stays bounded.
    static let maxToolOutputScanCharacters = 200_000

    /// A reason when the assistant reports an explicit EVALUATION result (a benchmark pass rate,
    /// "N/M passed", a score/reward) but NONE of the specific figures it cites appears anywhere in the
    /// run's tool output. High-precision by construction: a genuine result's numbers are printed by the
    /// eval (or read from its file) and therefore live in some tool output, so only figures the model
    /// invented go unbacked. Requires eval-result LANGUAGE too, so an incidental derived percentage in
    /// ordinary coding prose can't trip it.
    static func unbackedResultFigure(in thread: ChatThread) -> RunIntegrityReason? {
        guard let claim = ResultFigureLexicon.firstResultClaim(inAssistantMessagesOf: thread) else {
            return nil
        }
        let corpus = normalizedForFigureMatch(toolOutputCorpus(in: thread))
        // Backed if ANY cited figure appears in tool output (format-tolerantly) — then we assume the
        // result is data-backed (the model may have derived one figure the eval didn't print).
        let anyBacked = claim.figures.contains { figureAppears($0, in: corpus) }
        guard !anyBacked else { return nil }
        let cited = claim.figures.prefix(3).joined(separator: ", ")
        return RunIntegrityReason(
            rule: .unbackedResultFigure,
            detail: "Reported result figures (\(cited)) appear in no tool output — the run may not have "
                + "actually produced them."
        )
    }

    /// Concatenated stdout+stderr+error of every tool result in the run, capped to the TAIL. A reported
    /// figure must trace back to this ground truth. The tail (not the head) is kept because in a long
    /// unattended run the eval runs LAST — its output, where the real figures live, is at the end
    /// (mirrors ShellOutputCapper's tail-keep rationale).
    static func toolOutputCorpus(in thread: ChatThread) -> String {
        var pieces: [String] = []
        for event in thread.events {
            guard event.kind == .toolCompleted || event.kind == .toolFailed else { continue }
            guard let result = decodeResult(event.payloadJSON) else { continue }
            pieces.append(result.stdout)
            pieces.append(result.stderr)
            if let error = result.error { pieces.append(error) }
        }
        let corpus = pieces.joined(separator: "\n")
        guard corpus.count > maxToolOutputScanCharacters else { return corpus }
        return String(corpus.suffix(maxToolOutputScanCharacters))
    }

    /// Collapses whitespace around `/` so a ratio the eval printed as "3 / 5" still backs the model's
    /// "3/5" (figures are already space-stripped on extraction — normalize the corpus symmetrically).
    static func normalizedForFigureMatch(_ corpus: String) -> String {
        var result = ""
        result.reserveCapacity(corpus.count)
        let chars = Array(corpus)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "/" {
                // Drop whitespace already emitted before the slash…
                while let last = result.last, last == " " || last == "\t" { result.removeLast() }
                result.append("/")
                // …and skip whitespace after it.
                i += 1
                while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
                continue
            }
            result.append(c)
            i += 1
        }
        return result
    }

    /// Whether a result figure appears in the (normalized) corpus, tolerating the `100%`↔`100.0%`
    /// formatting the eval and the model may disagree on.
    static func figureAppears(_ figure: String, in corpus: String) -> Bool {
        if corpus.contains(figure) { return true }
        guard figure.hasSuffix("%") else { return false }
        let number = String(figure.dropLast())
        if number.contains(".") {
            // "80.0%" also backs a printed "80%": strip trailing zeros (and a bare trailing dot).
            var trimmed = number
            while trimmed.hasSuffix("0") { trimmed.removeLast() }
            if trimmed.hasSuffix(".") { trimmed.removeLast() }
            return corpus.contains(trimmed + "%")
        }
        // "100%" also backs a printed "100.0%".
        return corpus.contains(number + ".0%")
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
