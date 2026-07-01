import XCTest

final class ParityHTMLInteractionPrimitiveGateTests: QuillCodeParityTestCase {
    func testHTMLInteractiveControlsKeepExplicitHitTargets() throws {
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")
        let browserText = try Self.appSourceText(named: "WorkspaceHTMLBrowserRenderer.swift")
        let toolCardText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let reviewText = try Self.appSourceText(named: "WorkspaceHTMLReviewRenderer.swift")
        let secondaryText = try Self.appSourceText(named: "WorkspaceHTMLSecondaryPaneRenderer.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
        let interactionAuditHelperText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/playwright/tests/interaction-audit-helpers.ts"),
            encoding: .utf8
        )

        XCTAssertTrue(
            primitivesText.contains("enum WorkspaceHTMLHitTargetKind: String, CaseIterable")
                && primitivesText.contains("case link")
                && primitivesText.contains("case formAction = \"form-action\"")
                && primitivesText.contains("case adjustable = \"adjustable\""),
            "HTML renderers should choose typed semantic target kinds before those kinds are mapped to CSS classes."
        )
        XCTAssertTrue(
            primitivesText.contains("static func commandButton(")
                && primitivesText.contains("static func buttonAttributes(")
                && primitivesText.contains(#"attributes: [("data-command-id", commandID)] + attributes"#),
            "HTML command buttons should be emitted through one primitive that owns command routing, disabled semantics, and target classes."
        )
        XCTAssertTrue(
            primitivesText.contains("static func hitTargetAttributes(kind: WorkspaceHTMLHitTargetKind")
                && primitivesText.contains("classesWithDefaultHitTarget(classes, defaultKind: kind)"),
            "HTML hit-target attributes should derive classes and data-hit-target-kind from typed semantic target kinds."
        )
        XCTAssertTrue(
            toolCardText.contains(#"class="tool-details""#),
            "Tool-card details disclosures should opt into the harness hit-target styling."
        )
        XCTAssertTrue(
            toolCardText.contains(#"WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .link, classes: ["artifact-chip"])"#),
            "Artifact links should keep an explicit 44 px hit target instead of relying on chip padding."
        )
        XCTAssertTrue(
            reviewText.contains(#"WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .text, classes: ["review-action-button"])"#),
            "Review action buttons should declare text-button hit-target semantics through the shared primitive."
        )
        XCTAssertTrue(
            reviewText.contains(#"data-testid="pr-review-thread-reply-form""#)
                && reviewText.contains(#"WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .formAction, classes: ["review-action-button"])"#),
            "Pull request review-thread reply forms should expose explicit form-action targets."
        )
        XCTAssertTrue(
            secondaryText.contains("extensionActionButton(")
                && secondaryText.contains("extension-action-button")
                && secondaryText.contains("hitTargetKind: .formAction"),
            "Extension action buttons should use the shared command primitive plus named form-action hit-target semantics."
        )
        XCTAssertTrue(
            secondaryText.contains("extensionActionButton(\"Install\"")
                && secondaryText.contains("extensionActionButton(\"Start\"")
                && secondaryText.contains("extension-reference-action")
                && secondaryText.contains("hitTargetKind: .capsule"),
            "Extension and MCP reference buttons should use the shared command primitive consumed by click routing."
        )
        XCTAssertFalse(
            secondaryText.contains(#"data-command=""#),
            "Secondary-pane HTML should not emit data-command; command buttons must use the shared data-command-id contract."
        )
        XCTAssertTrue(
            secondaryText.contains("memory-edit-button")
                && secondaryText.contains("memory-delete-button")
                && secondaryText.contains("hitTargetKind: .formAction"),
            "Memory edit/delete buttons should keep shared memory action classes and compact form-action semantics."
        )
        XCTAssertTrue(
            browserText.contains(#"class="browser-form""#)
                && browserText.contains(#"class="browser-nav-controls""#)
                && browserText.contains("browserNavButton(")
                && browserText.contains("WorkspaceHTMLPrimitives.button(")
                && browserText.contains("hitTargetKind: .capsule")
                && browserText.contains("hitTargetKind: .icon")
                && browserText.contains(#""browser-nav-button""#)
                && browserText.contains(#""browser-open-button""#)
                && browserText.contains(#"data-testid="browser-address""#),
            "Browser controls should keep named classes and address test IDs so compact hit-target CSS and audits cannot silently regress."
        )
        XCTAssertTrue(
            harnessText.contains(".hit-target-link"),
            "The Playwright harness should size semantic non-button click targets explicitly."
        )
        XCTAssertTrue(
            harnessText.contains("button,\n    summary,\n    input,\n    select,\n    textarea,\n    a.hit-target-link"),
            "The Playwright harness should enforce a global 44 px baseline for buttons, summaries, fields, and link-style controls."
        )
        XCTAssertTrue(
            interactionAuditHelperText.contains("function visibleRect(element: Element, rect: DOMRect)")
                && interactionAuditHelperText.contains("scrollClipped")
                && interactionAuditHelperText.contains("hardClipped")
                && interactionAuditHelperText.contains("isScrollBoundarySliver")
                && interactionAuditHelperText.contains("visible_area_too_small_or_clipped"),
            "The Playwright harness should audit the visible actionable target after viewport and clipping ancestors, not only raw DOM bounds."
        )
        XCTAssertTrue(
            harnessText.contains(".hit-target-icon")
                && harnessText.contains(".hit-target-form-action")
                && harnessText.contains(".hit-target-adjustable"),
            "The Playwright harness should expose semantic target classes for icon, compact form, and adjustable controls."
        )
        XCTAssertTrue(
            harnessText.contains("button:active:not(:disabled)")
                && harnessText.contains(#"[data-hit-target-action="press"]:active"#)
                && harnessText.contains(#"[data-hit-target-action="owned-gesture"]:active"#)
                && harnessText.contains("transform: scale(.96)"),
            "The Playwright harness should keep consistent 0.96 press feedback on semantic clickable controls, including non-button owned targets."
        )
        XCTAssertTrue(
            harnessText.contains(#"[data-hit-target-action="press"],"#)
                && harnessText.contains(#"[data-hit-target-action="adjust"]"#)
                && harnessText.contains("-webkit-tap-highlight-color: transparent")
                && harnessText.contains("user-select: none")
                && harnessText.contains("transition-property: transform, background-color, border-color, box-shadow, color, opacity"),
            "The Playwright harness should attach tactile behavior to semantic hit-target actions, not only to native button elements."
        )
        XCTAssertFalse(
            harnessText.contains("scale(.97)") || harnessText.contains("scale(0.97)"),
            "Press feedback should use the shared 0.96 scale everywhere instead of local one-off values."
        )
        XCTAssertEqual(
            harnessText.components(separatedBy: "@media (prefers-reduced-motion: reduce)").count - 1,
            1,
            "The Playwright harness should keep one shared reduced-motion override instead of screen-local partial rules."
        )
        XCTAssertTrue(
            harnessText.contains(".thinking-dot {\n        animation: none !important;")
                && harnessText.contains("summary:active")
                && harnessText.contains(".empty-starter:active")
                && harnessText.contains("transition-duration: 1ms !important;")
                && harnessText.contains("transform: none !important;"),
            "The reduced-motion override should cover animated thinking indicators and shared press-feedback controls."
        )
        XCTAssertTrue(
            harnessText.contains("summary:focus-visible")
                && harnessText.contains("a.hit-target-link:focus-visible")
                && harnessText.contains(#"[role="option"]:focus-visible"#)
                && harnessText.contains(".hit-target-form-action:focus-visible")
                && harnessText.contains(".hit-target-adjustable:focus-visible"),
            "The Playwright harness should give non-button semantic targets the same visible keyboard focus treatment as buttons and fields."
        )
        XCTAssertTrue(
            harnessText.contains("details > summary"),
            "Disclosure summaries should keep a minimum click target in the harness."
        )
        XCTAssertTrue(
            harnessText.contains(#".activity-section [data-testid="activity-section-toggle"]"#)
                && harnessText.contains("min-height: var(--hit-target);"),
            "Activity disclosure rows should keep full-row 44 px click targets in the harness."
        )
        XCTAssertTrue(
            harnessText.contains(".activity-source-action")
                && harnessText.contains("flex: 0 0 auto;")
                && harnessText.contains("width: auto;")
                && harnessText.contains("min-width: var(--hit-target);"),
            "Activity source actions should keep compact explicit 44 px targets instead of inheriting full-width row styling."
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
            harnessText.contains(".browser-nav-button")
                && harnessText.contains(".browser-open-button")
                && harnessText.contains("@media (max-width: 760px)")
                && harnessText.contains("grid-template-columns: repeat(3, var(--hit-target)) minmax(72px, 1fr);"),
            "Browser nav controls should have explicit compact target CSS instead of relying on cramped grid auto sizing."
        )
        XCTAssertTrue(
            harnessText.contains(#"class="browser-tab hit-target-capsule"#)
                && harnessText.contains(#"class="browser-tab-action hit-target-icon"#),
            "Harness browser tab controls should use the same semantic hit-target classes as production HTML."
        )
        XCTAssertTrue(
            harnessText.contains(#"class="artifact-chip hit-target-link""#),
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

    func testHTMLInteractiveLinksUseSharedHitTargetPrimitive() throws {
        let rendererNames = [
            "WorkspaceHTMLBrowserRenderer.swift",
            "WorkspaceHTMLReviewRenderer.swift",
            "WorkspaceHTMLSecondaryPaneRenderer.swift",
            "WorkspaceHTMLSidebarCommandRenderer.swift",
            "WorkspaceHTMLSidebarProjectRenderer.swift",
            "WorkspaceHTMLSidebarRenderer.swift",
            "WorkspaceHTMLSidebarSavedSearchRenderer.swift",
            "WorkspaceHTMLSidebarThreadRenderer.swift",
            "WorkspaceHTMLTerminalRenderer.swift",
            "WorkspaceHTMLToolCardRenderer.swift",
            "WorkspaceHTMLTopBarRenderer.swift",
            "WorkspaceHTMLTranscriptRenderer.swift"
        ]

        for rendererName in rendererNames {
            let source = try Self.appSourceText(named: rendererName)
            let linkLines = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { $0.contains("<a ") }

            for line in linkLines {
                XCTAssertTrue(
                    line.contains("WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .link"),
                    "\(rendererName) should render link targets through WorkspaceHTMLPrimitives link semantics: \(line)"
                )
            }
        }
    }

    func testHTMLCommandButtonsUseSharedPrimitive() throws {
        let rendererNames = [
            "WorkspaceHTMLBrowserRenderer.swift",
            "WorkspaceHTMLReviewRenderer.swift",
            "WorkspaceHTMLSecondaryPaneRenderer.swift",
            "WorkspaceHTMLSidebarCommandRenderer.swift",
            "WorkspaceHTMLSidebarProjectRenderer.swift",
            "WorkspaceHTMLSidebarRenderer.swift",
            "WorkspaceHTMLSidebarSavedSearchRenderer.swift",
            "WorkspaceHTMLSidebarThreadRenderer.swift",
            "WorkspaceHTMLTerminalRenderer.swift",
            "WorkspaceHTMLToolCardRenderer.swift",
            "WorkspaceHTMLTopBarRenderer.swift",
            "WorkspaceHTMLTranscriptRenderer.swift"
        ]

        for rendererName in rendererNames {
            let source = try Self.appSourceText(named: rendererName)
            let rawCommandLines = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { ($0.offset + 1, String($0.element)) }
                .filter { _, line in line.contains("data-command-id") }

            for (lineNumber, line) in rawCommandLines {
                let isStructuredNestedButton = rendererName == "WorkspaceHTMLBrowserRenderer.swift"
                    && line.contains(#"("data-command-id", tab.selectCommandID)"#)
                    || rendererName == "WorkspaceHTMLSecondaryPaneRenderer.swift"
                    && line.contains(#"("data-command-id", section.toggleCommandID)"#)
                XCTAssertTrue(
                    isStructuredNestedButton,
                    "\(rendererName):\(lineNumber) should route command buttons through WorkspaceHTMLPrimitives.commandButton unless nested visible markup requires buttonAttributes: \(line)"
                )
            }
        }
    }

}
