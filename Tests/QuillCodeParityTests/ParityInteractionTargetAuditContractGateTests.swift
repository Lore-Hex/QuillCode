import XCTest

final class ParityInteractionTargetAuditContractGateTests: QuillCodeParityTestCase {
    func testHTMLInteractionAuditRequiresNamedClickableTargets() throws {
        let auditText = try Self.playwrightInteractionAuditContractText()

        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "accessibleName(element)",
                "missing_accessible_name",
            ],
            reason: "Visible interactive elements should need user-facing names."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "button",
                "[role=\"button\"]",
                "[role=\"tab\"]",
                "label",
                "range",
                "textarea",
            ],
            reason: "The audit should cover native controls, ARIA controls, labels, and text entry."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "MINIMUM_HIT_TARGET = 44",
                "expectHitTarget(locator: Locator",
            ],
            reason: "Whole-screen and explicit critical-control probes should keep the 44 px floor."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "MINIMUM_TARGET_CLEARANCE = 8",
                "clearanceIssues",
                "expectNoAmbiguousAdjacentInteractiveTargets",
                "allowsTightClearance",
                #"[data-testid="sidebar-compose-zone"]"#,
            ],
            reason: "Adjacent targets should keep clearance except for intentional dense rows."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "export type CriticalTargetProbe",
                "expectedKind?: string",
                "expectCriticalTargetRegistry",
                "export type CriticalTargetSurface",
                "requiredKinds: string[]",
                "expectCriticalTargetSurfaceRegistry",
                "should declare semantic click-target intent",
            ],
            reason: "Critical probes should be named and grouped by interaction surface."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "target.evaluate",
                "elementFromPoint",
                "clickableInteriorIssues",
                "TARGET_INTERIOR_SAMPLE_FRACTIONS = [0.2, 0.5, 0.8]",
                "TARGET_EDGE_SAMPLE_FRACTIONS = [0.08, 0.92]",
                "targetInteriorSamplePoints",
            ],
            reason: "Critical probes should test near-edge and interior clickability."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "pointer_events_none",
                "isSemanticallyDisabled",
                "missing_click_affordance",
                "requiresPointerAffordance",
            ],
            reason: "Clickable controls should expose pointer behavior unless disabled."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "requiresTactileFeedbackContract",
                "missing_touch_action_manipulation",
                "click_target_allows_text_selection",
                "missing_press_feedback_transition",
            ],
            reason: "Visible controls should inherit the shared tactile contract."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "missing_shared_hit_target_contract",
                "SHARED_HIT_TARGET_CLASSES",
                "EXPECTED_KIND_BY_CLASS",
                "'hit-target-adjustable': 'adjustable'",
            ],
            reason: "Interactive controls should declare shared hit-target ownership."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "EXPECTED_ACTION_BY_KIND",
                "missing_hit_target_action",
                "hit_target_kind_class_mismatch",
                "hit_target_action_mismatch",
                "element_action_mismatch",
                "expectedElementAction(element)",
                "data-hit-target-source",
                "data-hit-target-action",
            ],
            reason: "Controls should keep coherent semantic kind, action, and source metadata."
        )
        Self.assertInteractionTargetText(
            auditText,
            containsAll: [
                "closestInteractiveAncestor",
                "nestedIssues",
                "expectNoNestedInteractiveTargets",
                "isAuditableInteractiveElement",
                "HTMLLabelElement",
                "associatedLabelControl",
                "dialog[open]",
                #"[role="dialog"]"#,
            ],
            reason: "The audit should catch nested controls, active labels, and open dialogs."
        )
    }
}
