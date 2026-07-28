import XCTest

final class ParityPackagedMacOSSmokeGateTests: QuillCodeParityTestCase {
    func testPackagedMacOSSmokeIncludesLiveWindowProof() throws {
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let supportText = try Self.desktopSourceText(named: "QuillCodeDesktopSmokeSupport.swift")
        let windowSmokeText = try Self.desktopSourceText(named: "QuillCodeDesktopWindowSmokeRunner.swift")
        let packagedSmoke = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("scripts/packaged-macos-smoke.sh"),
            encoding: .utf8
        )
        let clickProbeValidator = try Self.nativeClickProbeValidatorText()

        XCTAssertTrue(appText.contains("QuillCodeDesktopWindowSmokeRequest(arguments: CommandLine.arguments)"))
        XCTAssertTrue(appText.contains("QuillCodeDesktopWindowSmokeWorkspaceRoot(request: windowRequest)"))
        XCTAssertTrue(appText.contains("QuillCodeDesktopWindowSmokeLaunch.schedule("))
        XCTAssertTrue(appText.contains("NSApplication.didFinishLaunchingNotification"))
        XCTAssertTrue(appText.contains("QuillCodeDesktopWindowSmokeRunner.runAndExit("))
        XCTAssertTrue(appText.contains(".defaultSize(width: 1280, height: 900)"))
        XCTAssertTrue(supportText.contains("struct QuillCodeDesktopWindowSmokeRequest"))
        XCTAssertTrue(supportText.contains("struct QuillCodeDesktopWindowSmokeReport"))
        XCTAssertTrue(supportText.contains("enum QuillCodeDesktopNativeHitTargetSmoke"))
        XCTAssertTrue(supportText.contains(#""nativeHitTargets": nativeHitTargets.dictionary"#))
        XCTAssertTrue(supportText.contains("struct QuillCodeDesktopWindowSmokeSurfaceReport"))
        XCTAssertTrue(supportText.contains("requiredCommandIDs"))
        XCTAssertTrue(supportText.contains("requiredStarterActionIDs"))
        XCTAssertTrue(supportText.contains(#""surface": surface.dictionary"#))
        XCTAssertTrue(windowSmokeText.contains("waitForWindow(controller: controller)"))
        XCTAssertTrue(windowSmokeText.contains("openSmokeWindow(controller: controller)"))
        XCTAssertTrue(windowSmokeText.contains("smokeController"))
        XCTAssertFalse(windowSmokeText.contains("QuillCodeDesktopController()"))
        XCTAssertTrue(windowSmokeText.contains("QuillCodeDesktopWindowSmokeSurfaceReport(surface: workspaceSurface)"))
        XCTAssertTrue(windowSmokeText.contains("NSHostingView(rootView: rootView)"))
        XCTAssertTrue(windowSmokeText.contains("QuillCodeDesktopRootView(controller: controller)"))
        XCTAssertTrue(windowSmokeText.contains("QuillCodeDesktopNativeHitTargetSmoke.validatedReport"))
        XCTAssertTrue(windowSmokeText.contains("bitmapImageRepForCachingDisplay"))
        XCTAssertTrue(windowSmokeText.contains("QuillCodeDesktopSmokePixelStats"))
        XCTAssertTrue(windowSmokeText.contains("window.title == \"QuillCode\""))
        XCTAssertTrue(packagedSmoke.contains("wait_for_smoke_process"))
        XCTAssertTrue(packagedSmoke.contains("--native-window-smoke"))
        XCTAssertTrue(packagedSmoke.contains("--window-smoke-report \"$WINDOW_REPORT_PATH\""))
        XCTAssertTrue(packagedSmoke.contains("--window-smoke-screenshot \"$WINDOW_SCREENSHOT_PATH\""))
        XCTAssertTrue(packagedSmoke.contains("--window-smoke-state-root \"$WINDOW_STATE_ROOT\""))
        XCTAssertFalse(packagedSmoke.contains("HOME=\"$SMOKE_ROOT/home\""))
        XCTAssertTrue(packagedSmoke.contains("window-report.json"))
        XCTAssertTrue(packagedSmoke.contains("window.png"))
        XCTAssertTrue(packagedSmoke.contains("packaged-accessibility-frames.json"))
        XCTAssertTrue(packagedSmoke.contains("accessibility_frames_manifest=packaged-accessibility-frames.json"))
        XCTAssertTrue(
            packagedSmoke.contains("SCHEDULED_COWORKER_MANIFEST=\"$SMOKE_ROOT/packaged-scheduled-coworker.json\"")
        )
        XCTAssertTrue(
            packagedSmoke.contains("MULTI_FILE_ARTIFACT_MANIFEST=\"$SMOKE_ROOT/packaged-multi-file-artifact.json\"")
        )
        XCTAssertTrue(
            packagedSmoke.contains("ONE_TURN_COWORKER_MANIFEST=\"$SMOKE_ROOT/packaged-one-turn-coworker.json\"")
        )
        XCTAssertTrue(
            packagedSmoke.contains("BROWSER_WORKFLOW_MANIFEST=\"$SMOKE_ROOT/packaged-browser-workflow.json\"")
        )
        XCTAssertTrue(packagedSmoke.contains("COMPUTER_USE_MANIFEST=\"$SMOKE_ROOT/packaged-computer-use.json\""))
        XCTAssertTrue(
            packagedSmoke.contains("COMPUTER_USE_ACTION_MANIFEST=\"$SMOKE_ROOT/packaged-computer-use-action.json\"")
        )
        XCTAssertTrue(packagedSmoke.contains("scheduled_coworker_manifest=packaged-scheduled-coworker.json"))
        XCTAssertTrue(packagedSmoke.contains("multi_file_artifact_manifest=packaged-multi-file-artifact.json"))
        XCTAssertTrue(packagedSmoke.contains("one_turn_coworker_manifest=packaged-one-turn-coworker.json"))
        XCTAssertTrue(packagedSmoke.contains("browser_workflow_manifest=packaged-browser-workflow.json"))
        XCTAssertTrue(packagedSmoke.contains("computer_use_manifest=packaged-computer-use.json"))
        XCTAssertTrue(packagedSmoke.contains("computer_use_action_manifest=packaged-computer-use-action.json"))
        XCTAssertTrue(packagedSmoke.contains(" scheduled-coworker \\"))
        XCTAssertTrue(packagedSmoke.contains(" multi-file-artifact \\"))
        XCTAssertTrue(packagedSmoke.contains(" one-turn-coworker \\"))
        XCTAssertTrue(packagedSmoke.contains(" browser-workflow \\"))
        XCTAssertTrue(packagedSmoke.contains(" computer-use \\"))
        XCTAssertTrue(packagedSmoke.contains(" computer-use-action \\"))
        XCTAssertTrue(packagedSmoke.contains(" frames \\"))
        XCTAssertTrue(packagedSmoke.contains("$WINDOW_REPORT_PATH"))
        XCTAssertTrue(packagedSmoke.contains("$WINDOW_SCREENSHOT_PATH"))
        XCTAssertTrue(packagedSmoke.contains("--click-probe-manifest \"$CLICK_PROBE_MANIFEST\""))
        XCTAssertTrue(packagedSmoke.contains("--manifest \"$ACCESSIBILITY_FRAMES_MANIFEST\""))
        Self.assertSource(packagedSmoke, excludes: "python3 - \"$WINDOW_REPORT_PATH\"")
        XCTAssertTrue(clickProbeValidator.contains(#"def validate_packaged_window_report"#))
        XCTAssertTrue(clickProbeValidator.contains(#"def write_accessibility_frames_manifest"#))
        XCTAssertTrue(clickProbeValidator.contains(#"write_scheduled_coworker_manifest"#))
        XCTAssertTrue(clickProbeValidator.contains(#"live-accessibility-frame-sampled"#))
        XCTAssertTrue(clickProbeValidator.contains(#"REQUIRED_LIVE_ACCESSIBILITY_CONTRACT_IDS"#))
        XCTAssertTrue(clickProbeValidator.contains(#"windowTitle") == "QuillCode""#))
        XCTAssertTrue(clickProbeValidator.contains(#"normalized_probe_contracts(report, "packaged live-window")"#))
        XCTAssertTrue(clickProbeValidator.contains(#"composerCanSend") is False"#))
        XCTAssertTrue(clickProbeValidator.contains(#"sidebarTitle") == "Chats""#))
        for commandID in ["new-chat", "command-palette", "keyboard-shortcuts", "settings", "toggle-terminal", "toggle-browser", "stop-all", "disconnect-all"] {
            Self.assertSource(clickProbeValidator, contains: commandID)
        }
        for commandID in [
            "computer-use-setup",
            "computer-use-open-screen-recording",
            "computer-use-open-accessibility",
            "computer-use-refresh",
        ] {
            Self.assertSource(supportText, contains: commandID)
            Self.assertSource(clickProbeValidator, contains: commandID)
        }
        for actionID in ["review-changes", "run-tests", "explain-project"] {
            Self.assertSource(clickProbeValidator, contains: actionID)
        }

        let scheduledCoworkerValidator = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("scripts/native_click_probe_contracts/scheduled_coworker.py"),
            encoding: .utf8
        )
        XCTAssertTrue(scheduledCoworkerValidator.contains(#""scheduledCoworkerSmoke""#))
        XCTAssertTrue(
            scheduledCoworkerValidator.contains(
                #""Scheduled task: check competitor pricing pages and notify me with a diff""#
            )
        )
        XCTAssertTrue(scheduledCoworkerValidator.contains(#""QuillCode scheduled task ready""#))
        XCTAssertTrue(scheduledCoworkerValidator.contains(#""Every Monday at 8:00 AM""#))
        XCTAssertTrue(scheduledCoworkerValidator.contains(#""scheduledCoworkerMatchesDirect": True"#))

        let multiFileArtifactValidator = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("scripts/native_click_probe_contracts/multi_file_artifact.py"),
            encoding: .utf8
        )
        XCTAssertTrue(multiFileArtifactValidator.contains(#""multiFileArtifactSmoke""#))
        XCTAssertTrue(
            multiFileArtifactValidator.contains(
                #""Create the team action brief from `notes/research.md` and `notes/risks.md`.""#
            )
        )
        XCTAssertTrue(multiFileArtifactValidator.contains(#""host.file.read", "host.file.read", "host.file.write""#))
        XCTAssertTrue(multiFileArtifactValidator.contains(#""team-action-brief.md""#))
        XCTAssertTrue(multiFileArtifactValidator.contains(#""multiFileArtifactMatchesDirect": True"#))

        XCTAssertTrue(supportText.contains("struct QuillCodeDesktopOneTurnCoworkerSmokeReport"))
        XCTAssertTrue(supportText.contains(#""oneTurnCoworkerSmoke": oneTurnCoworkerSmoke.dictionary"#))
        let oneTurnCoworkerValidator = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("scripts/native_click_probe_contracts/one_turn_coworker.py"),
            encoding: .utf8
        )
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""oneTurnCoworkerSmoke""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""packagedOneTurnCoworkerValidated": True"#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""catalogSpreadsheetURL": CATALOG_SPREADSHEET_URL"#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""catalogTaskIDs": direct_semantic["taskIDs"]"#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""oneTurnCoworkerMatchesDirect": True"#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""host.file.write""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""host.shell.run""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""launch-announcement.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""signup-slice.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""archive-readme.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""benefits-plan-matrix.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""marketing-budget-model.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""regional-revenue-chart.png""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""cohort-retention.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""collections-chase-emails.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""donors-split.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""support-replies/ticket-001.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""support-replies/ticket-002.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""newsletter-clean.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""newsletter-bad-rows.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""members-normalized.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""delay-notice.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""exhibits/Exhibit-A-Purchase-Agreement.pdf""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""exhibits/Exhibit-B-Disclosure-Schedule.pdf""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""amex_q3-categorized.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""amex_q3-review.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""june-variance-pack.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""downloads-organization-report.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""Downloads/Receipts/receipt-1042.pdf""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""prospect-followups/ada-day-1.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""prospect-followups/ada-day-3.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""prospect-followups/ben-day-1.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""forecast-review.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""pipeline-forecast.xlsx""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""q2-funnel-summary.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""q2-funnel-conversions.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""vendor-name-mapping.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""ap-vendors-standardized.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""senior-csm-job-description.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""senior-csm-screening-questions.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""sales-ops-analyst-scorecard.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""sales-ops-analyst-interview-questions.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""july-image-prep-report.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""Newsletter/July/ready/hero-launch.png""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""Newsletter/July/originals/IMG_0001.png""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""finance-kpi-dashboard.html""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""march-pricing-go-live-checklist.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""march-pricing-launch-brief.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""safety-guide-es.pdf""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""safety-guide-pt.pdf""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""q3-content-calendar.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""sales-pivot-summary.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""invoice-reconciliation.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""amendment-redline-impact.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""release-notes-2026-08.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""rfp-compliance-matrix.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""project-risk-register.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""roadmap.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""Q3-OKRs.docx""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""northwind-logistics-proposal.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""discovery-call-notes.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""pricing-sheet.xlsx""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""customer-leave-behind.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""product-deck-20-slides.pptx""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""approved-pricing.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""pension-vesting-retirement-table.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""pension-plan-1994-scanned.pdf""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""zendesk-theme-triage.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""zendesk-export.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""billing-support-macros.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""existing-macros.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""nps-plan-tier-summary.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""customer-survey-q2.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""nps-detractor-complaints.md""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""wbs.xlsx""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""team-roster.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""timeline.xlsx""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""milestones.csv""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""draft-price-increase-email-rewrite.docx""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""draft-price-increase-email.docx""#))
        XCTAssertTrue(oneTurnCoworkerValidator.contains(#""weekly-review.csv""#))

        let browserWorkflowValidator = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("scripts/native_click_probe_contracts/browser_workflow.py"),
            encoding: .utf8
        )
        XCTAssertTrue(browserWorkflowValidator.contains(#""browserWorkflowSmoke""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""browserSpreadsheetWorkflowSmoke""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""browserAuthenticatedWorkflowSmoke""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""host.browser.type""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""host.browser.click""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""host.browser.script""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""host.browser.inspect""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""Live DOM snapshot""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""H1: CRM Workflow Smoke""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""H1: Shared Sheet Workflow Smoke""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""H1: Signed-In Workspace Smoke""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""signed-in=true""#))
        XCTAssertTrue(browserWorkflowValidator.contains(#""browserWorkflowMatchesDirect": True"#))

        let computerUseValidator = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("scripts/native_click_probe_contracts/computer_use.py"),
            encoding: .utf8
        )
        XCTAssertTrue(computerUseValidator.contains(#""computer-use-setup""#))
        XCTAssertTrue(computerUseValidator.contains(#""computer-use-open-screen-recording""#))
        XCTAssertTrue(computerUseValidator.contains(#""computer-use-open-accessibility""#))
        XCTAssertTrue(computerUseValidator.contains(#""computer-use-refresh""#))
        XCTAssertTrue(computerUseValidator.contains(#""computerUseLabel""#))
        XCTAssertTrue(computerUseValidator.contains("write_computer_use_manifest"))

        XCTAssertTrue(supportText.contains("struct QuillCodeDesktopComputerUseActionSmokeReport"))
        XCTAssertTrue(supportText.contains(#""computerUseActionSmoke": computerUseActionSmoke.dictionary"#))
        let computerUseActionValidator = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("scripts/native_click_probe_contracts/computer_use_action.py"),
            encoding: .utf8
        )
        XCTAssertTrue(computerUseActionValidator.contains(#""host.computer.screenshot""#))
        XCTAssertTrue(computerUseActionValidator.contains(#""host.computer.click""#))
        XCTAssertTrue(computerUseActionValidator.contains(#""host.computer.type""#))
        XCTAssertTrue(computerUseActionValidator.contains(#""host.computer.scroll""#))
        XCTAssertTrue(computerUseActionValidator.contains(#""host.computer.move""#))
        XCTAssertTrue(computerUseActionValidator.contains(#""host.computer.key""#))
        XCTAssertTrue(computerUseActionValidator.contains(#""leftClick:42,84""#))
        XCTAssertTrue(computerUseActionValidator.contains(#""type:QuillCode smoke""#))
        XCTAssertTrue(computerUseActionValidator.contains(#""computerUseActionMatchesDirect": True"#))
    }

}
