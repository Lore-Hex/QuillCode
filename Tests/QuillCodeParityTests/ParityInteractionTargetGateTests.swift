import XCTest

final class ParityInteractionTargetGateTests: QuillCodeParityTestCase {
    func testHTMLInteractionAuditRequiresNamedClickableTargets() throws {
        let auditHelperText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/playwright/tests/interaction-audit-helpers.ts"),
            encoding: .utf8
        )

        XCTAssertTrue(
            auditHelperText.contains("accessibleName(element)")
                && auditHelperText.contains("missing_accessible_name"),
            "The rendered click-target audit should fail visible interactive elements that have no user-facing name."
        )
        XCTAssertTrue(
            auditHelperText.contains("button")
                && auditHelperText.contains("[role=\"button\"]")
                && auditHelperText.contains("[role=\"tab\"]")
                && auditHelperText.contains("label")
                && auditHelperText.contains("range")
                && auditHelperText.contains("textarea"),
            "The rendered click-target audit should cover native controls, ARIA controls, tabs, interactive labels, and text entry."
        )
        XCTAssertTrue(
            auditHelperText.contains("MINIMUM_HIT_TARGET = 44")
                && auditHelperText.contains("expectHitTarget(locator: Locator"),
            "The rendered click-target audit should keep the same 44 px minimum for whole-screen audits and explicit critical-control probes."
        )
        XCTAssertTrue(
            auditHelperText.contains("MINIMUM_TARGET_CLEARANCE = 8")
                && auditHelperText.contains("clearanceIssues")
                && auditHelperText.contains("expectNoAmbiguousAdjacentInteractiveTargets")
                && auditHelperText.contains("allowsTightClearance")
                && auditHelperText.contains(#"[data-testid="sidebar-compose-zone"]"#),
            "The rendered click-target audit should reject peer controls that are nearly touching, while allowing intentional menu/list rows and segmented controls."
        )
        XCTAssertTrue(
            auditHelperText.contains("export type CriticalTargetProbe")
                && auditHelperText.contains("expectedKind?: string")
                && auditHelperText.contains("expectCriticalTargetRegistry"),
            "High-risk click targets should be declared through a named registry with expected semantic target kinds instead of scattered one-off assertions."
        )
        XCTAssertTrue(
            auditHelperText.contains("export type CriticalTargetSurface")
                && auditHelperText.contains("requiredKinds: string[]")
                && auditHelperText.contains("expectCriticalTargetSurfaceRegistry")
                && auditHelperText.contains("should declare semantic click-target intent"),
            "Critical click-target probes should be grouped by interaction surface and should fail when a probe only checks geometry without semantic target intent."
        )
        XCTAssertTrue(
            auditHelperText.contains("target.evaluate")
                && auditHelperText.contains("elementFromPoint")
                && auditHelperText.contains("clickableInteriorIssues"),
            "Explicit critical-control probes should test the clickable interior, not only raw bounding-box dimensions."
        )
        XCTAssertTrue(
            auditHelperText.contains("TARGET_INTERIOR_SAMPLE_FRACTIONS = [0.2, 0.5, 0.8]")
                && auditHelperText.contains("TARGET_EDGE_SAMPLE_FRACTIONS = [0.08, 0.92]")
                && auditHelperText.contains("targetInteriorSamplePoints"),
            "Click-target probes should sample near-edge and interior points so controls cannot pass with only the center or middle band clickable."
        )
        XCTAssertTrue(
            auditHelperText.contains("pointer_events_none")
                && auditHelperText.contains("isSemanticallyDisabled"),
            "Visible interactive controls with pointer-events disabled should fail unless they are semantically disabled."
        )
        XCTAssertTrue(
            auditHelperText.contains("missing_click_affordance")
                && auditHelperText.contains("requiresPointerAffordance"),
            "Visible clickable controls should expose a pointer affordance, not only a large invisible hit box."
        )
        XCTAssertTrue(
            auditHelperText.contains("requiresTactileFeedbackContract")
                && auditHelperText.contains("missing_touch_action_manipulation")
                && auditHelperText.contains("click_target_allows_text_selection")
                && auditHelperText.contains("missing_press_feedback_transition"),
            "Visible clickable controls should inherit the shared tactile contract: no text selection, touch-action manipulation, and transform-based press feedback."
        )
        XCTAssertTrue(
            auditHelperText.contains("missing_shared_hit_target_contract")
                && auditHelperText.contains("SHARED_HIT_TARGET_CLASSES")
                && auditHelperText.contains("EXPECTED_KIND_BY_CLASS")
                && auditHelperText.contains("'hit-target-adjustable': 'adjustable'"),
            "Visible interactive controls should declare ownership through a shared hit-target class and semantic kind, not only rely on global geometry."
        )
        XCTAssertTrue(
            auditHelperText.contains("EXPECTED_ACTION_BY_KIND")
                && auditHelperText.contains("missing_hit_target_action")
                && auditHelperText.contains("hit_target_kind_class_mismatch")
                && auditHelperText.contains("hit_target_action_mismatch")
                && auditHelperText.contains("element_action_mismatch")
                && auditHelperText.contains("expectedElementAction(element)")
                && auditHelperText.contains("data-hit-target-source")
                && auditHelperText.contains("data-hit-target-action"),
            "Visible interactive controls should declare a coherent semantic kind/action/source and match their underlying element role; size alone must not pass a target."
        )
        XCTAssertTrue(
            auditHelperText.contains("closestInteractiveAncestor")
                && auditHelperText.contains("nestedIssues")
                && auditHelperText.contains("expectNoNestedInteractiveTargets"),
            "The rendered click-target audit should fail nested interactive controls, not only undersized controls."
        )
        XCTAssertTrue(
            auditHelperText.contains("isAuditableInteractiveElement")
                && auditHelperText.contains("HTMLLabelElement")
                && auditHelperText.contains("associatedLabelControl"),
            "Interactive labels should be audited when they act as checkbox/radio click targets without treating passive form captions as buttons."
        )
        XCTAssertTrue(
            auditHelperText.contains("dialog[open]")
                && auditHelperText.contains(#"[role="dialog"]"#),
            "The active-layer audit should cover generic dialogs in addition to QuillCode-specific popovers and panels."
        )
    }

    func testRenderedHarnessUsesNamedClearanceTokensForDenseActionClusters() throws {
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(
            harnessText.contains("--hit-target-clearance: 8px")
                && harnessText.contains("--control-cluster-gap: 10px"),
            "The rendered harness should expose named click-target clearance tokens that mirror the native design metrics."
        )
        XCTAssertTrue(
            harnessText.contains(".model-category { display: grid; gap: var(--hit-target-clearance); }")
                && harnessText.contains(".model-actions {\n      display: flex;\n      gap: var(--hit-target-clearance);")
                && harnessText.contains(".browser-nav-controls {\n      display: grid;\n      grid-template-columns: repeat(3, var(--hit-target)) minmax(72px, auto);\n      gap: var(--hit-target-clearance);")
                && harnessText.contains(".sidebar-saved-search-row {\n      display: grid;\n      grid-template-columns: minmax(0, 1fr) var(--hit-target) var(--hit-target) var(--hit-target);\n      align-items: center;\n      gap: var(--hit-target-clearance);")
                && harnessText.contains(".slash-suggestion-list {\n      display: grid;\n      gap: var(--hit-target-clearance);"),
            "Dense rendered action groups should use the shared clearance token instead of local 6 px gaps that make adjacent targets ambiguous."
        )
    }

    func testHTMLButtonPrimitiveDefaultsToSharedHitTargetClass() throws {
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")

        XCTAssertTrue(
            primitivesText.contains("classesWithDefaultHitTarget")
                && primitivesText.contains("defaultKind: WorkspaceHTMLHitTargetKind = .text")
                && primitivesText.contains("return trimmed + [defaultKind.className]"),
            "HTML button attributes should add the default semantic hit-target kind unless a more specific shared target class is already present."
        )
        XCTAssertTrue(
            primitivesText.contains("enum WorkspaceHTMLHitTargetKind")
                && primitivesText.contains("case icon")
                && primitivesText.contains("case textEntry = \"text-entry\"")
                && primitivesText.contains("case segmented")
                && primitivesText.contains("case switchRow = \"switch-row\"")
                && primitivesText.contains("case formAction = \"form-action\"")
                && primitivesText.contains("case adjustable = \"adjustable\"")
                && primitivesText.contains("var nativeKind: QuillCodeNativeHitTargetKind")
                && primitivesText.contains("var className: String"),
            "Rendered controls should declare hit-target intent through the same native semantic vocabulary instead of passing target CSS classes as the primary API."
        )
        XCTAssertTrue(
            primitivesText.contains(#"static let hitTargetKindAttributeName = "data-hit-target-kind""#)
                && primitivesText.contains(#"static let hitTargetActionAttributeName = "data-hit-target-action""#)
                && primitivesText.contains(#"static let hitTargetSourceAttributeName = "data-hit-target-source""#)
                && primitivesText.contains("static func hitTargetKindAttribute(forClasses classes: [String])")
                && primitivesText.contains("static func hitTargetAttributes(kind: WorkspaceHTMLHitTargetKind")
                && primitivesText.contains("static func hitTargetAttributes(classes: [String])")
                && primitivesText.contains("hitTargetKindByClass")
                && primitivesText.contains(##"#"\#(hitTargetActionAttributeName)="\#(escape(kind.action))""#"##)
                && primitivesText.contains(##"#"\#(hitTargetSourceAttributeName)="explicit""#"##)
                && primitivesText.contains(##"parts.append(#"\#(hitTargetKindAttributeName)="\#(escape(hitTargetKind.rawValue))""#)"##)
                && primitivesText.contains(##"parts.append(#"\#(hitTargetActionAttributeName)="\#(escape(hitTargetKind.action))""#)"##)
                && primitivesText.contains(##"parts.append(#"\#(hitTargetSourceAttributeName)="explicit""#)"##),
            "HTML primitives should emit explicit semantic hit-target kind, action, and source so rendered controls can be audited by contract, not only by geometry."
        )
        XCTAssertTrue(
            primitivesText.contains("static func summary(")
                && primitivesText.contains("<summary\\(elementAttributes("),
            "HTML details summaries should route through the shared primitive so disclosure controls keep named hit targets."
        )
        XCTAssertTrue(
            primitivesText.contains("private static func isHitTargetClass")
                && primitivesText.contains("ownedHitTargetClass")
                && primitivesText.contains("linkHitTargetClass")
                && primitivesText.contains("textEntryHitTargetClass")
                && primitivesText.contains("segmentedHitTargetClass")
                && primitivesText.contains("switchRowHitTargetClass")
                && primitivesText.contains("formActionHitTargetClass"),
            "The defaulting helper should recognize every shared rendered hit-target class instead of duplicating class-name logic at call sites."
        )
        XCTAssertTrue(
            primitivesText.contains("adjustableHitTargetClass")
                && primitivesText.contains("nativeKind.renderedClassName"),
            "Rendered adjustable controls such as range inputs should derive their semantic class from the shared native vocabulary instead of falling through to generic ownership."
        )
    }

    func testHarnessAuditsVisibleCommandTargetsForRouting() throws {
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
        let interactionSpecText = try Self.playwrightInteractionAuditSpecText(names: [
            "interaction-audit-routability.ts",
            "interaction-audit-registry.spec.ts",
            "interaction-audit-fixtures.spec.ts"
        ])

        XCTAssertTrue(
            harnessText.contains("const harnessStaticCommandIDs = new Set")
                && harnessText.contains("const harnessRoutableCommandPrefixes = [")
                && harnessText.contains("'sidebar-saved-search:'"),
            "The harness should keep an explicit command routing registry for rendered command targets."
        )
        XCTAssertTrue(
            harnessText.contains("function canRouteHarnessCommand(commandID)")
                && harnessText.contains("function commandRoutingAuditReport()")
                && harnessText.contains("unroutableCommands")
                && harnessText.contains("unroutableTargets"),
            "The harness should expose a reusable audit report for command IDs that would silently no-op."
        )
        XCTAssertTrue(
            harnessText.contains("window.__quillCodeCommandRoutingAudit = commandRoutingAuditReport"),
            "Playwright should be able to call the command routing audit after every rendered state."
        )
        XCTAssertTrue(
            harnessText.contains("if (!canRouteHarnessCommand(commandID))")
                && harnessText.contains("state.lastUnroutableCommandID"),
            "The harness command dispatcher should reject unknown command IDs instead of silently rerendering."
        )
        XCTAssertTrue(
            interactionSpecText.contains("expectCommandTargetsRoutable(page, label)")
                && interactionSpecText.contains("command routing audit catches visible dead command targets"),
            "The broad interaction audit should include command routing, with a regression proving dead command targets fail."
        )
    }

    func testRenderedCriticalTargetRegistryCoversPrimarySurfaces() throws {
        let interactionSpecText = try Self.playwrightInteractionAuditSpecText(names: [
            "interaction-audit-helpers.ts",
            "interaction-audit.spec.ts",
            "interaction-audit-registry.spec.ts",
            "interaction-audit-fixtures.spec.ts",
            "interaction-audit-edge-controls.spec.ts",
            "interaction-audit-responsive.spec.ts",
            "interaction-audit-routability.ts"
        ])

        for requiredSurface in [
            "primary workspace chrome",
            "top-bar overflow menu",
            "model picker",
            "command palette",
            "settings panel",
            "terminal pane",
            "browser pane",
            "extensions pane",
            "memories pane",
            "automations pane",
            "transcript tool card"
        ] {
            XCTAssertTrue(
                interactionSpecText.contains(requiredSurface),
                "The critical click-target registry should cover \(requiredSurface)."
            )
        }

        XCTAssertTrue(
            interactionSpecText.contains("model-detail-button")
                && interactionSpecText.contains("model-favorite-button")
                && interactionSpecText.contains("settings-sign-in")
                && interactionSpecText.contains("browser-comment-input")
                && interactionSpecText.contains("extension-mcp-resource-action")
                && interactionSpecText.contains("memory-delete")
                && interactionSpecText.contains("automation-primary-action")
                && interactionSpecText.contains("tool-card-details"),
            "The registry should include small/high-risk controls that commonly regress: model row actions, settings auth, browser inputs, and tool disclosures."
        )
        XCTAssertTrue(
            interactionSpecText.contains("sidebar saved-search controls")
                && interactionSpecText.contains("sidebar saved-search chip"),
            "The broad click-target audit should cover custom sidebar saved searches, since they are dynamically rendered command targets."
        )
        XCTAssertTrue(
            interactionSpecText.contains("sidebar saved-search create button")
                && interactionSpecText.contains("sidebar saved-search delete button")
                && interactionSpecText.contains("sidebar saved-search move down button")
                && interactionSpecText.contains("sidebar saved-search move up button")
                && interactionSpecText.contains("saved-search query leading interior")
                && interactionSpecText.contains("saved-search title trailing interior"),
            "Saved-search management should audit create/delete/reorder targets and text-entry focus from interior clicks, not only the selected chip."
        )
        XCTAssertTrue(
            interactionSpecText.contains("secondary pane controls respond from the full interior click target")
                && interactionSpecText.contains("terminal run trailing interior")
                && interactionSpecText.contains("browser new tab leading interior")
                && interactionSpecText.contains("extension start trailing interior")
                && interactionSpecText.contains("memory edit leading interior")
                && interactionSpecText.contains("automation run leading interior"),
            "Secondary pane controls should be edge-clicked in Playwright so non-central hit-area regressions fail before release."
        )
        XCTAssertTrue(
            interactionSpecText.contains("primary utility controls activate from near-edge target points")
                && interactionSpecText.contains("settings save trailing edge")
                && interactionSpecText.contains("worktree choice trailing edge")
                && interactionSpecText.contains("model favorite icon trailing edge")
                && interactionSpecText.contains("command palette browser result leading edge"),
            "Primary utility click-target coverage should verify near-edge activation, not only target geometry and semantic classes."
        )
        XCTAssertTrue(
            interactionSpecText.contains("sidebar and project controls activate from near-edge target points")
                && interactionSpecText.contains("saved search delete trailing edge")
                && interactionSpecText.contains("sidebar duplicate action trailing edge")
                && interactionSpecText.contains("project refresh action trailing edge"),
            "Sidebar and project rows, menus, saved searches, and destructive controls should prove near-edge activation instead of relying only on broad geometry audits."
        )
        XCTAssertTrue(
            interactionSpecText.contains("transcript, recovery, and suggestion controls activate from near-edge target points")
                && interactionSpecText.contains("empty starter trailing edge")
                && interactionSpecText.contains("slash suggestion leading edge")
                && interactionSpecText.contains("assistant retry trailing edge")
                && interactionSpecText.contains("runtime retry leading edge"),
            "Transcript, slash suggestion, context, and recovery controls should be edge-clicked because these are common small targets users hit during normal work."
        )
        XCTAssertTrue(
            interactionSpecText.contains("audits narrow viewport click targets across squeezed states")
                && interactionSpecText.contains("width: 320"),
            "Click-target coverage should include a narrow squeezed viewport, not only standard desktop and phone widths."
        )
        XCTAssertTrue(
            interactionSpecText.contains("expectedKind: 'icon'")
                && interactionSpecText.contains("expectedKind: 'text-entry'")
                && interactionSpecText.contains("expectedKind: 'row'")
                && interactionSpecText.contains("expectedKind: 'text'"),
            "Critical click-target probes should assert the intended semantic target kind, not only any shared class."
        )
        XCTAssertTrue(
            interactionSpecText.contains("expectedKind: 'form-action'")
                || interactionSpecText.contains("expectedKind: 'capsule'"),
            "Critical click-target probes should include compact form-action or capsule controls, not only generic row/text/icon controls."
        )
        XCTAssertTrue(
            interactionSpecText.contains("expectCriticalTargetSurfaceRegistry")
                && interactionSpecText.contains("primary workspace chrome")
                && interactionSpecText.contains("requiredKinds: ['text-entry', 'text']")
                && interactionSpecText.contains("requiredKinds: ['capsule', 'icon']"),
            "Critical click-target coverage should be organized by surface-level target mixes, not just a flat list of controls."
        )
        XCTAssertTrue(
            interactionSpecText.contains("button-declared-as-text-entry-target")
                && interactionSpecText.contains("button-declared-as-link-action")
                && interactionSpecText.contains("link-declared-as-press-target")
                && interactionSpecText.contains("kind-class-mismatch-target")
                && interactionSpecText.contains("missing-tactile-contract-target")
                && interactionSpecText.contains("hit_target_kind_class_mismatch")
                && interactionSpecText.contains("hit_target_action_mismatch")
                && interactionSpecText.contains("element_action_mismatch")
                && interactionSpecText.contains("missing_press_feedback_transition"),
            "The click-target audit should include fixtures for semantic and tactile mismatches so controls cannot pass by being large while lying about button/link/text-entry behavior or skipping press feedback."
        )
        XCTAssertTrue(
            interactionSpecText.contains("too-close-a")
                && interactionSpecText.contains("too-close-b")
                && interactionSpecText.contains("report.clearanceIssues")
                && interactionSpecText.contains("gap: 2"),
            "The click-target audit should include a near-miss spacing fixture so adjacent controls cannot pass solely because they do not overlap."
        )
    }

    func testFindBarUsesResponsiveTargetPreservingLayout() throws {
        let findText = try Self.appSourceText(named: "QuillCodeTranscriptFindView.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(
            findText.contains("ViewThatFits(in: .horizontal)")
                && findText.contains("compactLayout")
                && findText.contains("quillCodeTextEntryTarget()"),
            "Native transcript find should switch to a compact layout before the search field can shrink below its text-entry target."
        )
        XCTAssertTrue(
            harnessText.contains(".find-bar input,\n      .find-status")
                && harnessText.contains("grid-column: 1 / -1"),
            "Rendered transcript find should wrap input/status rows on compact widths instead of squeezing the input target."
        )
    }

    func testHarnessNormalizesDynamicClickTargetContracts() throws {
        let harnessText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        XCTAssertTrue(
            harnessText.contains("function normalizeInteractionTargetContracts")
                && harnessText.contains("sharedHitTargetClasses")
                && harnessText.contains("function fallbackHitTargetContract")
                && harnessText.contains("function existingHitTargetKind")
                && harnessText.contains("function hitTargetAction")
                && harnessText.contains("element.dataset.hitTargetSource = 'class'")
                && harnessText.contains("element.dataset.hitTargetKind = `auto-${kind}`"),
            "The dynamic HTML harness should attach explicit semantic hit-target contracts after every render instead of relying on global button/input CSS."
        )
        XCTAssertTrue(
            harnessText.contains("element.dataset.hitTargetAction = `auto-${hitTargetAction(kind)}`")
                && harnessText.contains("element.dataset.hitTargetSource = 'auto'"),
            "The dynamic HTML harness should mark fallback targets as auto-inferred so audits can reject accidental missing semantic contracts."
        )
        XCTAssertTrue(
            harnessText.contains(#"data-testid="activity-section-toggle""#)
                && harnessText.contains(#"data-hit-target-kind="row""#)
                && harnessText.contains(#"data-hit-target-action="press""#)
                && harnessText.contains(#"data-hit-target-source="explicit""#)
                && harnessText.contains(#"data-testid="activity-source-action""#)
                && harnessText.contains(#"data-hit-target-kind="form-action""#),
            "Activity section toggles and source actions should declare explicit rendered hit-target contracts instead of relying on post-render normalization."
        )
        XCTAssertTrue(
            harnessText.contains(#".activity-section [data-testid="activity-section-toggle"]"#)
                && harnessText.contains("flex: 0 0 auto;")
                && harnessText.contains("width: auto;")
                && harnessText.contains("min-width: var(--hit-target);"),
            "Activity source actions should not inherit the full-width section-toggle layout; compact actions still need fixed 44 px target floors."
        )
        XCTAssertTrue(
            harnessText.contains("['hit-target-icon', 'icon']")
                && harnessText.contains("['hit-target-text-entry', 'text-entry']")
                && harnessText.contains("element.classList.contains('hit-target-segmented')")
                && harnessText.contains("['hit-target-row', 'row']")
                && harnessText.contains("['hit-target-switch-row', 'switch-row']")
                && harnessText.contains("['hit-target-capsule', 'capsule']")
                && harnessText.contains("['hit-target-adjustable', 'adjustable']")
                && harnessText.contains("['hit-target-text', 'text']"),
            "Dynamic fallback targets should classify controls as icon, text-entry, row, switch-row, capsule, adjustable, or text before using generic ownership, while preserving explicit segmented targets."
        )
        XCTAssertTrue(
            harnessText.contains("normalizeInteractionTargetContracts(document.getElementById('app'))"),
            "The dynamic hit-target normalizer should run immediately after rendering before audits and click handlers observe the DOM."
        )
    }

    func testHTMLRenderersUseSharedClickTargetPrimitives() throws {
        let rendererFiles = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
            .filter {
                $0.lastPathComponent.hasPrefix("WorkspaceHTML")
                    && $0.lastPathComponent != "WorkspaceHTMLPrimitives.swift"
            }
        let violations = try HTMLSourceInteractionTargetAudit(
            packageRoot: Self.packageRoot()
        )
        .violations(in: rendererFiles)

        XCTAssertTrue(
            violations.isEmpty,
            "Generated HTML controls must route through shared click-target primitives or shared hit-target classes:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testRenderedHTMLPrimitiveCallSitesDeclareExplicitHitTargetKinds() throws {
        let appFiles = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
            .filter { $0.lastPathComponent != "WorkspaceHTMLPrimitives.swift" }
        let violations = try HTMLPrimitiveHitTargetKindAudit(packageRoot: Self.packageRoot())
            .violations(in: appFiles)

        XCTAssertTrue(
            violations.isEmpty,
            "Rendered HTML primitive call sites must choose a semantic click-target kind explicitly:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testHTMLSourceAuditRequiresSemanticKindForRawSharedTargets() throws {
        let file = try makeTemporarySwiftFile(##"""
        enum BadHTMLRenderer {
            func render() -> String {
                #"<input class="\#(WorkspaceHTMLPrimitives.textEntryHitTargetClass)" aria-label="Search">"#
            }
        }
        """##)

        let violations = try HTMLSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertTrue(
            violations.contains { $0.contains("shared hit-target class without full semantic data-hit-target-kind/action/source contract") },
            "Raw generated HTML that directly uses a shared target class should also declare the full semantic hit-target contract."
        )
    }

    func testHTMLSourceAuditAcceptsRawSharedTargetsWithSemanticKind() throws {
        let file = try makeTemporarySwiftFile(##"""
        enum GoodHTMLRenderer {
            func render() -> String {
                #"<input\#(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) aria-label="Search">"#
            }
        }
        """##)

        let violations = try HTMLSourceInteractionTargetAudit(packageRoot: file.deletingLastPathComponent())
            .violations(in: [file])

        XCTAssertEqual(violations, [])
    }

}

private extension ParityInteractionTargetGateTests {
    static func playwrightInteractionAuditSpecText(names: [String]) throws -> String {
        let testRoot = packageRoot().appendingPathComponent("E2E/playwright/tests")
        return try names
            .map { name in
                try String(contentsOf: testRoot.appendingPathComponent(name), encoding: .utf8)
            }
            .joined(separator: "\n")
    }
}
