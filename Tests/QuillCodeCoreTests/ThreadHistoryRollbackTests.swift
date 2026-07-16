import Foundation
import XCTest

@testable import QuillCodeCore

final class ThreadHistoryRollbackTests: XCTestCase {
    func testRemovesCompleteTurnsAndPreservesDurableSideStateAndUsageReceipts() {
        let base = Date(timeIntervalSince1970: 1_000)
        let projectID = UUID()
        let goal = ThreadGoal(objective: "Ship rollback parity")!
        let earlierRun = SubagentRunRecord(objective: "Earlier", createdAt: base, updatedAt: base)
        let laterRun = SubagentRunRecord(
            objective: "Later",
            createdAt: base.addingTimeInterval(8),
            updatedAt: base.addingTimeInterval(8)
        )
        var usage = ModelTokenUsageEvent.event(
            usage: ModelTokenUsage(promptTokens: 10, completionTokens: 2),
            modelID: "trustedrouter/fast"
        )
        usage.createdAt = base.addingTimeInterval(9)
        var thread = ChatThread(
            title: "Generated title",
            projectID: projectID,
            messages: [
                message(.system, "system", at: base),
                message(.assistant, "summary", at: base.addingTimeInterval(1)),
                message(.user, "first", turnID: "turn-a", at: base.addingTimeInterval(2)),
                message(.assistant, "answer", turnID: "turn-a", at: base.addingTimeInterval(3)),
                message(.user, "steer", turnID: "turn-a", at: base.addingTimeInterval(4)),
                message(.tool, "tool", turnID: "turn-a", at: base.addingTimeInterval(5)),
                message(.assistant, "steered answer", turnID: "turn-a", at: base.addingTimeInterval(6)),
                message(.user, "second", turnID: "turn-b", at: base.addingTimeInterval(7)),
                message(.assistant, "second answer", turnID: "turn-b", at: base.addingTimeInterval(8))
            ],
            events: [
                ThreadEvent(kind: .notice, createdAt: base, summary: "earlier"),
                ThreadEvent(kind: .toolCompleted, createdAt: base.addingTimeInterval(8), summary: "later"),
                usage
            ],
            subagentRuns: [earlierRun, laterRun],
            goal: goal,
            isPinned: true
        )
        let updatedAt = base.addingTimeInterval(20)

        let result = ThreadHistoryRollback.apply(turnCount: 1, to: &thread, updatedAt: updatedAt)

        XCTAssertEqual(result.removedTurnCount, 1)
        XCTAssertEqual(result.removedMessageCount, 2)
        XCTAssertEqual(result.removedEventCount, 1)
        XCTAssertEqual(result.removedSubagentRunCount, 1)
        XCTAssertEqual(thread.messages.map { $0.content }, [
            "system", "summary", "first", "answer", "steer", "tool", "steered answer"
        ])
        XCTAssertEqual(thread.events.map { $0.summary }, ["earlier", ModelTokenUsageEvent.summary])
        XCTAssertEqual(thread.subagentRuns, [earlierRun])
        XCTAssertEqual(thread.title, "Generated title")
        XCTAssertEqual(thread.projectID, projectID)
        XCTAssertEqual(thread.goal, goal)
        XCTAssertTrue(thread.isPinned)
        XCTAssertEqual(thread.updatedAt, updatedAt)
    }

    func testExcessiveCountRemovesEveryUserTurnButPreservesLeadingContext() {
        let base = Date(timeIntervalSince1970: 2_000)
        var thread = ChatThread(messages: [
            message(.system, "system", at: base),
            message(.assistant, "summary", at: base.addingTimeInterval(1)),
            message(.user, "first", turnID: "turn-a", at: base.addingTimeInterval(2)),
            message(.assistant, "answer", turnID: "turn-a", at: base.addingTimeInterval(3)),
            message(.user, "second", turnID: "turn-b", at: base.addingTimeInterval(4))
        ])

        let result = ThreadHistoryRollback.apply(turnCount: 99, to: &thread)

        XCTAssertEqual(result.removedTurnCount, 2)
        XCTAssertEqual(result.removedMessageCount, 3)
        XCTAssertEqual(thread.messages.map(\.content), ["system", "summary"])
    }

    func testZeroCountIsNoOp() {
        let original = ChatThread(messages: [message(.user, "first", turnID: "turn-a")])
        var thread = original

        let result = ThreadHistoryRollback.apply(turnCount: 0, to: &thread)

        XCTAssertEqual(result, ThreadHistoryRollbackResult())
        XCTAssertEqual(thread, original)
    }

    func testChatMessageIdentifiersRoundTripAndRemainBackwardCompatible() throws {
        let message = ChatMessage(
            role: .user,
            content: "steer",
            turnID: "turn-a",
            clientMessageID: "client-a"
        )

        let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded, message)

        let legacy = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "role": "user",
          "content": "legacy",
          "attachments": [],
          "createdAt": 0
        }
        """
        let legacyDecoded = try JSONDecoder().decode(ChatMessage.self, from: Data(legacy.utf8))
        XCTAssertNil(legacyDecoded.turnID)
        XCTAssertNil(legacyDecoded.clientMessageID)
    }

    private func message(
        _ role: ChatRole,
        _ content: String,
        turnID: String? = nil,
        at createdAt: Date = Date()
    ) -> ChatMessage {
        ChatMessage(role: role, content: content, turnID: turnID, createdAt: createdAt)
    }
}
