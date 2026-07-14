import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class QuillCodeNativeHitTargetSurfaceAuditTests: QuillCodeNativeHitTargetAuditTestCase {
    func testAuditCoversDesignSystemCommandsAndVisibleSecondaryPanes() {
        var surface = representativeSurface()

        let report = QuillCodeNativeHitTargetAudit.report(for: surface)

        XCTAssertTrue(report.isValid)
        assertGlobalReportMetrics(report)
        assertNoCoverageGaps(report)
        assertRequiredRepresentativeContracts(report)
        assertCommandCoverage(report, surface: surface)
        assertProbeCoverage(report)
        assertRepresentativeContractSemantics(report)
        assertSurfacePolicies(report)

        surface.commands.removeAll { $0.id == "toggle-extensions" }
        let missingReport = QuillCodeNativeHitTargetAudit.report(for: surface)
        XCTAssertEqual(missingReport.missingRequiredCommandIDs, ["toggle-extensions"])
        XCTAssertFalse(missingReport.isValid)
    }

    func testAuditCoversEverySurfaceFamilyForPlainWorkspaceSnapshot() {
        let report = QuillCodeNativeHitTargetAudit.report(for: QuillCodeWorkspaceModel().surface())

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.missingSurfaceFamilies, [])
        XCTAssertEqual(report.missingRequiredSurfaceKinds, [])
        XCTAssertEqual(report.missingRequiredSurfaceActions, [])
        XCTAssertEqual(report.missingRequiredSurfaceFocusTargets, [])
        XCTAssertEqual(report.unexpectedSurfaceKinds, [])
        XCTAssertEqual(report.unexpectedSurfaceActions, [])
        XCTAssertEqual(report.unexpectedSurfaceFocusTargets, [])
        XCTAssertEqual(report.missingRequiredFocusTargets, [])
        XCTAssertEqual(report.clickProbeValidationIssues, [])
        XCTAssertEqual(
            Set(report.coveredSurfaceFamilies),
            Set(QuillCodeInteractionSurfaceFamily.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(report.coveredFocusTargets),
            Set(QuillCodeNativeFocusTarget.allCases.map(\.rawValue))
        )
    }

    func testAuditCoversMemoryConflictEditActionWhenVisible() {
        var surface = representativeSurface()
        surface.memories = WorkspaceMemoriesSurface(
            isVisible: true,
            notes: [
                MemoryNote(
                    id: "global-preferences",
                    scope: .global,
                    title: "Preferences",
                    content: "Prefer SwiftUI surfaces.",
                    relativePath: "memories/preferences.md",
                    byteCount: 24
                ),
                MemoryNote(
                    id: "project:.quillcode/memories/project.md",
                    scope: .project,
                    title: "Project",
                    content: "Do not use SwiftUI surfaces.",
                    relativePath: ".quillcode/memories/project.md",
                    byteCount: 29
                )
            ],
            canEditProjectMemories: true
        )

        let report = QuillCodeNativeHitTargetAudit.report(for: surface)
        let contract = report.surfaceContracts.first { $0.id == "memories.conflict-edit" }

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(contract?.kind, .formAction)
        XCTAssertEqual(contract?.testID, "quillcode-memory-conflict-edit")
        XCTAssertEqual(contract?.label, "Edit conflicting memory")
    }

    func testAuditCoversMemoryRedactionAddActionWhenVisible() throws {
        var surface = representativeSurface()
        let event = try XCTUnwrap(MemoryRedactionReviewSurface.event(
            action: .save,
            userText: "/remember api_key=SYNTHETIC_TEST_SECRET_DO_NOT_USE"
        ))
        surface.memories = WorkspaceMemoriesSurface(isVisible: true, events: [event])

        let report = QuillCodeNativeHitTargetAudit.report(for: surface)
        let contract = report.surfaceContracts.first { $0.id == "memories.redaction-add" }

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(contract?.kind, .formAction)
        XCTAssertEqual(contract?.testID, "quillcode-memory-redaction-add")
        XCTAssertEqual(contract?.label, "Add safe memory")
    }
}

private extension QuillCodeNativeHitTargetSurfaceAuditTests {
    func assertGlobalReportMetrics(_ report: QuillCodeNativeHitTargetAuditReport) {
        XCTAssertEqual(report.minimumHitTarget, 40)
        XCTAssertEqual(report.minimumTargetClearance, 8)
        XCTAssertEqual(report.pressScale, 0.96)
        XCTAssertEqual(Set(report.designSystemContracts.map(\.kind)), Set(QuillCodeNativeHitTargetKind.allCases))
    }

    func assertNoCoverageGaps(_ report: QuillCodeNativeHitTargetAuditReport) {
        XCTAssertEqual(report.missingDesignKinds, [])
        XCTAssertEqual(report.missingSurfaceFamilies, [])
        XCTAssertEqual(report.missingRequiredSurfaceKinds, [])
        XCTAssertEqual(report.missingRequiredSurfaceActions, [])
        XCTAssertEqual(report.missingRequiredSurfaceFocusTargets, [])
        XCTAssertEqual(report.unexpectedSurfaceKinds, [])
        XCTAssertEqual(report.unexpectedSurfaceActions, [])
        XCTAssertEqual(report.unexpectedSurfaceFocusTargets, [])
        XCTAssertEqual(report.missingRequiredFocusTargets, [])
        XCTAssertEqual(report.missingRequiredCommandIDs, [])
        XCTAssertEqual(report.missingClickProbeContractIDs, [])
        XCTAssertEqual(report.clickProbeValidationIssues, [])
        XCTAssertEqual(report.duplicateContractIDs, [])
        XCTAssertEqual(report.validationIssues, [])
        XCTAssertEqual(Set(report.coveredSurfaceFamilies), Set(QuillCodeInteractionSurfaceFamily.allCases.map(\.rawValue)))
        XCTAssertEqual(Set(report.coveredFocusTargets), Set(QuillCodeNativeFocusTarget.allCases.map(\.rawValue)))
    }

    func assertRequiredRepresentativeContracts(_ report: QuillCodeNativeHitTargetAuditReport) {
        let contractsByID = Dictionary(uniqueKeysWithValues: report.surfaceContracts.map { ($0.id, $0) })
        for requiredID in requiredRepresentativeContractIDs {
            XCTAssertNotNil(contractsByID[requiredID], requiredID)
        }
    }

    func assertCommandCoverage(_ report: QuillCodeNativeHitTargetAuditReport, surface: WorkspaceSurface) {
        let commandContractIDs = Set(report.surfaceContracts.compactMap(\.commandID))
        XCTAssertEqual(
            commandContractIDs,
            Set(surface.commands.map(\.id)),
            "Every workspace command should declare a native click-target contract."
        )
    }

    func assertProbeCoverage(_ report: QuillCodeNativeHitTargetAuditReport) {
        let contractsByID = Dictionary(uniqueKeysWithValues: report.surfaceContracts.map { ($0.id, $0) })
        let probesByContractID = Dictionary(uniqueKeysWithValues: report.clickProbes.map { ($0.contractID, $0) })
        XCTAssertEqual(Set(report.clickProbes.map(\.contractID)), Set(report.surfaceContracts.map(\.id)))
        XCTAssertEqual(
            Set(probesByContractID["composer.send"]?.samplePoints.map(\.name) ?? []),
            Set(expectedSamplePoints.map(\.name))
        )
        XCTAssertEqual(probesByContractID["composer.send"]?.samplePoints, expectedSamplePoints)

        for probe in report.clickProbes {
            let contract = contractsByID[probe.contractID]
            XCTAssertFalse(probe.selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThanOrEqual(probe.requiredMinWidth, 40)
            XCTAssertGreaterThanOrEqual(probe.requiredMinHeight, 40)
            XCTAssertGreaterThanOrEqual(probe.requiredPeerClearance, 8)
            XCTAssertFalse(probe.collisionScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(probe.collisionScope, contract?.collisionScope)
            XCTAssertEqual(probe.allowsNestedInteractiveChildren, contract?.allowsNestedInteractiveChildren)
            XCTAssertEqual(probe.requiresUnblockedInterior, contract?.requiresUnblockedInterior)
            XCTAssertEqual(probe.requiresTactileFeedback, contract?.requiresTactileFeedback)
            XCTAssertEqual(probe.allowsTextSelection, contract?.allowsTextSelection)
            XCTAssertEqual(probe.samplePoints, expectedSamplePoints)
            XCTAssertTrue(probe.samplePoints.allSatisfy { $0.x > 0 && $0.x < 1 && $0.y > 0 && $0.y < 1 })
        }
    }

    func assertRepresentativeContractSemantics(_ report: QuillCodeNativeHitTargetAuditReport) {
        let contractsByID = Dictionary(uniqueKeysWithValues: report.surfaceContracts.map { ($0.id, $0) })
        let probesByContractID = Dictionary(uniqueKeysWithValues: report.clickProbes.map { ($0.contractID, $0) })

        XCTAssertTrue(report.surfaceContracts.allSatisfy { contract in
            contract.focusTarget != nil || contract.testID?.isEmpty == false || contract.commandID?.isEmpty == false
        })
        XCTAssertEqual(contractsByID["extensions.mcp-reference"]?.kind, .capsule)
        XCTAssertEqual(contractsByID["extensions.reference-action"]?.kind, .capsule)
        XCTAssertEqual(contractsByID["extensions.add"]?.kind, .icon)
        XCTAssertEqual(contractsByID["extensions.close"]?.kind, .icon)
        XCTAssertEqual(contractsByID["transcript.artifact-link"]?.kind, .link)
        XCTAssertEqual(contractsByID["memories.edit"]?.kind, .icon)
        XCTAssertEqual(contractsByID["memories.close"]?.kind, .icon)
        XCTAssertEqual(contractsByID["memories.item-action"]?.kind, .icon)
        XCTAssertEqual(contractsByID["automations.create"]?.kind, .formAction)
        XCTAssertEqual(contractsByID["automations.close"]?.kind, .icon)
        XCTAssertEqual(contractsByID["review.mode"]?.kind, .segmentedControl)
        XCTAssertEqual(contractsByID["browser.comment"]?.kind, .textEntry)
        XCTAssertEqual(contractsByID["browser.family-icon"]?.kind, .icon)
        XCTAssertEqual(contractsByID["transcript.thinking-trace"]?.kind, .capsule)
        XCTAssertEqual(contractsByID["command.add-project"]?.kind, .icon)
        XCTAssertEqual(contractsByID["project.clear"]?.kind, .icon)
        XCTAssertEqual(contractsByID["command.git-status"]?.family, .commandPalette)
        XCTAssertEqual(contractsByID["command.git-status"]?.surface, "Command palette")
        XCTAssertEqual(contractsByID["command.git-status"]?.kind, .fullRow)
        XCTAssertEqual(contractsByID["command.disconnect-all"]?.family, .topBar)
        XCTAssertEqual(contractsByID["command.disconnect-all"]?.surface, "Top bar overflow")
        XCTAssertEqual(contractsByID["command.computer-use-setup"]?.family, .topBar)
        XCTAssertEqual(contractsByID["browser.comment"]?.action, .textInput)
        XCTAssertEqual(contractsByID["transcript.artifact-link"]?.action, .link)
        XCTAssertEqual(contractsByID["browser.new-tab"]?.action, .press)
        XCTAssertEqual(contractsByID["composer.input"]?.focusTarget, .composerMessage)
        XCTAssertEqual(contractsByID["command-palette.input"]?.focusTarget, .commandPaletteSearch)
        XCTAssertEqual(contractsByID["search.input"]?.focusTarget, .searchChats)
        XCTAssertEqual(contractsByID["shortcuts.search"]?.focusTarget, .shortcutsSearch)
        XCTAssertEqual(contractsByID["settings.text-entry"]?.focusTarget, .settingsTrustedRouterBaseURL)
        XCTAssertEqual(contractsByID["model-picker.search"]?.focusTarget, .modelPickerSearch)
        XCTAssertEqual(contractsByID["review.body"]?.focusTarget, .reviewBody)
        XCTAssertEqual(contractsByID["review.thread-reply"]?.focusTarget, .reviewThreadReply)
        XCTAssertEqual(contractsByID["terminal.command"]?.focusTarget, .terminalCommand)
        XCTAssertEqual(contractsByID["browser.address"]?.focusTarget, .browserAddress)
        XCTAssertEqual(contractsByID["browser.comment"]?.focusTarget, .browserComment)
        XCTAssertEqual(contractsByID["composer.send"]?.testID, "quillcode-send-button")
        XCTAssertEqual(contractsByID["command-palette.input"]?.testID, "quillcode-command-palette-input")
        XCTAssertEqual(contractsByID["browser.add-comment"]?.testID, "quillcode-browser-add-comment")
        XCTAssertEqual(contractsByID["extensions.add"]?.testID, "quillcode-extensions-add")
        XCTAssertEqual(contractsByID["extensions.close"]?.testID, "quillcode-extensions-close")
        XCTAssertEqual(contractsByID["memories.close"]?.testID, "quillcode-memories-close")
        XCTAssertEqual(contractsByID["automations.delete"]?.testID, "quillcode-automation-delete")
        XCTAssertEqual(contractsByID["automations.close"]?.testID, "quillcode-automations-close")
        XCTAssertEqual(contractsByID["project.clear"]?.testID, "quillcode-project-clear-button")
        XCTAssertEqual(contractsByID["command.add-project"]?.commandID, "add-project")
        XCTAssertEqual(contractsByID["command.new-chat"]?.commandID, "new-chat")
        XCTAssertEqual(contractsByID["command.settings"]?.commandID, "settings")
        XCTAssertEqual(probesByContractID["composer.send"]?.selectorKind, .testID)
        XCTAssertEqual(probesByContractID["composer.send"]?.selector, "quillcode-send-button")
        XCTAssertEqual(probesByContractID["command.new-chat"]?.selectorKind, .commandID)
        XCTAssertEqual(probesByContractID["command.new-chat"]?.selector, "new-chat")
        XCTAssertEqual(probesByContractID["project.clear"]?.selectorKind, .testID)
        XCTAssertEqual(probesByContractID["project.clear"]?.selector, "quillcode-project-clear-button")
        XCTAssertEqual(probesByContractID["terminal.command"]?.selectorKind, .testID)
        XCTAssertEqual(probesByContractID["terminal.command"]?.selector, "quillcode-terminal-command")
        XCTAssertGreaterThanOrEqual(probesByContractID["composer.send"]?.requiredMinWidth ?? 0, 40)
        XCTAssertGreaterThanOrEqual(probesByContractID["composer.send"]?.requiredMinHeight ?? 0, 40)
        XCTAssertEqual(contractsByID["memories.edit"]?.requiresUnblockedInterior, true)
        XCTAssertEqual(contractsByID["memories.edit"]?.requiresTactileFeedback, true)
        XCTAssertEqual(contractsByID["composer.input"]?.requiresTactileFeedback, false)
        XCTAssertEqual(contractsByID["composer.input"]?.allowsTextSelection, true)
        XCTAssertEqual(contractsByID["composer.send"]?.allowsTextSelection, false)
        XCTAssertEqual(contractsByID["model-picker.option"]?.allowsNestedInteractiveChildren, false)
        XCTAssertEqual(contractsByID["command-palette.input"]?.family, .commandPalette)
        XCTAssertEqual(contractsByID["search.result"]?.family, .search)
        XCTAssertEqual(contractsByID["menu-bar.action"]?.family, .menuBar)
        XCTAssertEqual(contractsByID["transcript.context-banner-action"]?.family, .contextBanner)
        XCTAssertEqual(contractsByID["command.new-chat"]?.label, "New chat")
        XCTAssertTrue((report.designSystemContracts + report.surfaceContracts).allSatisfy { !$0.id.isEmpty })
        XCTAssertTrue((report.designSystemContracts + report.surfaceContracts).allSatisfy { !$0.label.isEmpty })
        XCTAssertTrue((report.designSystemContracts + report.surfaceContracts).allSatisfy { !$0.source.isEmpty })
        XCTAssertTrue((report.designSystemContracts + report.surfaceContracts).allSatisfy { !$0.collisionScope.isEmpty })
    }

    func assertSurfacePolicies(_ report: QuillCodeNativeHitTargetAuditReport) {
        let policyByFamily = Dictionary(uniqueKeysWithValues: report.surfacePolicies.map { ($0.family, $0) })
        XCTAssertEqual(Set(policyByFamily[.composer]?.requiredKinds ?? []), Set([.textEntry, .icon, .capsule]))
        XCTAssertEqual(Set(policyByFamily[.composer]?.requiredActions ?? []), Set([.textInput, .press]))
        XCTAssertEqual(Set(policyByFamily[.composer]?.requiredFocusTargets ?? []), Set([.composerMessage]))
        XCTAssertEqual(Set(policyByFamily[.transcript]?.requiredKinds ?? []), Set([.icon, .link]))
        XCTAssertEqual(Set(policyByFamily[.transcript]?.allowedKinds ?? []), Set([.icon, .link, .capsule]))
        XCTAssertEqual(Set(policyByFamily[.sidebar]?.allowedKinds ?? []), Set([.fullRow, .icon]))
        XCTAssertEqual(Set(policyByFamily[.settings]?.requiredKinds ?? []), Set([.textEntry, .formAction]))
        XCTAssertEqual(Set(policyByFamily[.settings]?.requiredActions ?? []), Set([.textInput, .press]))
        XCTAssertEqual(Set(policyByFamily[.search]?.requiredFocusTargets ?? []), Set([.searchChats, .shortcutsSearch]))
        XCTAssertEqual(Set(policyByFamily[.browser]?.requiredKinds ?? []), Set([.textEntry, .textButton, .icon]))
        XCTAssertEqual(Set(policyByFamily[.browser]?.requiredActions ?? []), Set([.textInput, .press]))
        XCTAssertEqual(Set(policyByFamily[.browser]?.requiredFocusTargets ?? []), Set([.browserAddress, .browserComment]))
        XCTAssertEqual(Set(policyByFamily[.review]?.requiredKinds ?? []), Set([.textEntry, .segmentedControl, .fullRow, .formAction]))
        XCTAssertEqual(Set(policyByFamily[.review]?.requiredActions ?? []), Set([.textInput, .press]))
        XCTAssertEqual(Set(policyByFamily[.review]?.requiredFocusTargets ?? []), Set([.reviewBody, .reviewThreadReply]))
    }
}
