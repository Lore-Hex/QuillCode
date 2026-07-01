import XCTest

final class ParityInteractionTargetRegistryGateTests: QuillCodeParityTestCase {
    func testRenderedCriticalTargetRegistryCoversPrimarySurfaces() throws {
        let specText = try Self.playwrightInteractionAuditText(names: [
            "interaction-audit-helpers.ts",
            "interaction-audit.spec.ts",
            "interaction-audit-registry.spec.ts",
            "interaction-audit-fixtures.spec.ts",
            "interaction-audit-edge-controls.spec.ts",
            "interaction-audit-responsive.spec.ts",
            "interaction-audit-routability.ts",
        ])

        Self.assertInteractionTargetText(
            specText,
            containsAll: [
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
                "transcript tool card",
            ],
            reason: "The critical click-target registry should cover primary app surfaces."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAll: [
                "model-detail-button",
                "model-favorite-button",
                "settings-sign-in",
                "browser-comment-input",
                "extension-mcp-resource-action",
                "memory-delete",
                "automation-primary-action",
                "tool-card-details",
            ],
            reason: "The registry should include small high-risk controls."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAll: [
                "sidebar saved-search controls",
                "sidebar saved-search chip",
                "sidebar saved-search create button",
                "sidebar saved-search delete button",
                "sidebar saved-search move down button",
                "sidebar saved-search move up button",
                "saved-search query leading interior",
                "saved-search title trailing interior",
            ],
            reason: "Saved-search management should audit dynamic command targets."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAll: [
                "secondary pane controls respond from the full interior click target",
                "terminal run trailing interior",
                "browser new tab leading interior",
                "extension start trailing interior",
                "memory edit leading interior",
                "automation run leading interior",
                "primary utility controls activate from near-edge target points",
                "settings save trailing edge",
                "worktree choice trailing edge",
                "model favorite icon trailing edge",
                "command palette browser result leading edge",
            ],
            reason: "Secondary-pane and utility controls should be edge-clicked."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAll: [
                "sidebar and project controls activate from near-edge target points",
                "saved search delete trailing edge",
                "sidebar duplicate action trailing edge",
                "project refresh action trailing edge",
                "transcript, recovery, and suggestion controls activate from near-edge target points",
                "empty starter trailing edge",
                "slash suggestion leading edge",
                "assistant retry trailing edge",
                "runtime retry leading edge",
            ],
            reason: "Sidebar, transcript, recovery, and suggestion controls should be edge-clicked."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAll: [
                "audits narrow viewport click targets across squeezed states",
                "width: 320",
                "expectedKind: 'icon'",
                "expectedKind: 'text-entry'",
                "expectedKind: 'row'",
                "expectedKind: 'text'",
            ],
            reason: "Registry probes should cover squeezed viewports and semantic kinds."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAny: [
                "expectedKind: 'form-action'",
                "expectedKind: 'capsule'",
            ],
            reason: "Registry probes should include compact form-action or capsule controls."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAll: [
                "expectCriticalTargetSurfaceRegistry",
                "primary workspace chrome",
                "requiredKinds: ['text-entry', 'text']",
                "requiredKinds: ['capsule', 'icon']",
            ],
            reason: "Critical target coverage should be organized by surface-level mixes."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAll: [
                "button-declared-as-text-entry-target",
                "button-declared-as-link-action",
                "link-declared-as-press-target",
                "kind-class-mismatch-target",
                "missing-tactile-contract-target",
                "hit_target_kind_class_mismatch",
                "hit_target_action_mismatch",
                "element_action_mismatch",
                "missing_press_feedback_transition",
            ],
            reason: "Fixture coverage should catch semantic and tactile mismatches."
        )
        Self.assertInteractionTargetText(
            specText,
            containsAll: [
                "too-close-a",
                "too-close-b",
                "report.clearanceIssues",
                "gap: 2",
            ],
            reason: "The audit should include a near-miss spacing fixture."
        )
    }
}
