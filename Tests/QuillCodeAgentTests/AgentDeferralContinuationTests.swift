import XCTest
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeAgent

/// The unattended-stall fix, end to end. The live failure (BFCL setup): with real work remaining,
/// the model emitted "…What would you like me to do next?" and, because a bare `.say` ends the run,
/// the whole task stalled with nobody there to answer.
///
/// A run must NOT end on a task-abandoning deferral: it re-drives once, and if the model then makes
/// progress the run continues to a real finish.
final class AgentDeferralContinuationTests: XCTestCase {
    func testRunReDrivesADeferralIntoProgressInsteadOfStalling() async throws {
        let root = try makeTempDirectory()
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "out.txt", "content": "done\n"])
        )
        // 1) deferral (must be re-driven), 2) the tool the model does after the nudge, 3) final say.
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("The venv is set up. What would you like me to do next — run the eval or something else?"),
            .tool(write),
            .say("Wrote out.txt.")
        ]))

        let result = try await runner.send(
            "Set up the tool and write out.txt.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        // The deferral did NOT terminate the run — the file got written and the run finished cleanly.
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("out.txt"), encoding: .utf8),
            "done\n"
        )
        XCTAssertEqual(result.thread.messages.last?.content, "Wrote out.txt.")
        // The stall message must not be what the run ended on.
        XCTAssertFalse(result.thread.messages.last?.content.contains("What would you like me to do next") ?? false)
    }

    /// A model that keeps asking (genuinely wants input) is allowed through rather than looping or
    /// erroring — the deferral is a soft correction, not a hard failure.
    func testPersistentDeferralIsAllowedThroughNotThrown() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .say("How would you like me to proceed?"),
            .say("How would you like me to proceed?"),
            .say("How would you like me to proceed?"),
            .say("How would you like me to proceed?")
        ]))

        // Must not throw; the run ends with the (allowed) question rather than crashing.
        let result = try await runner.send(
            "Do the task.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )
        XCTAssertTrue(result.thread.messages.last?.content.contains("proceed") ?? false)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-deferral-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
