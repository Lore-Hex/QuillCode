import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspacePlanProgressBuilderTests: XCTestCase {
    private func item(_ step: String, _ status: AgentPlanItemStatus) -> AgentPlanItem {
        AgentPlanItem(step: step, status: status)
    }

    private func progress(
        _ items: [AgentPlanItem],
        status: String = TopBarAgentStatusLabel.running
    ) -> WorkspacePlanProgress? {
        WorkspacePlanProgressBuilder.progress(from: AgentPlanUpdate(plan: items), agentStatus: status)
    }

    // MARK: - Thread entry point

    func testNilThreadIsNil() {
        XCTAssertNil(WorkspacePlanProgressBuilder.progress(for: nil, agentStatus: "Running"))
    }

    func testThreadWithNoPlanIsNil() {
        let thread = ChatThread(title: "t", messages: [], events: [])
        XCTAssertNil(WorkspacePlanProgressBuilder.progress(for: thread, agentStatus: "Running"))
    }

    func testThreadWithAuthoredPlanIsRead() throws {
        // Round-trips through PlanUpdateToolExecutor.latestUpdate exactly as the real event stream does.
        let update = AgentPlanUpdate(plan: [
            item("Read the code", .completed),
            item("Write the fix", .inProgress),
            item("Add tests", .pending)
        ])
        let result = ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        let event = ThreadEvent(
            kind: .toolCompleted,
            summary: "host.plan.update completed",
            payloadJSON: try JSONHelpers.encodePretty(result)
        )
        let thread = ChatThread(title: "t", messages: [], events: [event])
        let p = WorkspacePlanProgressBuilder.progress(
            for: thread,
            agentStatus: TopBarAgentStatusLabel.running
        )
        XCTAssertEqual(p?.stepCounterLabel, "2/3")
        XCTAssertEqual(p?.currentStepTitle, "Write the fix")
        XCTAssertEqual(p?.completedCount, 1)
    }

    // MARK: - Pure core derivation

    func testEmptyPlanIsNil() {
        XCTAssertNil(progress([]))
    }

    func testSingleInProgressStep() {
        let p = progress([item("Do the thing", .inProgress)])
        XCTAssertEqual(p?.totalCount, 1)
        XCTAssertEqual(p?.completedCount, 0)
        XCTAssertEqual(p?.currentStepIndex, 1)
        XCTAssertEqual(p?.stepCounterLabel, "1/1")
        XCTAssertEqual(p?.fraction, 0.5)
        XCTAssertEqual(p?.isRunning, true)
        XCTAssertEqual(p?.isComplete, false)
    }

    func testSingleCompletedStep() {
        let p = progress([item("Done", .completed)])
        XCTAssertEqual(p?.isComplete, true)
        XCTAssertEqual(p?.fraction, 1.0)
        XCTAssertEqual(p?.currentStepIndex, 1)
        XCTAssertEqual(p?.completedCount, 1)
    }

    func testAllCompletedMultiStep() {
        let p = progress([
            item("a", .completed),
            item("b", .completed),
            item("c", .completed)
        ])
        XCTAssertEqual(p?.currentStepIndex, 3)     // clamps to last when nothing pending/in-progress
        XCTAssertEqual(p?.isComplete, true)
        XCTAssertEqual(p?.fraction, 1.0)
        XCTAssertEqual(p?.stepCounterLabel, "3/3")
    }

    func testInProgressWinsAndHalfCredits() {
        // 2 completed, 1 in-progress, 2 pending → surface the in-progress (index 3), fraction (2+0.5)/5.
        let p = progress([
            item("a", .completed), item("b", .completed),
            item("c", .inProgress),
            item("d", .pending), item("e", .pending)
        ])
        XCTAssertEqual(p?.currentStepIndex, 3)
        XCTAssertEqual(p?.currentStepTitle, "c")
        XCTAssertEqual(p?.completedCount, 2)
        XCTAssertEqual(p?.fraction, 0.5)           // (2 + 0.5) / 5
        XCTAssertEqual(p?.isComplete, false)
    }

    func testNextPendingWhenNothingInProgress() {
        // 1 completed, rest pending, none in-progress → surface first pending (index 2), no half-credit.
        let p = progress([
            item("a", .completed),
            item("b", .pending),
            item("c", .pending),
            item("d", .pending)
        ])
        XCTAssertEqual(p?.currentStepIndex, 2)
        XCTAssertEqual(p?.currentStepTitle, "b")
        XCTAssertEqual(p?.fraction, 0.25)          // 1 / 4, no in-progress bonus
    }

    func testFailedRunFreezesButKeepsAuthoredPosition() {
        // A stopped/failed run: isRunning is false, but the plan still shows WHERE it stalled — the
        // half-credit reflects the plan's authored in-progress state, not liveness (documented behavior).
        let p = progress(
            [item("a", .completed), item("b", .inProgress), item("c", .pending)],
            status: TopBarAgentStatusLabel.failed
        )
        XCTAssertEqual(p?.isRunning, false)
        XCTAssertEqual(p?.currentStepIndex, 2)
        XCTAssertEqual(p?.fraction, 0.5)           // (1 + 0.5) / 3
    }

    func testOverLongStepTitleIsBounded() {
        let long = String(repeating: "x", count: 200)
        let p = progress([item(long, .inProgress)])
        XCTAssertEqual(p?.currentStepTitle.count, 83)   // 80 + "..."
        XCTAssertEqual(p?.currentStepTitle.hasSuffix("..."), true)
    }

    // MARK: - Shared classifier (the drift fix)

    func testClassifierMatchesTheActiveLabels() {
        let active = [TopBarAgentStatusLabel.running, TopBarAgentStatusLabel.streaming,
                      TopBarAgentStatusLabel.queued, TopBarAgentStatusLabel.terminal]
        let inactive = [TopBarAgentStatusLabel.idle, TopBarAgentStatusLabel.review,
                        TopBarAgentStatusLabel.finishing, TopBarAgentStatusLabel.failed,
                        TopBarAgentStatusLabel.stopped]
        for label in active {
            XCTAssertTrue(AgentStatusClassifier.isActive(label), label)
        }
        for label in inactive {
            XCTAssertFalse(AgentStatusClassifier.isActive(label), label)
        }
    }
}
