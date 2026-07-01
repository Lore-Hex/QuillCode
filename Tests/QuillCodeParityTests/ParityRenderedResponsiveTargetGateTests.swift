import XCTest

final class ParityRenderedResponsiveTargetGateTests: QuillCodeParityTestCase {
    func testRenderedHarnessUsesNamedClearanceTokensForDenseActionClusters() throws {
        let harnessText = try ParityInteractionTargetTextSupport.harnessText(
            packageRoot: Self.packageRoot()
        )

        Self.assertSource(harnessText, containsAll: [
            "--hit-target-clearance: 8px",
            "--control-cluster-gap: 10px",
            ".model-category { display: grid; gap: var(--hit-target-clearance); }",
            ".model-actions {",
            "gap: var(--hit-target-clearance);",
            ".browser-nav-controls {",
            "grid-template-columns: repeat(3, var(--hit-target))",
            ".sidebar-saved-search-row {",
            "grid-template-columns: minmax(0, 1fr) var(--hit-target)",
            ".slash-suggestion-list {",
        ])
    }

    func testFindBarUsesResponsiveTargetPreservingLayout() throws {
        let findText = try Self.appSourceText(named: "QuillCodeTranscriptFindView.swift")
        let harnessText = try ParityInteractionTargetTextSupport.harnessText(
            packageRoot: Self.packageRoot()
        )

        Self.assertSource(findText, containsAll: [
            "ViewThatFits(in: .horizontal)",
            "compactLayout",
            "quillCodeTextEntryTarget()",
        ])
        Self.assertSource(harnessText, containsAll: [
            ".find-bar input,\n      .find-status",
            "grid-column: 1 / -1",
        ])
    }

    func testHarnessNormalizesDynamicClickTargetContracts() throws {
        let harnessText = try ParityInteractionTargetTextSupport.harnessText(
            packageRoot: Self.packageRoot()
        )

        Self.assertSource(harnessText, containsAll: [
            "function normalizeInteractionTargetContracts",
            "sharedHitTargetClasses",
            "function fallbackHitTargetContract",
            "function existingHitTargetKind",
            "function hitTargetAction",
            "element.dataset.hitTargetSource = 'class'",
            "element.dataset.hitTargetKind = `auto-${kind}`",
            "element.dataset.hitTargetAction = `auto-${hitTargetAction(kind)}`",
            "element.dataset.hitTargetSource = 'auto'",
            "normalizeInteractionTargetContracts(document.getElementById('app'))",
            "['hit-target-icon', 'icon']",
            "['hit-target-text-entry', 'text-entry']",
            "element.classList.contains('hit-target-segmented')",
            "['hit-target-row', 'row']",
            "['hit-target-switch-row', 'switch-row']",
            "['hit-target-capsule', 'capsule']",
            "['hit-target-adjustable', 'adjustable']",
            "['hit-target-text', 'text']",
        ])
    }

    func testHarnessDeclaresActivityTargetContracts() throws {
        let harnessText = try ParityInteractionTargetTextSupport.harnessText(
            packageRoot: Self.packageRoot()
        )

        Self.assertSource(harnessText, containsAll: [
            #"data-testid="activity-section-toggle""#,
            #"data-hit-target-kind="row""#,
            #"data-hit-target-action="press""#,
            #"data-hit-target-source="explicit""#,
            #"data-testid="activity-source-action""#,
            #"data-hit-target-kind="form-action""#,
            #".activity-section [data-testid="activity-section-toggle"]"#,
            "flex: 0 0 auto;",
            "width: auto;",
            "min-width: var(--hit-target);",
        ])
    }
}
