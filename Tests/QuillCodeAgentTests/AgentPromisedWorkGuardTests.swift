import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentPromisedWorkGuardTests: XCTestCase {
    func testDetectsFutureWorkPromise() {
        XCTAssertTrue(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I'll check your Quill's disk usage now.",
            tools: [.shellRun]
        ))
        XCTAssertTrue(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I will create the file.",
            tools: [.fileWrite]
        ))
    }

    func testDoesNotDetectCapabilityOrPermissionAnswers() {
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I can run commands, edit files, and review diffs when you ask.",
            tools: [.shellRun]
        ))
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "Do you want me to run the migration?",
            tools: [.shellRun]
        ))
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I will not run that command.",
            tools: [.shellRun]
        ))
    }

    func testDoesNotRequestCorrectionWithoutTools() {
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "I'll run the command now.",
            tools: []
        ))
    }

    func testSuppressesPromisedWorkStreamingPreview() {
        XCTAssertTrue(AgentPromisedWorkGuard.shouldSuppressStreamingPreview(
            for: "I'll"
        ))
        XCTAssertTrue(AgentPromisedWorkGuard.shouldSuppressStreamingPreview(
            for: "I'll check your Quill's disk usage now."
        ))
        XCTAssertTrue(AgentPromisedWorkGuard.shouldSuppressStreamingPreview(
            for: "I will check your Quill's disk usage now."
        ))
        XCTAssertFalse(AgentPromisedWorkGuard.shouldSuppressStreamingPreview(
            for: "I can run commands, edit files, and review diffs when you ask."
        ))
        XCTAssertFalse(AgentPromisedWorkGuard.shouldSuppressStreamingPreview(
            for: "Let me know if you want a deeper review."
        ))
    }

    func testCorrectionPromptKeepsSchemaBoundaryExplicit() {
        let prompt = AgentPromisedWorkGuard.correctionPrompt(
            assistantText: "I'll run whoami.",
            userMessage: "whoami?"
        )

        XCTAssertTrue(prompt.contains("Return exactly one QuillCode JSON action"))
        XCTAssertTrue(prompt.contains(#"{"type":"tool",...}"#))
        XCTAssertTrue(prompt.contains(#"{"type":"say","text":"..."}"#))
        XCTAssertTrue(prompt.contains("whoami?"))
    }

    // MARK: - Trailing-off narration (the coworker-task "stops mid-plan" failure)

    /// The exact live failure: the model narrates completed steps and ends its turn on a bare step
    /// heading with no content and no tool call. No "I'll…" phrase appears, so only the structural
    /// check can catch it. -> correction requested.
    func testTrailingStepHeadingAfterEarlierStepsRequestsCorrection() {
        let liveShape = """
        **Step 1: Clone** — Done. Cloned python-dotenv into ./python-dotenv.

        **Step 2: Architecture Map**
        The package lives under src/dotenv/ with a flat module structure.

        **Step 3: Setting up virtualenv with uv**
        """
        XCTAssertTrue(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: liveShape,
            tools: [.shellRun]
        ))
    }

    /// A trailing lead-in colon whose content never arrived is the same truncation smell. -> correction.
    func testTrailingLeadInColonRequestsCorrection() {
        XCTAssertTrue(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "The clone finished cleanly.\n\nNext steps:",
            tools: [.shellRun]
        ))
    }

    /// A COMPLETE numbered walkthrough — content after the last heading, and a real final line —
    /// must not fire (precision guard: this is the everyday happy path).
    func testCompleteStepNarrationDoesNotRequestCorrection() {
        let complete = """
        **Step 1: Clone** — Done.

        **Step 2: Tests** — Ran the suite.

        All 138 tests passed. Grand total: $14,600.
        """
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: complete,
            tools: [.shellRun]
        ))
    }

    /// A single step-heading with no earlier steps is a short answer, not a truncation. -> no fire.
    func testSingleStepHeadingAloneDoesNotRequestCorrection() {
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "Step 1: run `make test` from the repo root.",
            tools: [.shellRun]
        ))
    }

    /// Ordinary final lines containing colons mid-line ("Top region: West") are untouched.
    func testColonInsideFinalLineDoesNotRequestCorrection() {
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "Cleaning finished.\nGrand total: $14,600\nTop region: West",
            tools: [.shellRun]
        ))
    }

    /// Without tools there is nothing to continue WITH; structural truncation must not fire either.
    func testTrailingNarrationWithoutToolsDoesNotRequestCorrection() {
        XCTAssertFalse(AgentPromisedWorkGuard.shouldRequestCorrection(
            for: "Step 1: done.\nStep 2: also done.\nStep 3: Setting up",
            tools: []
        ))
    }

    /// Streaming previews always end mid-something; the structural check must NOT suppress them.
    func testStreamingPreviewIgnoresTrailingNarration() {
        XCTAssertFalse(AgentPromisedWorkGuard.shouldSuppressStreamingPreview(
            for: "Step 1: done.\n\nStep 2: Setting up the environment"
        ))
    }
}
