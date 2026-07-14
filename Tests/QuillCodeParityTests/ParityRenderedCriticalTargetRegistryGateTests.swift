import XCTest

final class ParityRenderedCriticalTargetRegistryGateTests: QuillCodeParityTestCase {
    func testRenderedCriticalTargetRegistryCoversPrimarySurfaces() throws {
        let specText = try interactionSpecText()

        Self.assertSource(specText, containsAll: [
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
            "expectCriticalTargetSurfaceRegistry",
            "requiredKinds: ['text-entry', 'text']",
            "requiredKinds: ['capsule', 'icon']",
        ])
    }

    func testRenderedCriticalTargetRegistryCoversRiskySmallControls() throws {
        let specText = try interactionSpecText()

        Self.assertSource(specText, containsAll: [
            "model-detail-button",
            "model-favorite-button",
            "settings-sign-in",
            "browser-comment-input",
            "extension-mcp-resource-action",
            "memory-delete",
            "automation-primary-action",
            "tool-card-details",
            "sidebar filter menu button",
            "sidebar select chats action",
            "sidebar saved-search chip",
            "sidebar saved-search create button",
            "sidebar saved-search delete button",
            "sidebar saved-search move down button",
            "sidebar saved-search move up button",
            "saved-search query leading interior",
            "saved-search title trailing interior",
        ])
    }

    func testRenderedCriticalTargetRegistryCoversNearEdgeFlows() throws {
        let specText = try interactionSpecText()

        Self.assertSource(specText, containsAll: [
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
            "sidebar and project controls activate from near-edge target points",
            "saved search delete trailing edge",
            "sidebar duplicate action trailing edge",
            "project refresh action trailing edge",
            "transcript, recovery, and suggestion controls activate",
            "empty starter trailing edge",
            "slash suggestion leading edge",
            "assistant retry trailing edge",
            "runtime retry leading edge",
            "audits narrow viewport click targets across squeezed states",
            "width: 320",
        ])
    }

    func testRenderedCriticalTargetRegistryIncludesSemanticFixtures() throws {
        let specText = try interactionSpecText()

        Self.assertSource(specText, containsAll: [
            "expectedKind: 'icon'",
            "expectedKind: 'text-entry'",
            "expectedKind: 'row'",
            "expectedKind: 'text'",
            "button-declared-as-text-entry-target",
            "button-declared-as-link-action",
            "link-declared-as-press-target",
            "kind-class-mismatch-target",
            "missing-tactile-contract-target",
            "hit_target_kind_class_mismatch",
            "hit_target_action_mismatch",
            "element_action_mismatch",
            "missing_press_feedback_transition",
            "too-close-a",
            "too-close-b",
            "report.clearanceIssues",
            "gap: 2",
        ])
        XCTAssertTrue(
            specText.contains("expectedKind: 'form-action'")
                || specText.contains("expectedKind: 'capsule'")
        )
    }

    private func interactionSpecText() throws -> String {
        try ParityInteractionTargetTextSupport.specText(
            packageRoot: Self.packageRoot(),
            names: [
                "interaction-audit-helpers.ts",
                "interaction-audit.spec.ts",
                "interaction-audit-registry.spec.ts",
                "interaction-audit-fixtures.spec.ts",
                "interaction-audit-edge-controls.spec.ts",
                "interaction-audit-responsive.spec.ts",
                "interaction-audit-routability.ts",
            ]
        )
    }
}
