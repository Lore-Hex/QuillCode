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

    func testDetectsOfficeCoworkerFutureWorkPromises() {
        let promisedOfficeTasks = [
            "I'll inventory the brand assets and flag low-res logos.",
            "I will standardize the Stage values and highlight missing close dates.",
            "I'm going to chart kWh usage and draft the summary.",
            "Let me pull the last eight weeks and write the trend callouts."
        ]

        for response in promisedOfficeTasks {
            XCTAssertTrue(
                AgentPromisedWorkGuard.shouldRequestCorrection(for: response, tools: [.shellRun]),
                response
            )
        }
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

    func testNegativeClauseDoesNotHideLaterPositiveWorkPromise() {
        let liveTask311Stall = """
        Understood. Continuing task 311 from the existing outputs. I will not retry the blocked
        browser and will not claim LinkedIn verification is complete. I will complete all independent
        public-web research and every deliverable, then read back each artifact to verify it.
        """

        XCTAssertEqual(
            AgentPromisedWorkGuard.correctionNeeded(
                for: liveTask311Stall,
                tools: [.fileRead, .fileWrite, .webSearch]
            ),
            .promisedWork
        )
    }

    func testNegativePromiseStillDoesNotRequestCorrection() {
        XCTAssertNil(AgentPromisedWorkGuard.correctionNeeded(
            for: "I will not retry the blocked browser or claim the unavailable verification.",
            tools: [.webSearch]
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

extension AgentPromisedWorkGuardTests {
    // MARK: - Task-abandoning deferral (the unattended-stall fix)

    func testDetectsDeferralQuestions() {
        let deferrals = [
            "I'm ready to continue. Based on the context, we're working on the BFCL evaluation. What would you like me to do next — run a specific evaluation, analyze available models, or something else?",
            "The venv is set up. What would you like me to do?",
            "How would you like me to proceed?",
            "How should I proceed with the remaining steps?",
            "Let me know how you'd like me to proceed.",
            "What should I do next?"
        ]
        for text in deferrals {
            XCTAssertEqual(
                AgentPromisedWorkGuard.correctionNeeded(for: text, tools: [.shellRun]),
                .deferralToUser,
                "should re-drive: \(text)"
            )
        }
    }

    func testPoliteCompletionCloserIsNotADeferral() {
        let closers = [
            "Done — I created report.md and verified its contents. Let me know if you'd like anything else.",
            "All 42 tests pass. Is there anything else you need?",
            "The summary is ready in findings.md."
        ]
        for text in closers {
            XCTAssertNil(
                AgentPromisedWorkGuard.correctionNeeded(for: text, tools: [.shellRun]),
                "must not re-drive a finished task: \(text)"
            )
        }
    }

    func testSpecificPermissionQuestionIsNotAWholeTaskDeferral() {
        XCTAssertNil(AgentPromisedWorkGuard.correctionNeeded(
            for: "This will permanently delete 12 files. Should I proceed?",
            tools: [.shellRun]
        ))
    }

    func testDeferralIsNotAHardFailure() {
        XCTAssertFalse(AgentSayCorrection.deferralToUser.isHardFailure)
        XCTAssertTrue(AgentSayCorrection.promisedWork.isHardFailure)
    }

    func testDeferralCorrectionPromptTellsModelToContinueAutonomously() {
        let prompt = AgentPromisedWorkGuard.correctionPrompt(
            for: .deferralToUser,
            assistantText: "What would you like me to do next?",
            userMessage: "Set up BFCL and run a small eval."
        )
        XCTAssertTrue(prompt.contains("autonomously"))
        XCTAssertTrue(prompt.lowercased().contains("do not ask the user"))
        XCTAssertTrue(prompt.lowercased().contains("blocked"))
    }
}

extension AgentPromisedWorkGuardTests {
    // MARK: - "Let's …" + readiness-to-proceed (the gemini verbose-planner stalls)

    func testDetectsLetsWorkPromise() {
        XCTAssertEqual(
            AgentPromisedWorkGuard.correctionNeeded(
                for: "I verified the catalog. Let's design and run a budget-friendly evaluation within the $5 ceiling.",
                tools: [.shellRun]
            ),
            .promisedWork
        )
    }

    func testLetsWithoutWorkVerbIsNotAPromise() {
        // The work-verb gate: "Let's see …" is a final answer, not a promise to do work.
        XCTAssertNil(
            AgentPromisedWorkGuard.correctionNeeded(
                for: "Let's see — the totals reconcile, so the ledger is balanced.",
                tools: [.shellRun]
            )
        )
    }

    func testDetectsReadinessToProceedDeclaration() {
        // The exact live gem3 stall: explored everything, then declared readiness with no action.
        let readiness = [
            "I have reviewed the handlers and configs. I am fully prepared to proceed with the execution steps under the $5 ceiling.",
            "The environment is set up. I am ready to proceed.",
            "I will now proceed to run the evaluation.",
            "Ready to begin the benchmark."
        ]
        for text in readiness {
            XCTAssertEqual(
                AgentPromisedWorkGuard.correctionNeeded(for: text, tools: [.shellRun]),
                .promisedWork,
                "readiness declaration should re-drive: \(text)"
            )
        }
    }

    func testDetectsEvidenceReadyAnnouncementWithoutFinalSynthesis() {
        let stalls = [
            "I have all the data needed.",
            "I have all the evidence needed!",
            "All required data is collected.",
        ]
        for text in stalls {
            XCTAssertEqual(
                AgentPromisedWorkGuard.correctionNeeded(
                    for: text,
                    tools: [.webFetch, .fileWrite, .fileRead]
                ),
                .promisedWork,
                "evidence readiness is not a completed deliverable: \(text)"
            )
        }
    }

    func testEvidenceReadyPhraseWithVerifiedDeliverableIsACompletion() {
        XCTAssertNil(AgentPromisedWorkGuard.correctionNeeded(
            for: "I have all the data needed. The final chart is saved and verified at outputs/revenue.html.",
            tools: [.fileWrite, .fileRead]
        ))
    }

    func testDetectsTerminalPresentProgressWorkNarration() {
        let stalls = [
            "I need to read the two source files before writing. Reading inputs/context.md and inputs/data.csv now.",
            "I'm running the tests now.",
            "I am writing the requested report right now.",
        ]
        for text in stalls {
            XCTAssertEqual(
                AgentPromisedWorkGuard.correctionNeeded(for: text, tools: [.fileRead, .fileWrite]),
                .promisedWork,
                "present-progress narration should re-drive: \(text)"
            )
        }
    }

    func testDetectsBareInProgressStatusAsUnfinishedWork() {
        let stalls = [
            "[Research in progress]",
            "Work in progress",
            "**Analysis in progress**",
            "Task in progress",
        ]
        for text in stalls {
            XCTAssertEqual(
                AgentPromisedWorkGuard.correctionNeeded(for: text, tools: [.webSearch, .fileWrite]),
                .promisedWork,
                "bare progress status should re-drive: \(text)"
            )
        }
    }

    func testDetectsDelegatedWorkerNextStepStalls() {
        let stalls = [
            "I found Q3 2024. Now I need Q2 2024 to complete the requested series.",
            "I could not extract a verified number. Next: re-fetch the investor filing.",
            "Three rows are verified; I still need to search for the fourth filing.",
            "COMPLETE: I need Q4 FY2026 revenue to finish the four-quarter set. Fetching Q4 report now.",
            "The IR page uses JavaScript. Fetching the Q2 2025 press release next for concrete revenue figures.",
            "The page does not yet verify the exact SKU. Let me continue researching.",
            "The listed model is not eligible. Continuing research.",
            "Starting research on MacBook Pro 14-inch M4 (32GB/1TB).",
            "The product page is truncated. Let me try the browser to access the full page directly.",
        ]
        for text in stalls {
            XCTAssertEqual(
                AgentPromisedWorkGuard.correctionNeeded(for: text, tools: [.webFetch, .webSearch]),
                .promisedWork,
                "unfinished delegated work should re-drive: \(text)"
            )
        }
    }

    func testCompletedDelegatedHandoffIsNotAStall() {
        XCTAssertNil(AgentPromisedWorkGuard.correctionNeeded(
            for: "All four quarters are verified. The remaining step is for the deliverable owner to merge these findings.",
            tools: [.webFetch, .fileWrite]
        ))
    }

    func testPresentProgressObservationIsNotAPromise() {
        XCTAssertNil(AgentPromisedWorkGuard.correctionNeeded(
            for: "Reading the report now shows three conversion gaps.",
            tools: [.fileRead]
        ))
    }

    func testCompletedResultReadyIsNotAReadinessStall() {
        // "X is ready" (a finished artifact) must NOT fire — only "ready to <proceed/begin/...>".
        let closers = [
            "The report is ready to send whenever you are.",
            "Your cleaned CSV is ready in output.csv.",
            "Done — the summary is ready."
        ]
        for text in closers {
            XCTAssertNil(
                AgentPromisedWorkGuard.correctionNeeded(for: text, tools: [.shellRun]),
                "a finished-artifact 'ready' must not re-drive: \(text)"
            )
        }
    }
}
