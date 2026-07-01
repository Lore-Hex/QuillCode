import XCTest

final class ParityInteractionTargetHarnessGateTests: QuillCodeParityTestCase {
    func testRenderedHarnessUsesNamedClearanceTokensForDenseActionClusters() throws {
        let harnessText = try Self.renderedHarnessText()

        Self.assertInteractionTargetText(
            harnessText,
            containsAll: [
                "--hit-target-clearance: 8px",
                "--control-cluster-gap: 10px",
                ".model-category { display: grid; gap: var(--hit-target-clearance); }",
                ".model-actions {",
                ".browser-nav-controls {",
                ".sidebar-saved-search-row {",
                ".slash-suggestion-list {",
                "gap: var(--hit-target-clearance);",
            ],
            reason: "Dense rendered action groups should use shared clearance tokens."
        )
        Self.assertInteractionTargetText(
            harnessText,
            containsAll: [
                "grid-template-columns: repeat(3, var(--hit-target)) minmax(72px, auto);",
                "grid-template-columns: minmax(0, 1fr) var(--hit-target) var(--hit-target)",
            ],
            reason: "Dense rows should preserve fixed hit-target tracks while shrinking."
        )
    }

    func testHarnessAuditsVisibleCommandTargetsForRouting() throws {
        let harnessText = try Self.renderedHarnessText()
        let interactionSpecText = try Self.playwrightInteractionAuditText(names: [
            "interaction-audit-routability.ts",
            "interaction-audit-registry.spec.ts",
            "interaction-audit-fixtures.spec.ts",
        ])

        Self.assertInteractionTargetText(
            harnessText,
            containsAll: [
                "const harnessStaticCommandIDs = new Set",
                "const harnessRoutableCommandPrefixes = [",
                "'sidebar-saved-search:'",
                "function canRouteHarnessCommand(commandID)",
                "function commandRoutingAuditReport()",
                "unroutableCommands",
                "unroutableTargets",
                "window.__quillCodeCommandRoutingAudit = commandRoutingAuditReport",
                "if (!canRouteHarnessCommand(commandID))",
                "state.lastUnroutableCommandID",
            ],
            reason: "Rendered command targets should be routed explicitly and reject dead IDs."
        )
        Self.assertInteractionTargetText(
            interactionSpecText,
            containsAll: [
                "expectCommandTargetsRoutable(page, label)",
                "command routing audit catches visible dead command targets",
            ],
            reason: "Playwright should run command-routing checks in the broad audit."
        )
    }

    func testFindBarUsesResponsiveTargetPreservingLayout() throws {
        let findText = try Self.appSourceText(named: "QuillCodeTranscriptFindView.swift")
        let harnessText = try Self.renderedHarnessText()

        Self.assertInteractionTargetText(
            findText,
            containsAll: [
                "ViewThatFits(in: .horizontal)",
                "compactLayout",
                "quillCodeTextEntryTarget()",
            ],
            reason: "Native transcript find should use compact layout before target shrinkage."
        )
        Self.assertInteractionTargetText(
            harnessText,
            containsAll: [
                ".find-bar input,\n      .find-status",
                "grid-column: 1 / -1",
            ],
            reason: "Rendered transcript find should wrap on compact widths."
        )
    }

    func testHarnessNormalizesDynamicClickTargetContracts() throws {
        let harnessText = try Self.renderedHarnessText()

        Self.assertInteractionTargetText(
            harnessText,
            containsAll: [
                "function normalizeInteractionTargetContracts",
                "sharedHitTargetClasses",
                "function fallbackHitTargetContract",
                "function existingHitTargetKind",
                "function hitTargetAction",
                "element.dataset.hitTargetSource = 'class'",
                "element.dataset.hitTargetKind = `auto-${kind}`",
                "element.dataset.hitTargetAction = `auto-${hitTargetAction(kind)}`",
                "element.dataset.hitTargetSource = 'auto'",
            ],
            reason: "Dynamic HTML should attach explicit semantic contracts after each render."
        )
        Self.assertInteractionTargetText(
            harnessText,
            containsAll: [
                #"data-testid="activity-section-toggle""#,
                #"data-hit-target-kind="row""#,
                #"data-hit-target-action="press""#,
                #"data-hit-target-source="explicit""#,
                #"data-testid="activity-source-action""#,
                #"data-hit-target-kind="form-action""#,
            ],
            reason: "Activity controls should declare explicit contracts before normalization."
        )
        Self.assertInteractionTargetText(
            harnessText,
            containsAll: [
                #".activity-section [data-testid="activity-section-toggle"]"#,
                "flex: 0 0 auto;",
                "width: auto;",
                "min-width: var(--hit-target);",
            ],
            reason: "Activity source actions should stay compact while preserving target floors."
        )
        Self.assertInteractionTargetText(
            harnessText,
            containsAll: [
                "['hit-target-icon', 'icon']",
                "['hit-target-text-entry', 'text-entry']",
                "element.classList.contains('hit-target-segmented')",
                "['hit-target-row', 'row']",
                "['hit-target-switch-row', 'switch-row']",
                "['hit-target-capsule', 'capsule']",
                "['hit-target-adjustable', 'adjustable']",
                "['hit-target-text', 'text']",
                "normalizeInteractionTargetContracts(document.getElementById('app'))",
            ],
            reason: "Fallback targets should classify every shared target kind before auditing."
        )
    }
}
