import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

/// The preflight planner exists for TERSE single commands; a multi-step task prompt is model
/// territory. These lock the live hijack: "(1) clone … (2) list the repository's top-level
/// directory …" fired `host.file.list {"path": "order"}` (the word after "in" in "do these in
/// order"), the tool failed on the nonexistent path, and the run ended without the model ever
/// seeing the task.
final class AgentImmediateActionMultiStepGateTests: XCTestCase {
    private let tools: [ToolDefinition] = [.shellRun, .fileList, .fileRead, .fileWrite]

    /// The exact live prompt shape must not be hijacked. -> nil (the model gets the turn).
    func testEnumeratedTaskPromptIsNeverPreflighted() {
        let prompt = "Do these in order with tools: (1) clone https://github.com/x/y into ./y "
            + "(2) list the repository's top-level directory (3) read the first 30 lines of its "
            + "README.md (4) tell me in two sentences what the project does."
        XCTAssertNil(AgentImmediateActionPlanner.action(for: prompt, tools: tools))
    }

    func testNumberedLinesPromptIsNeverPreflighted() {
        let prompt = """
        1. run the test suite
        2. list the files in src
        """
        XCTAssertNil(AgentImmediateActionPlanner.action(for: prompt, tools: tools))
    }

    /// A single "(1)" citation is not an enumeration; terse commands keep their fast path.
    func testSingleMarkerAndTerseCommandsStillPreflight() {
        XCTAssertFalse(AgentImmediateActionPlanner.isMultiStepTaskPrompt("run whoami"))
        XCTAssertFalse(AgentImmediateActionPlanner.isMultiStepTaskPrompt(
            "see item (1) in the changelog and list the files here"
        ))
        XCTAssertNotNil(AgentImmediateActionPlanner.action(for: "run whoami", tools: tools))
        XCTAssertNotNil(AgentImmediateActionPlanner.action(for: "list files in src", tools: tools))
    }

    func testMultiStepDetectionMatchesBothMarkerStyles() {
        XCTAssertTrue(AgentImmediateActionPlanner.isMultiStepTaskPrompt("(1) clone (2) test"))
        XCTAssertTrue(AgentImmediateActionPlanner.isMultiStepTaskPrompt("1. clone\n2. test"))
        XCTAssertTrue(AgentImmediateActionPlanner.isMultiStepTaskPrompt("1) clone\n2) test"))
        XCTAssertFalse(AgentImmediateActionPlanner.isMultiStepTaskPrompt("list files in src"))
    }

    // MARK: - File-list scope-marker precision

    /// A scope marker BEFORE any listing keyword is unrelated prose, never a path source: the "in"
    /// of "in order" must not name a directory. (Reachable via terse prompts even with the planner
    /// gate, so the parser holds its own line.)
    func testScopeMarkerBeforeListingKeywordIsIgnored() {
        let request = AgentFileListRequestParser.request(from: "in order, list the files here")
        XCTAssertEqual(request?.path, ".")
    }

    /// The everyday terse command keeps its explicit path.
    func testListFilesInDirectoryStillExtractsPath() {
        let request = AgentFileListRequestParser.request(from: "list files in src")
        XCTAssertEqual(request?.path, "src")
    }
}
