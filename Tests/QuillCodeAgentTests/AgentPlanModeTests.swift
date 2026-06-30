import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentPlanModeTests: XCTestCase {
    func testPlanModeBlocksAMutatingToolThatAutoModeWouldRun() async throws {
        let root = try makeTempDirectory()
        let planned = root.appendingPathComponent("planned.txt")

        // Plan mode blocks the mutating shell: nothing runs, the file is NOT created, and an
        // approval is surfaced instead. Asserting the file is absent proves a genuine block —
        // a leaked execution would have created it, so this is not a vacuous "flag-only" check.
        let planResult = try await AgentRunner().send(
            "run touch planned.txt",
            in: ChatThread(mode: .plan),
            workspaceRoot: root
        )
        XCTAssertTrue(planResult.toolResults.isEmpty, "no tool should execute while planning")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: planned.path),
            "the mutating shell must not touch the filesystem while planning"
        )
        XCTAssertTrue(planResult.thread.events.contains { $0.kind == .approvalRequested })

        // Auto mode runs the exact same command — proving the block above is real, not vacuous.
        let autoResult = try await AgentRunner().send(
            "run touch planned.txt",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )
        XCTAssertEqual(autoResult.toolResults.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: planned.path))
    }

    func testPlanModeBlocksMutatingToolEvenWithImmediateActionPreflight() async throws {
        // Production enables the immediate-action preflight (RuntimeFactory). The preflight only
        // chooses the action faster; it still flows through the same gate — so plan mode must
        // block a mutating shell on this path too, not just the LLM path.
        let root = try makeTempDirectory()
        let planned = root.appendingPathComponent("preflight.txt")
        let runner = AgentRunner(enablesImmediateActionPreflight: true)

        let result = try await runner.send(
            "run touch preflight.txt",
            in: ChatThread(mode: .plan),
            workspaceRoot: root
        )
        XCTAssertTrue(result.toolResults.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: planned.path))
        XCTAssertTrue(result.thread.events.contains { $0.kind == .approvalRequested })
    }
}
