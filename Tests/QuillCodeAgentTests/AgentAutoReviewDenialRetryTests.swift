import XCTest
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentAutoReviewDenialRetryTests: XCTestCase {
    func testDeniedActionFeedsModelThenExactRetryReviewsExecutesAndConsumesOnce() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "approved.txt", "content": "done"])
        )
        let safety = SequenceSafetyReviewer([
            .init(verdict: .deny, rationale: "Needs explicit retry."),
            .init(verdict: .approve, rationale: "Exact retry approved.")
        ])
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("I can use a safer alternative.")]),
            safety: safety
        )

        let first = try await runner.send(
            "Create approved.txt",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )
        XCTAssertNil(first.pendingApproval)
        XCTAssertEqual(first.thread.messages.last?.content, "I can use a safer alternative.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("approved.txt").path))

        let denial = try XCTUnwrap(AutoReviewDenialHistory.records(
            in: first.thread,
            workspaceRoot: root
        ).first)
        let retry = try await runner.retryAutoReviewDenial(
            requestID: denial.id,
            in: first.thread,
            workspaceRoot: root,
            userMessage: "Create approved.txt"
        )

        XCTAssertTrue(retry.didExecute)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("approved.txt").path))
        XCTAssertEqual(
            AutoReviewDenialHistory.records(in: retry.thread, workspaceRoot: root).first?.retryState,
            .consumed
        )
        let attempts = await safety.attempts()
        XCTAssertEqual(attempts, [.initial, .denialOverride(requestID: denial.id)])

        do {
            _ = try await runner.retryAutoReviewDenial(
                requestID: denial.id,
                in: retry.thread,
                workspaceRoot: root,
                userMessage: "Create approved.txt"
            )
            XCTFail("A consumed denial must never execute twice")
        } catch let error as AgentAutoReviewRetryError {
            XCTAssertEqual(error, .retryConsumed)
        }
    }

    func testRetryCanBeDeniedAgainWithoutExecuting() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "blocked.txt", "content": "no"])
        )
        let safety = SequenceSafetyReviewer([
            .init(verdict: .deny, rationale: "Denied first."),
            .init(verdict: .deny, rationale: "Denied again.")
        ])
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("Blocked.")]),
            safety: safety
        )
        let first = try await runner.send("Write blocked.txt", in: ChatThread(mode: .auto), workspaceRoot: root)
        let denial = try XCTUnwrap(AutoReviewDenialHistory.records(in: first.thread, workspaceRoot: root).first)

        let retry = try await runner.retryAutoReviewDenial(
            requestID: denial.id,
            in: first.thread,
            workspaceRoot: root,
            userMessage: "Write blocked.txt"
        )

        XCTAssertFalse(retry.didExecute)
        XCTAssertTrue(retry.toolResults.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("blocked.txt").path))
        XCTAssertEqual(AutoReviewDenialHistory.records(
            in: retry.thread,
            workspaceRoot: root
        ).first?.retryState, .consumed)
    }

    func testRetryRejectsChangedTurnAndRedactedArguments() async throws {
        let root = try makeTempDirectory()
        let call = ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: ToolArguments.json([
            "cmd": "env",
            "env": ["TOKEN": "secret"]
        ]))
        let safety = SequenceSafetyReviewer([.init(verdict: .deny, rationale: "Private arguments.")])
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(call), .say("Blocked.")]),
            safety: safety
        )
        let first = try await runner.send("Run it", in: ChatThread(mode: .auto), workspaceRoot: root)
        let denial = try XCTUnwrap(AutoReviewDenialHistory.records(in: first.thread).first)

        do {
            _ = try await runner.retryAutoReviewDenial(
                requestID: denial.id,
                in: first.thread,
                workspaceRoot: root,
                userMessage: "Run it"
            )
            XCTFail("Redacted arguments must not be replayed")
        } catch let error as AgentAutoReviewRetryError {
            XCTAssertEqual(error, .replayUnavailable)
        }

        var changed = first.thread
        changed.messages.append(.init(role: .user, content: "A new turn"))
        let safeCall = ToolCall(name: ToolDefinition.shellRun.name, argumentsJSON: ToolArguments.json(["cmd": "whoami"]))
        let safeSafety = SequenceSafetyReviewer([.init(verdict: .deny, rationale: "Denied.")])
        let safeRunner = AgentRunner(
            llm: SequenceLLMClient(actions: [.tool(safeCall), .say("Blocked.")]),
            safety: safeSafety
        )
        let safeFirst = try await safeRunner.send("Run whoami", in: ChatThread(mode: .auto), workspaceRoot: root)
        let safeDenial = try XCTUnwrap(AutoReviewDenialHistory.records(in: safeFirst.thread).first)
        var nextTurn = safeFirst.thread
        nextTurn.messages.append(.init(role: .user, content: "Different task"))
        do {
            _ = try await safeRunner.retryAutoReviewDenial(
                requestID: safeDenial.id,
                in: nextTurn,
                workspaceRoot: root,
                userMessage: "Different task"
            )
            XCTFail("A changed turn must invalidate the retry")
        } catch let error as AgentAutoReviewRetryError {
            XCTAssertEqual(error, .contextChanged)
        }
    }
}

private actor SequenceSafetyReviewer: SafetyReviewer {
    private var reviews: [SafetyReview]
    private var recordedAttempts: [ApprovalReviewAttempt] = []

    init(_ reviews: [SafetyReview]) {
        self.reviews = reviews
    }

    func review(_ context: SafetyContext) async -> SafetyReview {
        recordedAttempts.append(context.reviewAttempt)
        guard !reviews.isEmpty else {
            return SafetyReview(verdict: .deny, rationale: "No review fixture remained.")
        }
        return reviews.removeFirst()
    }

    func attempts() -> [ApprovalReviewAttempt] {
        recordedAttempts
    }
}
