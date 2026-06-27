import XCTest

final class ParityHTMLGateTests: QuillCodeParityTestCase {
    func testHTMLChromeRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let htmlChromeTests = try Self.appTestSourceText(named: "WorkspaceHTMLChromeRendererTests.swift")
        let chromeCases = [
            "testHTMLRendererEscapesAndLabelsPrimaryRegions",
            "testHTMLRendererTopBarOverflowUsesCommandAvailability",
            "testHTMLRendererShowsStopButtonDuringActiveSend",
            "testHTMLRendererUsesMultilineComposer",
            "testHTMLRendererIncludesContextBanner",
            "testHTMLRendererIncludesRuntimeIssue",
            "testHTMLRendererGroupsPinnedTodayAndArchivedChats"
        ]

        for testCase in chromeCases {
            XCTAssertTrue(
                htmlChromeTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLChromeRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

    func testHTMLToolCardRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let toolCardTests = try Self.appTestSourceText(named: "WorkspaceHTMLToolCardRendererTests.swift")
        let toolCardCases = [
            "testHTMLRendererIncludesToolCardOutput",
            "testHTMLToolCardRendererIncludesApprovalActions",
            "testHTMLRendererIncludesToolCardArtifacts",
            "testHTMLRendererIncludesImageArtifactPreview",
            "testHTMLRendererIncludesDocumentArtifactPreview",
            "testHTMLRendererIncludesAppshotArtifactPreview",
            "testHTMLRendererKeepsToolCardsInTranscriptOrder"
        ]

        for testCase in toolCardCases {
            XCTAssertTrue(
                toolCardTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLToolCardRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

    func testHTMLTerminalRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let terminalTests = try Self.appTestSourceText(named: "WorkspaceHTMLTerminalRendererTests.swift")
        let terminalCases = [
            "testHTMLRendererIncludesVisibleTerminalPane",
            "testHTMLRendererLabelsRunningAndStoppedTerminalEntries"
        ]

        for testCase in terminalCases {
            XCTAssertTrue(
                terminalTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLTerminalRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

    func testHTMLReviewRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let reviewTests = try Self.appTestSourceText(named: "WorkspaceHTMLReviewRendererTests.swift")
        let reviewCases = [
            "testHTMLRendererIncludesGitReviewPane"
        ]

        for testCase in reviewCases {
            XCTAssertTrue(
                reviewTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLReviewRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

    func testHTMLSecondaryPaneRendererCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let secondaryPaneTests = try Self.appTestSourceText(named: "WorkspaceHTMLSecondaryPaneRendererTests.swift")
        let secondaryPaneCases = [
            "testHTMLRendererIncludesVisibleExtensionsPane",
            "testHTMLRendererIncludesVisibleMemoriesPane"
        ]

        for testCase in secondaryPaneCases {
            XCTAssertTrue(
                secondaryPaneTests.contains("func \(testCase)"),
                "\(testCase) should live in WorkspaceHTMLSecondaryPaneRendererTests."
            )
            XCTAssertFalse(
                broadSurfaceTests.contains("func \(testCase)"),
                "\(testCase) should not drift back into the broad WorkspaceSurfaceTests file."
            )
        }
    }

    func testWorkspaceHTMLRendererDelegatesToolCardRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let toolCardText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")

        XCTAssertTrue(toolCardText.contains("enum WorkspaceHTMLToolCardRenderer"), "HTML tool-card rendering should live in a focused renderer.")
        XCTAssertTrue(toolCardText.contains("static func render(_ card: ToolCardState"), "HTML tool-card rendering should expose a directly testable entry point.")
        XCTAssertTrue(toolCardText.contains("private static func renderArtifacts"), "Artifact chip rendering should live beside tool-card HTML.")
        XCTAssertTrue(toolCardText.contains("private static func renderTextPreviews"), "Text-preview rendering should live beside tool-card HTML.")
        XCTAssertTrue(toolCardText.contains("private static func renderDocumentPreviews"), "Document-preview rendering should live beside tool-card HTML.")
        XCTAssertTrue(toolCardText.contains("private static func renderImagePreviews"), "Image-preview rendering should live beside tool-card HTML.")
        XCTAssertTrue(primitivesText.contains("enum WorkspaceHTMLPrimitives"), "Shared HTML primitives should live outside feature renderers.")
        XCTAssertTrue(primitivesText.contains("static func escape"), "HTML escaping should have one implementation.")
        XCTAssertTrue(primitivesText.contains("static func executionContextChip"), "Execution-context chip HTML should be shared by tool cards and terminal rows.")
        XCTAssertTrue(toolCardText.contains("WorkspaceHTMLPrimitives.executionContextChip"), "Tool-card rows should use shared execution-context chip HTML.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTranscriptRenderer.render"), "WorkspaceHTMLRenderer should delegate transcript rendering.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLToolCardRenderer.render"), "Transcript HTML should delegate tool-card rows to the focused renderer.")
        XCTAssertFalse(htmlText.contains("private static func renderToolCard"), "WorkspaceHTMLRenderer should not own tool-card rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderToolArtifacts"), "WorkspaceHTMLRenderer should not own artifact chip rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderToolTextPreviews"), "WorkspaceHTMLRenderer should not own text-preview rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderToolDocumentPreviews"), "WorkspaceHTMLRenderer should not own document-preview rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderToolImagePreviews"), "WorkspaceHTMLRenderer should not own image-preview rendering.")
        XCTAssertFalse(htmlText.contains("private static func documentIcon"), "WorkspaceHTMLRenderer should not own document-preview icon labels.")
    }

    func testWorkspaceHTMLRendererDelegatesTopBarRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let topBarText = try Self.appSourceText(named: "WorkspaceHTMLTopBarRenderer.swift")

        XCTAssertTrue(topBarText.contains("enum WorkspaceHTMLTopBarRenderer"), "HTML top-bar rendering should live in a focused renderer.")
        XCTAssertTrue(topBarText.contains("static func render(_ topBar: TopBarSurface"), "HTML top-bar rendering should expose a directly testable entry point.")
        XCTAssertFalse(topBarText.contains("renderPrimaryCluster"), "Send-time model/mode controls should not crowd top-bar HTML.")
        XCTAssertTrue(topBarText.contains("private static func renderStatusMetadata"), "Status semantics should stay available without visible top-bar chrome.")
        XCTAssertFalse(topBarText.contains("private static func renderStatusCluster"), "HTML top-bar should not reintroduce a visible status cluster.")
        XCTAssertTrue(topBarText.contains("private static func renderActionCluster"), "Overflow cluster rendering should live beside top-bar HTML.")
        XCTAssertTrue(topBarText.contains("private static func renderActivityHairline"), "Runtime and activity state should use quiet top-bar hairline rendering.")
        XCTAssertTrue(topBarText.contains("private static func renderRuntimeIssuePill"), "Runtime issue metadata rendering should live beside top-bar HTML.")
        XCTAssertTrue(topBarText.contains("TopBarOverflowCommandCatalog.commands"), "Top-bar overflow should use the shared command catalog.")
        XCTAssertTrue(topBarText.contains("WorkspaceHTMLPrimitives.escape"), "Top-bar renderer should reuse shared HTML escaping.")
        XCTAssertFalse(topBarText.contains("topbar-status-menu"), "HTML top-bar should not expose a status details menu in primary chrome.")
        XCTAssertFalse(topBarText.contains("top-bar-status-button"), "HTML top-bar should not expose a status button in primary chrome.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTopBarRenderer.render"), "WorkspaceHTMLRenderer should delegate top-bar rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTopBar"), "WorkspaceHTMLRenderer should not own top-bar rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTopBarOverflow"), "WorkspaceHTMLRenderer should not own top-bar overflow rendering.")
        XCTAssertFalse(htmlText.contains("topbar-primary-cluster"), "WorkspaceHTMLRenderer should not own top-bar cluster markup.")
        XCTAssertFalse(htmlText.contains("runtime-issue-pill"), "WorkspaceHTMLRenderer should not own runtime issue pill markup.")
        XCTAssertFalse(htmlText.contains("top-bar-overflow-popover"), "WorkspaceHTMLRenderer should not own top-bar overflow markup.")
    }

    func testWorkspaceHTMLRendererDelegatesTerminalRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let terminalText = try Self.appSourceText(named: "WorkspaceHTMLTerminalRenderer.swift")

        XCTAssertTrue(terminalText.contains("enum WorkspaceHTMLTerminalRenderer"), "HTML terminal rendering should live in a focused renderer.")
        XCTAssertTrue(terminalText.contains("static func render(_ terminal: TerminalSurface"), "HTML terminal rendering should expose a directly testable entry point.")
        XCTAssertTrue(terminalText.contains("private static func renderEntry"), "Terminal entry rendering should live beside terminal pane HTML.")
        XCTAssertTrue(terminalText.contains("private static func statusClass"), "Terminal status classes should live beside terminal pane HTML.")
        XCTAssertTrue(terminalText.contains("WorkspaceHTMLPrimitives.executionContextChip"), "Terminal rows should use shared execution-context chip HTML.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTerminalRenderer.render"), "WorkspaceHTMLRenderer should delegate terminal rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTerminal"), "WorkspaceHTMLRenderer should not own terminal pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func terminalStatusClass"), "WorkspaceHTMLRenderer should not own terminal status class mapping.")
    }

    func testWorkspaceHTMLRendererDelegatesSecondaryPaneRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let secondaryText = try Self.appSourceText(named: "WorkspaceHTMLSecondaryPaneRenderer.swift")

        XCTAssertTrue(secondaryText.contains("enum WorkspaceHTMLSecondaryPaneRenderer"), "HTML secondary panes should live in a focused renderer.")
        XCTAssertTrue(secondaryText.contains("static func renderExtensions"), "Extensions HTML should expose a directly testable entry point.")
        XCTAssertTrue(secondaryText.contains("static func renderMemories"), "Memories HTML should expose a directly testable entry point.")
        XCTAssertTrue(secondaryText.contains("static func renderActivity"), "Activity HTML should expose a directly testable entry point.")
        XCTAssertTrue(secondaryText.contains("static func renderAutomations"), "Automation HTML should expose a directly testable entry point.")
        XCTAssertTrue(secondaryText.contains("private static func renderMCPTools"), "MCP tool chips should live beside Extensions HTML.")
        XCTAssertTrue(secondaryText.contains("private static func renderAutomationActions"), "Automation actions should live beside Automations HTML.")
        XCTAssertTrue(secondaryText.contains("WorkspaceHTMLPrimitives.escape"), "Secondary pane renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSecondaryPaneRenderer.renderExtensions"), "WorkspaceHTMLRenderer should delegate Extensions rendering.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSecondaryPaneRenderer.renderMemories"), "WorkspaceHTMLRenderer should delegate Memories rendering.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSecondaryPaneRenderer.renderActivity"), "WorkspaceHTMLRenderer should delegate Activity rendering.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSecondaryPaneRenderer.renderAutomations"), "WorkspaceHTMLRenderer should delegate Automation rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderExtensions"), "WorkspaceHTMLRenderer should not own Extensions pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderMemories"), "WorkspaceHTMLRenderer should not own Memories pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderActivity"), "WorkspaceHTMLRenderer should not own Activity pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderAutomations"), "WorkspaceHTMLRenderer should not own Automations pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func countLabel"), "WorkspaceHTMLRenderer should not own secondary-pane count labels.")
        XCTAssertFalse(htmlText.contains("extension-mcp-tool-schema"), "WorkspaceHTMLRenderer should not own MCP extension details markup.")
    }

    func testWorkspaceHTMLRendererDelegatesReviewRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let reviewText = try Self.appSourceText(named: "WorkspaceHTMLReviewRenderer.swift")

        XCTAssertTrue(reviewText.contains("enum WorkspaceHTMLReviewRenderer"), "HTML review rendering should live in a focused renderer.")
        XCTAssertTrue(reviewText.contains("static func render(_ review: WorkspaceReviewSurface"), "HTML review rendering should expose a directly testable entry point.")
        XCTAssertTrue(reviewText.contains("private static func renderFile"), "Review file rendering should live beside review pane HTML.")
        XCTAssertTrue(reviewText.contains("private static func renderHunk"), "Review hunk rendering should live beside review pane HTML.")
        XCTAssertTrue(reviewText.contains("private static func renderLine"), "Review line rendering should live beside review pane HTML.")
        XCTAssertTrue(reviewText.contains("private static func renderAction"), "Review action rendering should live beside review pane HTML.")
        XCTAssertTrue(reviewText.contains("WorkspaceHTMLPrimitives.escape"), "Review renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTranscriptRenderer.render"), "WorkspaceHTMLRenderer should delegate transcript rendering.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLReviewRenderer.render"), "Transcript HTML should delegate review panes to the focused renderer.")
        XCTAssertFalse(htmlText.contains("private static func renderReview"), "WorkspaceHTMLRenderer should not own review pane rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderReviewHunk"), "WorkspaceHTMLRenderer should not own review hunk rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderReviewLine"), "WorkspaceHTMLRenderer should not own review line rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderReviewAction"), "WorkspaceHTMLRenderer should not own review action rendering.")
        XCTAssertFalse(htmlText.contains("review-hunk-header"), "WorkspaceHTMLRenderer should not own review hunk markup.")
        XCTAssertFalse(htmlText.contains("review-line-marker"), "WorkspaceHTMLRenderer should not own review line markup.")
    }

    func testWorkspaceHTMLRendererDelegatesTranscriptRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")

        XCTAssertTrue(transcriptText.contains("enum WorkspaceHTMLTranscriptRenderer"), "HTML transcript rendering should live in a focused renderer.")
        XCTAssertTrue(transcriptText.contains("static func render("), "HTML transcript rendering should expose a directly testable entry point.")
        XCTAssertTrue(transcriptText.contains("static func renderComposer"), "HTML composer rendering should live beside transcript HTML.")
        XCTAssertTrue(transcriptText.contains("private static func renderRuntimeIssue"), "Runtime issue panel HTML should live beside transcript HTML.")
        XCTAssertTrue(transcriptText.contains("private static func renderTimelineItem"), "Timeline item HTML should live beside transcript HTML.")
        XCTAssertTrue(transcriptText.contains("private static func renderContextBanner"), "Context banner HTML should live beside transcript HTML.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLToolCardRenderer.render"), "Transcript HTML should delegate tool-card rows to the tool-card renderer.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLReviewRenderer.render"), "Transcript HTML should delegate review panes to the review renderer.")
        XCTAssertTrue(transcriptText.contains("WorkspaceHTMLPrimitives.escape"), "Transcript renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTranscriptRenderer.render"), "WorkspaceHTMLRenderer should delegate transcript rendering.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLTranscriptRenderer.renderComposer"), "WorkspaceHTMLRenderer should delegate composer rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTranscript"), "WorkspaceHTMLRenderer should not own transcript rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderRuntimeIssue"), "WorkspaceHTMLRenderer should not own runtime issue panel rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderTimelineItem"), "WorkspaceHTMLRenderer should not own timeline item rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderMessageFeedbackActions"), "WorkspaceHTMLRenderer should not own message feedback markup.")
        XCTAssertFalse(htmlText.contains("private static func renderContextBanner"), "WorkspaceHTMLRenderer should not own context banner rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderComposer"), "WorkspaceHTMLRenderer should not own composer rendering.")
        XCTAssertFalse(htmlText.contains(#"data-testid="message-feedback-up""#), "WorkspaceHTMLRenderer should not own message action markup.")
        XCTAssertFalse(htmlText.contains(#"data-testid="runtime-issue""#), "WorkspaceHTMLRenderer should not own runtime issue markup.")
        XCTAssertFalse(htmlText.contains(#"data-testid="context-banner""#), "WorkspaceHTMLRenderer should not own context banner markup.")
    }

    func testWorkspaceHTMLRendererDelegatesSidebarRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let sidebarText = try Self.appSourceText(named: "WorkspaceHTMLSidebarRenderer.swift")

        XCTAssertTrue(sidebarText.contains("enum WorkspaceHTMLSidebarRenderer"), "HTML sidebar rendering should live in a focused renderer.")
        XCTAssertTrue(sidebarText.contains("static func render("), "HTML sidebar rendering should expose a directly testable entry point.")
        XCTAssertTrue(sidebarText.contains("private static func renderProjects"), "Project-list rendering should live beside sidebar HTML.")
        XCTAssertTrue(sidebarText.contains("private static func renderThreadSections"), "Thread-section rendering should live beside sidebar HTML.")
        XCTAssertTrue(sidebarText.contains("private static func renderBulkToolbar"), "Bulk-selection rendering should live beside sidebar HTML.")
        XCTAssertTrue(sidebarText.contains("private static func renderFooter"), "Sidebar tool footer rendering should live beside sidebar HTML.")
        XCTAssertTrue(sidebarText.contains("private static func renderUtilityAction"), "Individual utility command HTML should live beside grouped sidebar rendering.")
        XCTAssertTrue(sidebarText.contains("WorkspaceHTMLPrimitives.escape"), "Sidebar renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLSidebarRenderer.render"), "WorkspaceHTMLRenderer should delegate sidebar rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderSidebar"), "WorkspaceHTMLRenderer should not own sidebar rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderSidebarPrimaryActions"), "WorkspaceHTMLRenderer should not own sidebar primary action rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderSidebarSection"), "WorkspaceHTMLRenderer should not own sidebar section rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderSidebarBulkToolbar"), "WorkspaceHTMLRenderer should not own sidebar bulk toolbar rendering.")
        XCTAssertFalse(htmlText.contains("sidebar-tools-popover"), "WorkspaceHTMLRenderer should not own sidebar footer markup.")
        XCTAssertFalse(htmlText.contains("project-empty"), "WorkspaceHTMLRenderer should not own project empty-state markup.")
    }

    func testHTMLInteractiveControlsKeepExplicitHitTargets() throws {
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")
        let toolCardText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let reviewText = try Self.appSourceText(named: "WorkspaceHTMLReviewRenderer.swift")
        let secondaryText = try Self.appSourceText(named: "WorkspaceHTMLSecondaryPaneRenderer.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(
            primitivesText.contains("static let interactiveHitTargetClass"),
            "HTML renderers should share one semantic class for non-button clickable targets."
        )
        XCTAssertTrue(
            primitivesText.contains("static let iconHitTargetClass")
                && primitivesText.contains("static let textHitTargetClass")
                && primitivesText.contains("static let rowHitTargetClass")
                && primitivesText.contains("static let capsuleHitTargetClass")
                && primitivesText.contains("static let formActionHitTargetClass"),
            "HTML hit-target classes should name the same semantic control categories as the SwiftUI target specs."
        )
        XCTAssertTrue(
            toolCardText.contains(#"class="tool-details""#),
            "Tool-card details disclosures should opt into the harness hit-target styling."
        )
        XCTAssertTrue(
            toolCardText.contains(#"artifact-chip \(WorkspaceHTMLPrimitives.interactiveHitTargetClass)"#),
            "Artifact links should keep an explicit 44 px hit target instead of relying on chip padding."
        )
        XCTAssertTrue(
            reviewText.contains(#"class="review-action-button \(WorkspaceHTMLPrimitives.textHitTargetClass)""#),
            "Review action buttons should use a named class that can be target-sized in CSS."
        )
        XCTAssertTrue(
            reviewText.contains(#"data-testid="pr-review-thread-reply-form""#)
                && reviewText.contains(#"WorkspaceHTMLPrimitives.formActionHitTargetClass"#),
            "Pull request review-thread reply forms should expose explicit form-action targets."
        )
        XCTAssertTrue(
            secondaryText.contains(#"class="extension-action-button""#),
            "Extension action buttons should use a named class that can be target-sized in CSS."
        )
        XCTAssertTrue(
            secondaryText.contains(#"class="memory-edit-button""#),
            "Memory edit buttons should keep the shared memory action class."
        )
        XCTAssertTrue(
            harnessText.contains(".interactive-hit-target"),
            "The Playwright harness should size semantic non-button click targets explicitly."
        )
        XCTAssertTrue(
            harnessText.contains("button,\n    summary,\n    input,\n    select,\n    textarea,\n    a.interactive-hit-target"),
            "The Playwright harness should enforce a global 44 px baseline for buttons, summaries, fields, and link-style controls."
        )
        XCTAssertTrue(
            harnessText.contains(".hit-target-icon")
                && harnessText.contains(".hit-target-form-action"),
            "The Playwright harness should expose semantic target classes for icon and compact form controls."
        )
        XCTAssertTrue(
            harnessText.contains("button:active:not(:disabled)")
                && harnessText.contains("transform: scale(.96)"),
            "The Playwright harness should keep consistent 0.96 press feedback on clickable controls."
        )
        XCTAssertTrue(
            harnessText.contains("details > summary"),
            "Disclosure summaries should keep a minimum click target in the harness."
        )
        XCTAssertTrue(
            harnessText.contains(".activity-section button")
                && harnessText.contains("min-height: var(--hit-target);"),
            "Activity disclosure rows should keep full-row 44 px click targets in the harness."
        )
        XCTAssertTrue(
            harnessText.contains(".memory-edit-button,\n    .memory-delete-button")
                && harnessText.contains("min-width: var(--hit-target);"),
            "Memory edit/delete controls should keep explicit 44 px icon targets in the harness."
        )
        XCTAssertTrue(
            harnessText.contains(".extension-card button")
                && harnessText.contains("min-width: 72px;"),
            "Extension action controls should keep explicit text-button targets in the harness."
        )
        XCTAssertTrue(
            harnessText.contains(#"class="artifact-chip interactive-hit-target""#),
            "Harness artifact links should match the production target class."
        )
        XCTAssertTrue(
            harnessText.contains(#"class="review-action-button hit-target-text""#),
            "Harness review buttons should match the production review action target class."
        )
        XCTAssertTrue(
            harnessText.contains(#"class="pr-review-thread-reply-form""#)
                && harnessText.contains(#"data-testid="pr-review-thread-reply-submit""#),
            "Harness PR review-thread replies should exercise the same expanded form targets as production."
        )
    }

    func testHTMLArchitectureGatesStayOutOfBroadSuite() throws {
        let broadSuiteText = try Self.parityTestSourceText(named: "ParityGateTests.swift")
        let htmlGateNames = [
            "testWorkspaceHTMLRendererDelegatesToolCardRendering",
            "testWorkspaceHTMLRendererDelegatesTopBarRendering",
            "testWorkspaceHTMLRendererDelegatesTerminalRendering",
            "testWorkspaceHTMLRendererDelegatesSecondaryPaneRendering",
            "testWorkspaceHTMLRendererDelegatesReviewRendering",
            "testWorkspaceHTMLRendererDelegatesTranscriptRendering",
            "testWorkspaceHTMLRendererDelegatesSidebarRendering"
        ]

        for testName in htmlGateNames {
            XCTAssertFalse(
                broadSuiteText.contains("func \(testName)"),
                "\(testName) should stay in ParityHTMLGateTests."
            )
        }
    }
}
