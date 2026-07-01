import XCTest

final class ParityHTMLInteractionAuditContractGateTests: QuillCodeParityTestCase {
    func testHTMLInteractionAuditRequiresNamesControlsAndLayers() throws {
        let auditText = try ParityInteractionTargetTextSupport.auditText(
            packageRoot: Self.packageRoot()
        )

        Self.assertSource(auditText, containsAll: [
            "accessibleName(element)",
            "missing_accessible_name",
            "button",
            #"[role="button"]"#,
            #"[role="tab"]"#,
            "label",
            "range",
            "textarea",
            "dialog[open]",
            #"[role="dialog"]"#,
            "isAuditableInteractiveElement",
            "HTMLLabelElement",
            "associatedLabelControl",
        ])
    }

    func testHTMLInteractionAuditRequiresClearanceRegistriesAndSamples() throws {
        let auditText = try ParityInteractionTargetTextSupport.auditText(
            packageRoot: Self.packageRoot()
        )

        Self.assertSource(auditText, containsAll: [
            "MINIMUM_HIT_TARGET = 44",
            "expectHitTarget(locator: Locator",
            "MINIMUM_TARGET_CLEARANCE = 8",
            "clearanceIssues",
            "expectNoAmbiguousAdjacentInteractiveTargets",
            "allowsTightClearance",
            #"[data-testid="sidebar-compose-zone"]"#,
            "export type CriticalTargetProbe",
            "expectedKind?: string",
            "expectCriticalTargetRegistry",
            "export type CriticalTargetSurface",
            "requiredKinds: string[]",
            "expectCriticalTargetSurfaceRegistry",
            "should declare semantic click-target intent",
            "target.evaluate",
            "elementFromPoint",
            "clickableInteriorIssues",
            "TARGET_INTERIOR_SAMPLE_FRACTIONS = [0.2, 0.5, 0.8]",
            "TARGET_EDGE_SAMPLE_FRACTIONS = [0.08, 0.92]",
            "targetInteriorSamplePoints",
        ])
    }

    func testHTMLInteractionAuditRequiresSemanticAndTactileContracts() throws {
        let auditText = try ParityInteractionTargetTextSupport.auditText(
            packageRoot: Self.packageRoot()
        )

        Self.assertSource(auditText, containsAll: [
            "pointer_events_none",
            "isSemanticallyDisabled",
            "missing_click_affordance",
            "requiresPointerAffordance",
            "requiresTactileFeedbackContract",
            "missing_touch_action_manipulation",
            "click_target_allows_text_selection",
            "missing_press_feedback_transition",
            "missing_shared_hit_target_contract",
            "SHARED_HIT_TARGET_CLASSES",
            "EXPECTED_KIND_BY_CLASS",
            "'hit-target-adjustable': 'adjustable'",
            "EXPECTED_ACTION_BY_KIND",
            "missing_hit_target_action",
            "hit_target_kind_class_mismatch",
            "hit_target_action_mismatch",
            "element_action_mismatch",
            "expectedElementAction(element)",
            "data-hit-target-source",
            "data-hit-target-action",
            "closestInteractiveAncestor",
            "nestedIssues",
            "expectNoNestedInteractiveTargets",
        ])
    }
}
