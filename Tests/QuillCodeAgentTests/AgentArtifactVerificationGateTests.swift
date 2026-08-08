import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentArtifactVerificationGateTests: XCTestCase {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-verification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testRecognizesExplicitWriteThenReadRequest() {
        XCTAssertTrue(AgentArtifactVerificationGate.requiresReadback(
            in: "Save the result to outputs/report.md. After writing, read the saved file back to verify it."
        ))
        XCTAssertFalse(AgentArtifactVerificationGate.requiresReadback(
            in: "Read inputs/report.md and summarize it."
        ))
    }

    func testPathMatchingDistinguishesRelativeFilesWithTheSameBasename() {
        XCTAssertFalse(AgentArtifactVerificationGate.pathsMatch(
            "outputs/report.md",
            "report.md"
        ))
        XCTAssertTrue(AgentArtifactVerificationGate.pathsMatch(
            "/tmp/workspace/outputs/report.md",
            "outputs/report.md"
        ))
    }

    func testPrematureReadOfNamedOutputGetsWriteFirstCorrection() throws {
        let root = try makeWorkspace()
        let prompt = "Save the result to outputs/report.md. After writing, read the saved file back to verify it."
        let call = ToolCall(
            name: "host.file.read",
            argumentsJSON: ToolArguments.json(["path": "./outputs/report.md"])
        )

        let correction = try XCTUnwrap(AgentArtifactVerificationGate.preWriteCorrection(
            for: call,
            userMessage: prompt,
            workspaceRoot: root
        ))
        XCTAssertEqual(correction.path, "outputs/report.md")
        XCTAssertTrue(correction.prompt.contains("host.file.write"))

        let output = root.appendingPathComponent("outputs/report.md")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "done".write(to: output, atomically: true, encoding: .utf8)
        XCTAssertNil(AgentArtifactVerificationGate.preWriteCorrection(
            for: call,
            userMessage: prompt,
            workspaceRoot: root
        ))
    }

    func testRunnerSkipsPrematureReadAndVerifiesAfterWrite() async throws {
        let root = try makeWorkspace()
        let read = ToolCall(
            name: "host.file.read",
            argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
        )
        let write = ToolCall(
            name: "host.file.write",
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Decision\n\nShip the focused workflow.\n",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(read),
                .tool(write),
                .say("The report is complete."),
                .say("The report is complete and verified."),
            ]),
            maxToolSteps: 8
        )

        let result = try await runner.send(
            "Save the complete deliverable to outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(title: "verification"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 2, "the premature read must not create a failed tool result")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(result.thread.messages.last?.content, "The report is complete and verified.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("before creating it")
        })
    }

    func testRunnerDoesNotVerifyRequiredOutputByReadingRootLevelDuplicate() async throws {
        let root = try makeWorkspace()
        let outputWrite = ToolCall(
            name: "host.file.write",
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": "# Required output\n\nThe required report is complete.\n",
            ])
        )
        let rootWrite = ToolCall(
            name: "host.file.write",
            argumentsJSON: ToolArguments.json([
                "path": "report.md",
                "content": "# Wrong duplicate\n\nThis is not the requested output path.\n",
            ])
        )
        let rootRead = ToolCall(
            name: "host.file.read",
            argumentsJSON: ToolArguments.json(["path": "report.md"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(outputWrite),
                .tool(rootWrite),
                .tool(rootRead),
                .say("The report is complete."),
                .say("The required output is complete and verified."),
            ]),
            maxToolSteps: 8
        )

        let result = try await runner.send(
            "Save the deliverable to outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(title: "duplicate-path verification"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 4, "the required output needs its own forced readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(result.thread.messages.last?.content, "The required output is complete and verified.")
    }
}
