import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSubagentRunToolRequestDecoderTests: XCTestCase {
    func testDecodesAndNormalizesExecutableWorkerGraph() throws {
        let call = ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: """
            {
              "objective": "  Review   this branch in parallel.  ",
              "workers": [
                {"name":" Explorer ","role":" Inspect   implementation. "},
                {
                  "name":"Verifier",
                  "role":"Run focused checks.",
                  "dependsOn":["Explorer", "explorer"],
                  "groupPath":["Release"]
                }
              ],
              "maxConcurrentWorkers": 2
            }
            """
        )

        let request = try WorkspaceSubagentRunToolRequestDecoder.decode(call)

        XCTAssertEqual(request.objective, "Review this branch in parallel.")
        XCTAssertEqual(request.maxConcurrentWorkers, 2)
        XCTAssertEqual(request.workers.map(\.name), ["Explorer", "Verifier"])
        XCTAssertEqual(request.workers[0].role, "Inspect implementation.")
        XCTAssertEqual(request.workers[1].dependsOn, ["Explorer"])
        XCTAssertEqual(request.workers[1].groupPath, ["Release"])
    }

    func testRejectsDuplicateWorkerNamesCaseInsensitively() {
        let call = toolCall(workers: [
            ["name": "Verifier", "role": "Run checks."],
            ["name": "verifier", "role": "Inspect failures."]
        ])

        XCTAssertThrowsError(try WorkspaceSubagentRunToolRequestDecoder.decode(call)) { error in
            XCTAssertEqual(error.localizedDescription, "Delegated worker names must be unique.")
        }
    }

    func testRejectsUnknownDependenciesInsteadOfSilentlyDroppingThem() {
        let call = toolCall(workers: [[
            "name": "Verifier",
            "role": "Run checks.",
            "dependsOn": ["Builder"]
        ]])

        XCTAssertThrowsError(try WorkspaceSubagentRunToolRequestDecoder.decode(call)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Delegated worker Verifier depends on unknown worker Builder."
            )
        }
    }

    func testRejectsDependencyOverflowInsteadOfChangingTheWorkerGraph() {
        let call = toolCall(workers: [[
            "name": "Verifier",
            "role": "Run checks.",
            "dependsOn": (1...7).map { "Worker \($0)" }
        ]])

        XCTAssertThrowsError(try WorkspaceSubagentRunToolRequestDecoder.decode(call)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Delegated worker Verifier has 7 dependencies; keep it to 6 or fewer."
            )
        }
    }

    func testRejectsMalformedArgumentsWithActionableCopy() {
        let call = ToolCall(name: ToolDefinition.subagentsRun.name, argumentsJSON: #"{"workers":[]}"#)

        XCTAssertThrowsError(try WorkspaceSubagentRunToolRequestDecoder.decode(call)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Run Subagents needs objective, workers, and optional maxConcurrentWorkers JSON."
            )
        }
    }

    private func toolCall(workers: [[String: Any]]) -> ToolCall {
        ToolCall(
            name: ToolDefinition.subagentsRun.name,
            argumentsJSON: ToolArguments.json([
                "objective": "Audit the release.",
                "workers": workers
            ])
        )
    }
}
