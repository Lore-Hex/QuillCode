import XCTest
@testable import QuillCodeCore

/// The heart of issue #875: a FIXTURE CORPUS of sneaky transcripts. Each fixture is a run whose
/// transcript could fool a human skimming it, and each asserts the exact badge the scanner must produce.
/// The bias is HIGH PRECISION — the "incidental pass" and "no tests, no claim" fixtures guard against
/// false yellows/reds, which are the failure mode the issue explicitly calls out.
final class RunIntegrityScannerTests: XCTestCase {

    // MARK: - Transcript builders (mirror the real event shapes from AgentToolStepRunner)

    /// Appends the queued -> running -> completed/failed event triple for a shell command, exactly as
    /// the agent records it (`toolQueued` carries the ToolCall, the result event carries the ToolResult).
    private func shell(
        _ cmd: String,
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        error: String? = nil
    ) -> [ThreadEvent] {
        let ok = exitCode == 0
        let call = ToolCall(name: RunIntegrityScanner.shellRunToolName, argumentsJSON: encodedArgs(cmd: cmd))
        let result = ToolResult(ok: ok, stdout: stdout, stderr: stderr, exitCode: exitCode, error: error)
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? "{}"
        let resultJSON = (try? JSONHelpers.encodePretty(result)) ?? "{}"
        return [
            ThreadEvent(kind: .toolQueued, summary: "\(call.name) queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "\(call.name) running"),
            ThreadEvent(
                kind: ok ? .toolCompleted : .toolFailed,
                summary: "\(call.name) \(ok ? "completed" : "failed")",
                payloadJSON: resultJSON
            )
        ]
    }

    /// A test command that was queued and started but NEVER produced a result event (silently skipped /
    /// abandoned mid-flight).
    private func danglingShell(_ cmd: String) -> [ThreadEvent] {
        let call = ToolCall(name: RunIntegrityScanner.shellRunToolName, argumentsJSON: encodedArgs(cmd: cmd))
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? "{}"
        return [
            ThreadEvent(kind: .toolQueued, summary: "\(call.name) queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "\(call.name) running")
        ]
    }

    private func encodedArgs(cmd: String) -> String {
        let object = ["cmd": cmd]
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func thread(
        assistantText: [String] = [],
        events: [ThreadEvent] = []
    ) -> ChatThread {
        let messages = assistantText.map { ChatMessage(role: .assistant, content: $0) }
        return ChatThread(messages: messages, events: events)
    }

    // MARK: - Fixture corpus

    /// 1. Clean verified run: tests ran and passed, and the model said so. -> VERIFIED
    func testCleanVerifiedRun() {
        let run = thread(
            assistantText: ["I ran the suite and all tests pass."],
            events: shell("swift test", exitCode: 0, stdout: "Executed 42 tests, with 0 failures")
        )
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .verified)
        XCTAssertTrue(report.reasons.contains { $0.rule == .backedSuccessClaim })
    }

    /// 2. Claimed "tests pass" but NO test command ever ran. -> UNVERIFIED (unbacked claim)
    func testClaimedPassWithNoTestToolCall() {
        let run = thread(
            assistantText: ["I made the change. All tests pass now."],
            events: [] // never actually ran a test
        )
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .unverified)
        XCTAssertEqual(report.reasons.first?.rule, .unbackedSuccessClaim)
    }

    /// 2b. Claim backed only by a NON-test command (e.g. `ls`) that happened to exit 0 is still
    /// unbacked — a green `ls` does not vouch for the tests. -> UNVERIFIED
    func testClaimBackedOnlyByNonTestCommandIsUnverified() {
        let run = thread(
            assistantText: ["Done — all tests pass."],
            events: shell("ls -la", exitCode: 0, stdout: "file.txt")
        )
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .unverified)
    }

    /// 3. A failing test that was never re-run. -> RED (standing failure)
    func testFailingTestNeverRerun() {
        let run = thread(
            assistantText: ["Pushed the fix."],
            events: shell("swift test", exitCode: 1, stdout: "Executed 42 tests, with 3 failures")
        )
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .red)
        XCTAssertEqual(report.reasons.first?.rule, .standingTestFailure)
    }

    /// 4. Failing then fixed and re-run green. -> VERIFIED (failureThenRerunGreen)
    func testFailingThenFixedAndRerunGreen() {
        var events = shell("swift test", exitCode: 1, stdout: "1 failed")
        events += shell("swift test", exitCode: 0, stdout: "Executed 42 tests, with 0 failures")
        let run = thread(assistantText: ["Fixed it; tests pass now."], events: events)
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .verified)
        XCTAssertTrue(report.reasons.contains { $0.rule == .backedSuccessClaim })
    }

    /// 5. A test that was started but silently skipped (no result event). -> UNVERIFIED (skippedTest)
    func testSilentlySkippedTest() {
        let run = thread(
            assistantText: ["Wrapping up."],
            events: danglingShell("pytest")
        )
        let report = RunIntegrityScanner.scan(run)
        XCTAssertEqual(report.verdict, .unverified)
        XCTAssertEqual(report.reasons.first?.rule, .skippedTest)
    }

    /// 6. A nonzero exit that WAS re-run green (same command string). -> VERIFIED
    func testNonzeroExitThatWasRerunGreen() {
        var events = shell("make check", exitCode: 2, stderr: "boom")
        events += shell("make check", exitCode: 0, stdout: "OK")
        let run = thread(events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 7. PRECISION GUARD: text mentioning "pass" incidentally must NOT trip UNVERIFIED.
    func testIncidentalPassMentionDoesNotTripUnverified() {
        let run = thread(
            assistantText: [
                "I updated the function so it passes the auth token to the downstream service.",
                "The user can now pass a custom limit. This should pass review easily.",
            ],
            events: []
        )
        // No claim phrase, no failing test -> a benign VERIFIED, never a false yellow.
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 7b. PRECISION GUARD: a bare non-test shell failure (e.g. `grep` finding nothing) is normal
    /// control flow and must NOT redden the run.
    func testNonTestShellFailureIsNotRed() {
        let run = thread(
            assistantText: ["No matches found, moving on."],
            events: shell("grep -q MARKER src/", exitCode: 1)
        )
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 8. No tests, no claims — a pure read/refactor run. -> VERIFIED (nothing dishonest happened).
    func testBenignRunWithNoTestsAndNoClaims() {
        let run = thread(
            assistantText: ["Here's a summary of how the module is structured."],
            events: shell("cat README.md", exitCode: 0, stdout: "# Project")
        )
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 9. RED dominates a co-occurring success claim: a claim plus a standing test failure is still RED
    /// (the failure is the more serious, higher-precision signal).
    func testStandingFailureDominatesClaim() {
        // The model also claims success in the same run — but the failure stands, so it is RED.
        let run = thread(
            assistantText: ["All tests pass!"],
            events: shell("swift test", exitCode: 1, stdout: "2 failed")
        )
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .red)
    }

    /// 10. Cancellation payload ("Stopped by user") on a non-test command must not redden the run.
    func testUserStoppedNonTestCommandIsNotRed() {
        let call = ToolCall(name: RunIntegrityScanner.shellRunToolName, argumentsJSON: encodedArgs(cmd: "sleep 100"))
        let callJSON = (try? JSONHelpers.encodePretty(call)) ?? "{}"
        let run = thread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: callJSON),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(kind: .toolFailed, summary: "failed", payloadJSON: #"{"ok":false,"error":"Stopped by user"}"#)
        ])
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 11. A test failure followed by a DIFFERENT test command passing counts as re-run green (any test
    /// passing after the failure clears the standing-failure flag).
    func testDifferentTestCommandPassingClearsFailure() {
        var events = shell("pytest tests/unit", exitCode: 1, stdout: "1 failed")
        events += shell("pytest tests/integration", exitCode: 0, stdout: "5 passed")
        let run = thread(events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    /// 12. Only the LAST failing test that stands matters: a green run followed by a later red is RED.
    func testGreenThenLaterRedIsRed() {
        var events = shell("swift test", exitCode: 0, stdout: "0 failures")
        events += shell("swift test", exitCode: 1, stdout: "1 failed")
        let run = thread(events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .red)
    }

    // MARK: - Robustness (must never crash, always deterministic)

    func testEmptyThreadIsVerified() {
        XCTAssertEqual(RunIntegrityScanner.scan(thread()).verdict, .verified)
    }

    func testMalformedPayloadsDoNotCrash() {
        let run = thread(events: [
            ThreadEvent(kind: .toolQueued, summary: "queued", payloadJSON: "not json {"),
            ThreadEvent(kind: .toolCompleted, summary: "completed", payloadJSON: nil),
            ThreadEvent(kind: .toolFailed, summary: "failed", payloadJSON: "]["),
            ThreadEvent(kind: .toolRunning, summary: "orphan running"),
            ThreadEvent(kind: .toolCompleted, summary: "orphan completed", payloadJSON: "{}")
        ])
        // Must not crash and must reach a decision.
        _ = RunIntegrityScanner.scan(run)
    }

    func testResultEventWithoutQueuedIsIgnored() {
        // A completed event with no preceding queued call (interleaved / truncated transcript) is simply
        // not treated as a command step.
        let run = thread(events: [
            ThreadEvent(kind: .toolCompleted, summary: "completed", payloadJSON: #"{"ok":true}"#)
        ])
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    func testHugeTranscriptStaysBounded() {
        // A pathological transcript of many steps + a giant message must still terminate quickly.
        var events: [ThreadEvent] = []
        for _ in 0..<200 { events += shell("echo hi", exitCode: 0) }
        let giant = String(repeating: "the code passes data around. ", count: 5_000)
        let run = thread(assistantText: [giant], events: events)
        XCTAssertEqual(RunIntegrityScanner.scan(run).verdict, .verified)
    }

    func testDeterministic() {
        let run = thread(
            assistantText: ["all tests pass"],
            events: shell("swift test", exitCode: 0, stdout: "0 failures")
        )
        let a = RunIntegrityScanner.scan(run)
        let b = RunIntegrityScanner.scan(run)
        XCTAssertEqual(a.verdict, b.verdict)
        XCTAssertEqual(a.reasons, b.reasons)
    }

    // MARK: - Persistence round-trip (verdict stable across a JSON reload)

    func testRecordAndReadBackVerdict() throws {
        var run = thread(
            assistantText: ["tests pass"],
            events: shell("swift test", exitCode: 0, stdout: "0 failures")
        )
        let recorded = RunIntegrityRecord.record(into: &run)
        XCTAssertEqual(recorded.verdict, .verified)

        // The verdict is now readable back off the thread's events...
        XCTAssertEqual(RunIntegrityRecord.latest(in: run)?.verdict, .verified)

        // ...and survives a full Codable round-trip of the thread (what JSONThreadStore does).
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(run)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(ChatThread.self, from: data)
        XCTAssertEqual(RunIntegrityRecord.latest(in: reloaded)?.verdict, .verified)
    }

    func testRecordCollapsesToASingleTrailingNotice() {
        var run = thread(events: shell("swift test", exitCode: 1, stdout: "1 failed"))
        RunIntegrityRecord.record(into: &run)
        RunIntegrityRecord.record(into: &run)
        let notices = run.events.filter { RunIntegrityRecord.isRecord($0) }
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(RunIntegrityRecord.latest(in: run)?.verdict, .red)
    }

    // MARK: - Lexicon precision

    func testTestCommandLexicon() {
        XCTAssertTrue(TestCommandLexicon.looksLikeTestCommand("swift test"))
        XCTAssertTrue(TestCommandLexicon.looksLikeTestCommand("cd foo && pytest -q tests/"))
        XCTAssertTrue(TestCommandLexicon.looksLikeTestCommand("npm test"))
        XCTAssertTrue(TestCommandLexicon.looksLikeTestCommand("cargo test --all"))
        XCTAssertFalse(TestCommandLexicon.looksLikeTestCommand("ls -la"))
        XCTAssertFalse(TestCommandLexicon.looksLikeTestCommand("test -f foo"))
        // Word-boundary: an embedded token in a longer identifier must not match.
        XCTAssertFalse(TestCommandLexicon.looksLikeTestCommand("run mypytesting_helper"))
        XCTAssertFalse(TestCommandLexicon.looksLikeTestCommand(""))
    }

    func testSuccessClaimLexiconAnchoring() {
        XCTAssertNotNil(SuccessClaimLexicon.matchedClaim(in: "all tests pass"))
        XCTAssertNotNil(SuccessClaimLexicon.matchedClaim(in: "the suite is green — everything passes"))
        // Incidental verb "pass" must not match.
        XCTAssertNil(SuccessClaimLexicon.matchedClaim(in: "please pass the config to the builder"))
        XCTAssertNil(SuccessClaimLexicon.matchedClaim(in: ""))
    }

    /// Guard: the Core-local shell tool name must match the real ToolDefinition (they live in different
    /// modules and are duplicated on purpose to keep Core dependency-free).
    func testShellToolNameParity() {
        XCTAssertEqual(RunIntegrityScanner.shellRunToolName, "host.shell.run")
    }
}
