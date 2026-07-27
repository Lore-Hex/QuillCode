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
            "see item (1) in the changelog and release notes here"
        ))
        // Result-presentation continuations stay terse: they ask for the first action's output.
        XCTAssertFalse(AgentImmediateActionPlanner.isMultiStepTaskPrompt(
            "Read `hello.txt` and tell me its exact content"
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

    /// Prose-chained steps ("clone X, then list Y, then read Z") are multi-step too — this exact
    /// shape produced the second live hijack: `host.file.list {"path": "two"}` from the trailing
    /// "tell me in two sentences". A single "run tests then commit" keeps the fast path.
    func testThenChainedPromptIsNeverPreflighted() {
        let prompt = "Clone https://github.com/x/y into ./y, then list the top-level directory of "
            + "the cloned repo, then read the first 30 lines of its README.md, then tell me in two "
            + "sentences what the project does."
        XCTAssertTrue(AgentImmediateActionPlanner.isMultiStepTaskPrompt(prompt))
        XCTAssertNil(AgentImmediateActionPlanner.action(for: prompt, tools: tools))
        XCTAssertFalse(AgentImmediateActionPlanner.isMultiStepTaskPrompt("run tests then commit"))
    }

    /// A scope marker far downstream of the listing keyword is prose, not a path: "list the
    /// directory of the cloned repo, then tell me in two sentences" must not extract "two".
    func testDistantScopeMarkerIsIgnored() {
        let request = AgentFileListRequestParser.request(
            from: "list the top-level directory of the cloned repo and reply in two sentences"
        )
        XCTAssertEqual(request?.path, ".")
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

    /// The third live hijack shape: "Read notes.md AND TURN it into a PRD…" — the preflight
    /// answered the read and ended the run with the task untouched. An " and <action verb>"
    /// continuation is a compound task; a noun list ("files and folders") is not.
    func testAndActionContinuationIsNeverPreflighted() {
        let prompt = "Read notes.md and turn it into a structured PRD written to PRD.md"
        XCTAssertTrue(AgentImmediateActionPlanner.isMultiStepTaskPrompt(prompt))
        XCTAssertNil(AgentImmediateActionPlanner.action(for: prompt, tools: tools))
        XCTAssertFalse(AgentImmediateActionPlanner.isMultiStepTaskPrompt("list files and folders here"))
    }

    /// Nobody types a 200-character message to run one terse command; long prompts are tasks.
    func testLongPromptsAreNeverPreflighted() {
        let long = "Read the service log and figure out why the collector keeps restarting "
            + "overnight, paying attention to the supervisor lines, the Python traceback, the "
            + "config values it prints at startup, and anything else that looks suspicious."
        XCTAssertGreaterThan(long.count, AgentImmediateActionPlanner.terseCommandCharacterLimit)
        XCTAssertTrue(AgentImmediateActionPlanner.isMultiStepTaskPrompt(long))
        XCTAssertFalse(AgentImmediateActionPlanner.isMultiStepTaskPrompt("read src/main.py"))
    }
}
