import XCTest

final class ParityRenderedCommandRoutingGateTests: QuillCodeParityTestCase {
    func testHarnessAuditsVisibleCommandTargetsForRouting() throws {
        let harnessText = try ParityInteractionTargetTextSupport.harnessText(
            packageRoot: Self.packageRoot()
        )
        let interactionSpecText = try ParityInteractionTargetTextSupport.specText(
            packageRoot: Self.packageRoot(),
            names: [
                "interaction-audit-routability.ts",
                "interaction-audit-registry.spec.ts",
                "interaction-audit-fixtures.spec.ts",
            ]
        )

        Self.assertSource(harnessText, containsAll: [
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
        ])
        Self.assertSource(interactionSpecText, containsAll: [
            "expectCommandTargetsRoutable(page, label)",
            "command routing audit catches visible dead command targets",
        ])
    }
}
