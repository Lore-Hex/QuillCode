import XCTest
import Foundation
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

/// Emits fingerprint-equal but byte-DIFFERENT tool calls (whitespace varies inside the JSON), so the
/// run bypasses the exact-repeat short-circuit and exercises the flail detector instead.
private final class NearRepeatToolLLMClient: LLMClient, @unchecked Sendable {
    private var counter = 0
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        counter += 1
        // Alternate spacing → argumentsJSON differs byte-wise every call, normalizes identically.
        let json = counter % 2 == 0 ? #"{"path":"same.txt"}"# : #"{"path": "same.txt"}"#
        return .tool(ToolCall(name: "host.file.read", argumentsJSON: json))
    }
}

/// A different call every time (never repeats), used for the healthy-run control.
private final class AlwaysFreshToolLLMClient: LLMClient, @unchecked Sendable {
    private var counter = 0
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        counter += 1
        return .tool(ToolCall(name: "host.file.read", argumentsJSON: #"{"path":"file-\#(counter).txt"}"#))
    }
}

/// Alternates two structurally different calls whose RESULTS carry the identical failure — the
/// repeated-failure rule, not the repeated-action rule.
private final class AlternatingCallsLLMClient: LLMClient, @unchecked Sendable {
    private var counter = 0
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        counter += 1
        let path = counter % 2 == 0 ? "a.txt" : "b.txt"
        return .tool(ToolCall(name: "host.file.read", argumentsJSON: #"{"path":"\#(path)"}"#))
    }
}

final class AgentFlailWiringTests: XCTestCase {
    private var root: URL { FileManager.default.temporaryDirectory }
    private let thread = ChatThread(title: "T", messages: [], events: [])

    /// The canonical spin: near-identical calls, zero workspace change → one self-assessment nudge,
    /// then an honest flail stop with a distinct stopReason.
    func testFlailingRunIsNudgedOnceThenStopped() async throws {
        let runner = AgentRunner(
            llm: NearRepeatToolLLMClient(),
            toolExecutionOverride: { _, _ in ToolResult(ok: true, stdout: "same output") },
            maxToolSteps: 10,
            workspaceStateSignature: { _ in "constant-state" }
        )
        let result = try await runner.send("go", in: thread, workspaceRoot: root)

        guard case .flailDetected(let reason) = result.stopReason else {
            return XCTFail("expected flailDetected, got \(result.stopReason)")
        }
        XCTAssertTrue(reason.contains("no workspace change"), reason)

        let selfChecks = result.thread.messages.filter { $0.role == .user && $0.content.contains("[QuillCode self-check]") }
        XCTAssertEqual(selfChecks.count, 1, "exactly one self-assessment nudge per run")

        let notices = result.thread.events.filter { $0.kind == .notice && $0.summary.hasPrefix("Self-healing:") }
        XCTAssertEqual(notices.count, 2, "one nudge notice + one stop notice; got \(notices.map(\.summary))")
        XCTAssertTrue(notices.last!.summary.contains("stopped the run"), notices.last!.summary)

        // The nudge lands at suspected (turn 3), the stop at confirmed (turn 4) — well under the budget.
        XCTAssertLessThan(result.toolResults.count, 6)
    }

    /// Same failure through DIFFERENT calls — the repeated-failure rule catches zero learning even
    /// when the actions vary.
    func testRepeatedIdenticalFailureAcrossDifferentCallsIsCaught() async throws {
        let runner = AgentRunner(
            llm: AlternatingCallsLLMClient(),
            toolExecutionOverride: { _, _ in
                ToolResult(ok: false, stdout: "", stderr: "error: fatal: identical failure in Foo.swift", error: "failed")
            },
            maxToolSteps: 10,
            workspaceStateSignature: { _ in "constant-state" }
        )
        let result = try await runner.send("go", in: thread, workspaceRoot: root)

        guard case .flailDetected(let reason) = result.stopReason else {
            return XCTFail("expected flailDetected, got \(result.stopReason)")
        }
        XCTAssertTrue(reason.contains("identical failure"), reason)
    }

    /// Control: a healthy run making fresh progress every step must never see the flail machinery —
    /// it exhausts the ceiling exactly as before this feature.
    func testHealthyProgressingRunNeverTripsTheDetector() async throws {
        let stateCounter = Counter()
        let runner = AgentRunner(
            llm: AlwaysFreshToolLLMClient(),
            toolExecutionOverride: { _, _ in ToolResult(ok: true, stdout: "did work") },
            maxToolSteps: 4,
            workspaceStateSignature: { _ in "state-\(stateCounter.next())" }
        )
        let result = try await runner.send("go", in: thread, workspaceRoot: root)

        XCTAssertEqual(result.stopReason, .toolStepCeilingExhausted(limit: 4))
        XCTAssertFalse(
            result.thread.events.contains { $0.summary.hasPrefix("Self-healing:") },
            "no flail notices on a progressing run"
        )
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("[QuillCode self-check]") })
    }

    /// A genuine finish stays untouched.
    func testSayRunNeverComputesOrTripsFlail() async throws {
        let runner = AgentRunner(
            llm: FixedSayLLMClient(message: "Done."),
            workspaceStateSignature: { _ in
                XCTFail("a .say-only run must not sample the workspace state")
                return "never"
            }
        )
        let result = try await runner.send("go", in: thread, workspaceRoot: root)
        XCTAssertEqual(result.stopReason, .finished)
    }
}

/// Thread-compatible counter for @Sendable closures in tests (calls are sequential in the run loop).
private final class Counter: @unchecked Sendable {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}
