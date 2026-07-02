import XCTest
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeAgent

/// Functional tests at the agent gate: persisted permission rules must change what the run loop
/// actually executes, composed with (not instead of) the static mode/intent review.
final class AgentPermissionRuleGateTests: XCTestCase {
    private func makeRunner(rules: [PermissionRule], llmCommand: String) -> AgentRunner {
        AgentRunner(
            llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": llmCommand])
            )),
            safety: PermissionRuleGatedSafetyReviewer(
                base: StaticSafetyReviewer(),
                rules: StaticPermissionRulesProvider(table: PermissionRuleTable(rules: rules))
            )
        )
    }

    func testDenyRuleBlocksAnAutoModeRunTheIntentGateWouldApprove() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = makeRunner(
            rules: [PermissionRule(action: "host.shell.run", resource: "echo hi", match: .exact, decision: .deny)],
            llmCommand: "echo hi"
        )
        // "run echo hi" intent-matches shell.run, so WITHOUT the rule Auto mode would execute it.
        let result = try await runner.send(
            "run echo hi",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertTrue(
            result.thread.events.contains { $0.kind == .approvalRequested },
            "the deny rule must block the call"
        )
        XCTAssertFalse(
            result.thread.events.contains { $0.kind == .toolCompleted },
            "a denied tool call must never execute"
        )
        XCTAssertTrue(result.toolResults.isEmpty)
    }

    func testWithoutTheDenyRuleTheSameAutoRunExecutes() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = makeRunner(rules: [], llmCommand: "echo hi")
        let result = try await runner.send(
            "run echo hi",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertTrue(result.thread.events.contains { $0.kind == .toolCompleted })
    }

    func testAllowRuleSkipsTheReviewModeApprovalGate() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = makeRunner(
            rules: [PermissionRule(action: "host.shell.run", resource: "echo trusted", match: .exact, decision: .allow)],
            llmCommand: "echo trusted"
        )
        // Review mode gates every non-read tool; the saved allow rule is the standing approval.
        let result = try await runner.send(
            "run echo trusted",
            in: ChatThread(mode: .review),
            workspaceRoot: root
        )

        XCTAssertFalse(
            result.thread.events.contains { $0.kind == .approvalRequested },
            "the allow rule should have skipped the ask"
        )
        XCTAssertTrue(result.thread.events.contains { $0.kind == .toolCompleted })
    }

    func testAllowRuleStillBlocksHardDeniedCommands() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = makeRunner(
            rules: [PermissionRule(action: "host.shell.run", resource: "**", decision: .allow)],
            llmCommand: "rm -rf / --please"
        )
        let result = try await runner.send(
            "run rm -rf / --please",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertFalse(
            result.thread.events.contains { $0.kind == .toolCompleted },
            "a blanket allow rule must not bypass the hard-deny safety floor"
        )
    }

    func testReadOnlyModeIgnoresAllowRules() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = makeRunner(
            rules: [PermissionRule(action: "host.shell.run", resource: "**", decision: .allow)],
            llmCommand: "echo mutate"
        )
        let result = try await runner.send(
            "run echo mutate",
            in: ChatThread(mode: .readOnly),
            workspaceRoot: root
        )

        XCTAssertFalse(
            result.thread.events.contains { $0.kind == .toolCompleted },
            "read-only mode must stay read-only regardless of allow rules"
        )
    }
}
