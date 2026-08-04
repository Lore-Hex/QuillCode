import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// F30 — word-budget adherence. Live failure: "a 300-word Monday exec update" produced 222 words
/// on one model and 185 on another; the only quantitative spec in the task went unchecked.
final class AgentQuantitativeSpecGateTests: XCTestCase {
    // MARK: - Budget extraction

    func testExtractsHyphenAndSpaceForms() {
        XCTAssertEqual(AgentQuantitativeSpecGate.wordBudget(in: "write a 300-word update")?.words, 300)
        XCTAssertEqual(AgentQuantitativeSpecGate.wordBudget(in: "a 1500 word essay")?.words, 1500)
        XCTAssertEqual(AgentQuantitativeSpecGate.wordBudget(in: "about 250 words on X")?.words, 250)
    }

    func testUnboundedOrTinyFiguresDoNotArm() {
        XCTAssertNil(AgentQuantitativeSpecGate.wordBudget(in: "summarize in your own words"))
        XCTAssertNil(AgentQuantitativeSpecGate.wordBudget(in: "a 3 word answer"))
        XCTAssertNil(AgentQuantitativeSpecGate.wordBudget(in: "no numbers here"))
    }

    func testToleranceBandIsTwentyFivePercent() {
        let budget = try! XCTUnwrap(AgentQuantitativeSpecGate.wordBudget(in: "300-word memo"))
        XCTAssertEqual(budget.minimum, 225)
        XCTAssertEqual(budget.maximum, 375)
    }

    // MARK: - Violations

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wordbudget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testShortDeliverableViolatesCompliantOnePasses() throws {
        let root = try makeWorkspace()
        let short = Array(repeating: "word", count: 185).joined(separator: " ")
        try short.write(to: root.appendingPathComponent("exec-update.md"), atomically: true, encoding: .utf8)
        let message = "Turn my notes into a 300-word exec update. Save it as exec-update.md."
        let violations = AgentQuantitativeSpecGate.violations(userMessage: message, workspaceRoot: root)
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.actual, 185)

        let fine = Array(repeating: "word", count: 290).joined(separator: " ")
        try fine.write(to: root.appendingPathComponent("exec-update.md"), atomically: true, encoding: .utf8)
        XCTAssertTrue(AgentQuantitativeSpecGate.violations(userMessage: message, workspaceRoot: root).isEmpty)
    }

    func testNoBudgetOrNoMarkdownDeliverableNeverViolates() throws {
        let root = try makeWorkspace()
        try "a b c".write(to: root.appendingPathComponent("out.md"), atomically: true, encoding: .utf8)
        XCTAssertTrue(AgentQuantitativeSpecGate.violations(
            userMessage: "write out.md with the results",
            workspaceRoot: root
        ).isEmpty)
        XCTAssertTrue(AgentQuantitativeSpecGate.violations(
            userMessage: "build a 300-word summary into report.csv, save report.csv",
            workspaceRoot: root
        ).isEmpty)
    }

    // MARK: - End-to-end recovery

    private actor ScriptedState {
        var steps: [AgentAction]
        let root: URL
        init(_ steps: [AgentAction], root: URL) { self.steps = steps; self.root = root }
        func next() -> AgentAction {
            guard !steps.isEmpty else { return .say("out of steps") }
            let step = steps.removeFirst()
            if case .say(let text) = step, text == "REWRITE_THEN_DONE" {
                let full = Array(repeating: "substance", count: 300).joined(separator: " ")
                try? full.write(
                    to: root.appendingPathComponent("exec-update.md"), atomically: true, encoding: .utf8
                )
                return .say("exec-update.md rewritten to the requested length.")
            }
            return step
        }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            await state.next()
        }
    }

    func testShortDeliverableIsCorrectedAndRunSucceeds() async throws {
        let root = try makeWorkspace()
        let short = Array(repeating: "word", count: 185).joined(separator: " ")
        try short.write(to: root.appendingPathComponent("exec-update.md"), atomically: true, encoding: .utf8)
        let state = ScriptedState([.say("Done."), .say("REWRITE_THEN_DONE")], root: root)
        let runner = AgentRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "Turn my notes into a 300-word exec update. Save it as exec-update.md.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        let final = try XCTUnwrap(result.thread.messages.last?.content)
        XCTAssertTrue(final.contains("rewritten"))
        XCTAssertFalse(final.contains("⚠ Length"))
        let text = try String(contentsOf: root.appendingPathComponent("exec-update.md"), encoding: .utf8)
        XCTAssertGreaterThanOrEqual(AgentQuantitativeSpecGate.wordCount(of: text), 225)
    }

    func testPersistentShortfallSurfacesLengthNotice() async throws {
        let root = try makeWorkspace()
        let short = Array(repeating: "word", count: 100).joined(separator: " ")
        try short.write(to: root.appendingPathComponent("exec-update.md"), atomically: true, encoding: .utf8)
        let state = ScriptedState([.say("Done."), .say("Done."), .say("Done.")], root: root)
        let runner = AgentRunner(llm: ScriptedClient(state: state))

        let result = try await runner.send(
            "Turn my notes into a 300-word exec update. Save it as exec-update.md.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        let final = try XCTUnwrap(result.thread.messages.last?.content)
        XCTAssertTrue(final.contains("⚠ Length"))
        XCTAssertTrue(final.contains("100 words"))
    }
}
