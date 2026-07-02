import XCTest

/// Locks the construction-site invariant: the subagent worker — a one-shot auxiliary call whose
/// unique prompt is never re-sent — must be wired to a prompt-caching-DISABLED client, the same
/// class RuntimeFactory disables for context summaries. A breakpoint there could only ever be a
/// cache write with no read. This gate fails if a future edit reverts the WorkspaceModel wiring
/// back to the raw run-loop client.
final class ParitySubagentPromptCacheGateTests: QuillCodeParityTestCase {
    func testSubagentWorkerIsWiredToACachingDisabledClient() throws {
        let source = try Self.appSourceText(named: "WorkspaceModel.swift")

        XCTAssertTrue(
            source.contains("LLMWorkspaceSubagentWorker.scheduledWorker"),
            "expected the subagent scheduler to be built from LLMWorkspaceSubagentWorker.scheduledWorker"
        )
        XCTAssertTrue(
            source.contains("scheduledWorker(\n                llm: disablingPromptCachingIfSupported(runner.llm)")
                || source.contains("disablingPromptCachingIfSupported(runner.llm)"),
            "the subagent worker's llm must be routed through disablingPromptCachingIfSupported(runner.llm)"
        )
        XCTAssertFalse(
            source.contains("scheduledWorker(llm: runner.llm)"),
            "the subagent worker must NOT be wired to the raw run-loop client (that one keeps caching on)"
        )
    }
}
