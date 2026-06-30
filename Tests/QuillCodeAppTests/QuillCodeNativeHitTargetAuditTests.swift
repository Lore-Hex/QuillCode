import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class QuillCodeNativeHitTargetAuditTests: XCTestCase {
    func testDesignSystemHitTargetSpecsUseNativeSemantics() {
        let cases: [(spec: QuillCodeHitTargetSpec, kind: QuillCodeNativeHitTargetKind, action: QuillCodeNativeHitTargetAction)] = [
            (.icon(), .icon, .press),
            (.textButton(), .textButton, .press),
            (.formAction(), .formAction, .press),
            (.textEntry(), .textEntry, .textInput),
            (.segmentedControl(), .segmentedControl, .press),
            (.adjustableControl(), .adjustableControl, .adjust),
            (.link(), .link, .link),
            (.switchRow(), .switchRow, .press),
            (.ownedGesture(), .ownedGesture, .ownedGesture),
            (.fullRow(), .fullRow, .press),
            (.capsule(), .capsule, .press)
        ]

        XCTAssertEqual(Set(cases.map(\.kind)), Set(QuillCodeNativeHitTargetKind.allCases))
        for hitTargetCase in cases {
            XCTAssertEqual(hitTargetCase.spec.kind, hitTargetCase.kind)
            XCTAssertEqual(hitTargetCase.spec.action, hitTargetCase.action.rawValue)
            XCTAssertFalse(hitTargetCase.spec.kind.renderedKind.isEmpty)
            XCTAssertTrue(hitTargetCase.spec.kind.renderedClassName.hasPrefix("hit-target-"))
            XCTAssertEqual(hitTargetCase.spec.allowsNestedInteractiveChildren, hitTargetCase.kind.allowsNestedInteractiveChildren)
            XCTAssertEqual(hitTargetCase.spec.requiresUnblockedInterior, hitTargetCase.kind.requiresUnblockedInterior)
            XCTAssertGreaterThanOrEqual(hitTargetCase.spec.requiredMinWidth, QuillCodeMetrics.minimumHitTarget)
            XCTAssertGreaterThanOrEqual(hitTargetCase.spec.requiredMinHeight, QuillCodeMetrics.minimumHitTarget)
            XCTAssertGreaterThanOrEqual(hitTargetCase.spec.minHeight, QuillCodeMetrics.minimumHitTarget)
        }
    }

    func testRenderedHitTargetKindsBridgeToNativeSemantics() {
        let expectedNativeKinds: [WorkspaceHTMLHitTargetKind: QuillCodeNativeHitTargetKind] = [
            .icon: .icon,
            .text: .textButton,
            .textEntry: .textEntry,
            .segmented: .segmentedControl,
            .row: .fullRow,
            .switchRow: .switchRow,
            .capsule: .capsule,
            .formAction: .formAction,
            .adjustable: .adjustableControl,
            .link: .link,
            .owned: .ownedGesture
        ]

        XCTAssertEqual(Set(WorkspaceHTMLHitTargetKind.allCases), Set(expectedNativeKinds.keys))
        XCTAssertEqual(
            Set(WorkspaceHTMLHitTargetKind.allCases.map(\.nativeKind)),
            Set(QuillCodeNativeHitTargetKind.allCases),
            "Rendered and native click-target APIs should cover the same semantic vocabulary."
        )

        for kind in WorkspaceHTMLHitTargetKind.allCases {
            XCTAssertEqual(kind.nativeKind, expectedNativeKinds[kind], kind.rawValue)
            XCTAssertEqual(kind.rawValue, kind.nativeKind.renderedKind, kind.rawValue)
            XCTAssertEqual(kind.className, kind.nativeKind.renderedClassName, kind.rawValue)
            XCTAssertEqual(kind.action, kind.nativeKind.action.rawValue, kind.rawValue)
        }
    }

    func testDesignSystemHitTargetFactoriesClampTinyInputsToTheMinimumTarget() {
        let tinyTargets: [(name: String, spec: QuillCodeHitTargetSpec)] = [
            ("icon", .icon(size: 12)),
            ("text button", .textButton(minWidth: 12, minHeight: 12)),
            ("form action", .formAction(minWidth: 12, minHeight: 12)),
            ("text entry", .textEntry(minWidth: nil, minHeight: 12)),
            ("segmented control", .segmentedControl(minHeight: 12)),
            ("adjustable control", .adjustableControl(minHeight: 12)),
            ("link", .link(minWidth: nil, minHeight: 12)),
            ("switch row", .switchRow(minHeight: 12)),
            ("owned gesture", .ownedGesture(minHeight: 12)),
            ("full row", .fullRow(minHeight: 12)),
            ("capsule", .capsule(minWidth: nil, minHeight: 12))
        ]

        for target in tinyTargets {
            XCTAssertEqual(target.spec.requiredMinWidth, QuillCodeMetrics.minimumHitTarget, target.name)
            XCTAssertEqual(target.spec.requiredMinHeight, QuillCodeMetrics.minimumHitTarget, target.name)
            XCTAssertGreaterThanOrEqual(target.spec.minWidth ?? 0, QuillCodeMetrics.minimumHitTarget, target.name)
            XCTAssertGreaterThanOrEqual(target.spec.minHeight, QuillCodeMetrics.minimumHitTarget, target.name)
            if let width = target.spec.width {
                XCTAssertGreaterThanOrEqual(width, QuillCodeMetrics.minimumHitTarget, target.name)
            }
            if let height = target.spec.height {
                XCTAssertGreaterThanOrEqual(height, QuillCodeMetrics.minimumHitTarget, target.name)
            }
        }
    }

    func testAuditCoversDesignSystemCommandsAndVisibleSecondaryPanes() {
        var surface = makeWorkspaceSurfaceWithRepresentativePanes()

        let report = QuillCodeNativeHitTargetAudit.report(for: surface)

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.minimumHitTarget, 44)
        XCTAssertEqual(report.minimumTargetClearance, 6)
        XCTAssertEqual(report.pressScale, 0.96)
        XCTAssertEqual(Set(report.designSystemContracts.map(\.kind)), Set(QuillCodeNativeHitTargetKind.allCases))
        XCTAssertEqual(report.missingDesignKinds, [])
        XCTAssertEqual(report.missingSurfaceFamilies, [])
        XCTAssertEqual(report.missingRequiredSurfaceKinds, [])
        XCTAssertEqual(report.missingRequiredSurfaceActions, [])
        XCTAssertEqual(report.missingRequiredSurfaceFocusTargets, [])
        XCTAssertEqual(report.unexpectedSurfaceKinds, [])
        XCTAssertEqual(report.unexpectedSurfaceActions, [])
        XCTAssertEqual(report.unexpectedSurfaceFocusTargets, [])
        XCTAssertEqual(report.missingRequiredFocusTargets, [])
        XCTAssertEqual(
            Set(report.coveredSurfaceFamilies),
            Set(QuillCodeInteractionSurfaceFamily.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(report.coveredFocusTargets),
            Set(QuillCodeNativeFocusTarget.allCases.map(\.rawValue))
        )
        XCTAssertEqual(report.missingRequiredCommandIDs, [])
        XCTAssertEqual(report.missingClickProbeContractIDs, [])
        XCTAssertEqual(report.clickProbeValidationIssues, [])
        XCTAssertEqual(report.duplicateContractIDs, [])
        XCTAssertEqual(report.validationIssues, [])
        XCTAssertEqual(Set(report.clickProbes.map(\.contractID)), Set(report.surfaceContracts.map(\.id)))

        let contractsByID = Dictionary(uniqueKeysWithValues: report.surfaceContracts.map { ($0.id, $0) })
        let probesByContractID = Dictionary(uniqueKeysWithValues: report.clickProbes.map { ($0.contractID, $0) })
        let commandContractIDs = Set(report.surfaceContracts.compactMap(\.commandID))
        XCTAssertEqual(
            commandContractIDs,
            Set(surface.commands.map(\.id)),
            "Every workspace command should declare a native click-target contract so command-palette, menu, and chrome routes cannot drift."
        )
        for requiredID in [
            "composer.input",
            "composer.send",
            "composer.model-picker",
            "composer.mode-picker",
            "top-bar.overflow",
            "sidebar.tools-menu",
            "project.clear",
            "workspace.chrome",
            "sidebar.thread-row",
            "sidebar.thread-action",
            "transcript.message-action",
            "transcript.artifact-link",
            "transcript.tool-card",
            "transcript.tool-card-action",
            "transcript.context-banner-action",
            "command-palette.input",
            "command-palette.result",
            "search.input",
            "search.result",
            "settings.text-entry",
            "settings.action",
            "model-picker.search",
            "model-picker.option",
            "model-picker.option-action",
            "review.body",
            "review.thread-reply",
            "review.mode",
            "review.file-row",
            "review.action",
            "secondary-pane.tab",
            "menu-bar.action",
            "command.add-project",
            "command.new-chat",
            "command.search",
            "command.toggle-extensions",
            "command.toggle-automations",
            "command.toggle-terminal",
            "command.toggle-browser",
            "command.toggle-memories",
            "command.toggle-activity",
            "command.command-palette",
            "command.keyboard-shortcuts",
            "command.settings",
            "terminal.command",
            "terminal.family-action",
            "terminal.run",
            "terminal.clear",
            "browser.address",
            "browser.family-action",
            "browser.family-icon",
            "browser.open",
            "browser.new-tab",
            "browser.comment",
            "browser.add-comment",
            "extensions.action",
            "extensions.reference-action",
            "extensions.mcp-reference",
            "memories.add",
            "memories.item-action",
            "memories.edit",
            "memories.delete",
            "automations.create",
            "automations.run",
            "automations.primary",
            "automations.delete",
            "transcript.thinking-trace"
        ] {
            XCTAssertNotNil(contractsByID[requiredID], requiredID)
        }

        XCTAssertEqual(contractsByID["extensions.mcp-reference"]?.kind, .capsule)
        XCTAssertEqual(contractsByID["extensions.reference-action"]?.kind, .capsule)
        XCTAssertEqual(contractsByID["transcript.artifact-link"]?.kind, .link)
        XCTAssertEqual(contractsByID["memories.edit"]?.kind, .icon)
        XCTAssertEqual(contractsByID["memories.item-action"]?.kind, .icon)
        XCTAssertEqual(contractsByID["automations.create"]?.kind, .formAction)
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
        XCTAssertEqual(contractsByID["automations.delete"]?.testID, "quillcode-automation-delete")
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
        XCTAssertGreaterThanOrEqual(probesByContractID["composer.send"]?.requiredMinWidth ?? 0, 44)
        XCTAssertGreaterThanOrEqual(probesByContractID["composer.send"]?.requiredMinHeight ?? 0, 44)
        XCTAssertEqual(
            Set(probesByContractID["composer.send"]?.samplePoints.map(\.name) ?? []),
            Set([
                "center",
                "leading-edge",
                "leading-interior",
                "trailing-edge",
                "trailing-interior",
                "top-edge",
                "top-interior",
                "bottom-edge",
                "bottom-interior"
            ])
        )
        let expectedSamplePoints = [
            QuillCodeNativeHitTargetProbePoint(name: "center", x: 0.5, y: 0.5),
            QuillCodeNativeHitTargetProbePoint(name: "leading-edge", x: 0.08, y: 0.5),
            QuillCodeNativeHitTargetProbePoint(name: "leading-interior", x: 0.18, y: 0.5),
            QuillCodeNativeHitTargetProbePoint(name: "trailing-edge", x: 0.92, y: 0.5),
            QuillCodeNativeHitTargetProbePoint(name: "trailing-interior", x: 0.82, y: 0.5),
            QuillCodeNativeHitTargetProbePoint(name: "top-edge", x: 0.5, y: 0.08),
            QuillCodeNativeHitTargetProbePoint(name: "top-interior", x: 0.5, y: 0.18),
            QuillCodeNativeHitTargetProbePoint(name: "bottom-edge", x: 0.5, y: 0.92),
            QuillCodeNativeHitTargetProbePoint(name: "bottom-interior", x: 0.5, y: 0.82)
        ]
        XCTAssertEqual(probesByContractID["composer.send"]?.samplePoints, expectedSamplePoints)
        for probe in report.clickProbes {
            let contract = contractsByID[probe.contractID]
            XCTAssertFalse(probe.selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThanOrEqual(probe.requiredMinWidth, 44)
            XCTAssertGreaterThanOrEqual(probe.requiredMinHeight, 44)
            XCTAssertGreaterThanOrEqual(probe.requiredPeerClearance, 6)
            XCTAssertFalse(probe.collisionScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(probe.collisionScope, contract?.collisionScope)
            XCTAssertEqual(probe.allowsNestedInteractiveChildren, contract?.allowsNestedInteractiveChildren)
            XCTAssertEqual(probe.requiresUnblockedInterior, contract?.requiresUnblockedInterior)
            XCTAssertEqual(probe.samplePoints, expectedSamplePoints)
            XCTAssertTrue(probe.samplePoints.allSatisfy { point in
                point.x > 0 && point.x < 1 && point.y > 0 && point.y < 1
            })
        }
        XCTAssertTrue(report.surfaceContracts.allSatisfy { contract in
            contract.focusTarget != nil || contract.testID?.isEmpty == false || contract.commandID?.isEmpty == false
        })
        XCTAssertEqual(contractsByID["memories.edit"]?.requiresUnblockedInterior, true)
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
        let policyByFamily = Dictionary(uniqueKeysWithValues: report.surfacePolicies.map { ($0.family, $0) })
        XCTAssertEqual(
            Set(policyByFamily[.composer]?.requiredKinds ?? []),
            Set([.textEntry, .icon, .capsule])
        )
        XCTAssertEqual(
            Set(policyByFamily[.composer]?.requiredActions ?? []),
            Set([.textInput, .press])
        )
        XCTAssertEqual(
            Set(policyByFamily[.composer]?.requiredFocusTargets ?? []),
            Set([.composerMessage])
        )
        XCTAssertEqual(
            Set(policyByFamily[.transcript]?.requiredKinds ?? []),
            Set([.icon, .link])
        )
        XCTAssertEqual(
            Set(policyByFamily[.transcript]?.allowedKinds ?? []),
            Set([.icon, .link, .capsule])
        )
        XCTAssertEqual(
            Set(policyByFamily[.sidebar]?.allowedKinds ?? []),
            Set([.fullRow, .icon])
        )
        XCTAssertEqual(
            Set(policyByFamily[.settings]?.requiredKinds ?? []),
            Set([.textEntry, .formAction])
        )
        XCTAssertEqual(
            Set(policyByFamily[.settings]?.requiredActions ?? []),
            Set([.textInput, .press])
        )
        XCTAssertEqual(
            Set(policyByFamily[.browser]?.requiredKinds ?? []),
            Set([.textEntry, .textButton, .icon])
        )
        XCTAssertEqual(
            Set(policyByFamily[.browser]?.requiredActions ?? []),
            Set([.textInput, .press])
        )
        XCTAssertEqual(
            Set(policyByFamily[.browser]?.requiredFocusTargets ?? []),
            Set([.browserAddress, .browserComment])
        )
        XCTAssertEqual(
            Set(policyByFamily[.review]?.requiredKinds ?? []),
            Set([.textEntry, .segmentedControl, .fullRow, .formAction])
        )
        XCTAssertEqual(
            Set(policyByFamily[.review]?.requiredActions ?? []),
            Set([.textInput, .press])
        )
        XCTAssertEqual(
            Set(policyByFamily[.review]?.requiredFocusTargets ?? []),
            Set([.reviewBody, .reviewThreadReply])
        )

        surface.commands.removeAll { $0.id == "toggle-extensions" }
        let missingReport = QuillCodeNativeHitTargetAudit.report(for: surface)
        XCTAssertEqual(missingReport.missingRequiredCommandIDs, ["toggle-extensions"])
        XCTAssertFalse(missingReport.isValid)
    }

    func testSwiftInteractiveControlsDeclareHitTargetContractAtSource() throws {
        let sourceRoot = packageRoot()
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("QuillCodeApp", isDirectory: true)
        let issues = try swiftSourceFiles(in: sourceRoot)
            .flatMap { try sourceHitTargetContractIssues(in: $0, sourceRoot: sourceRoot) }
            .sorted()

        XCTAssertEqual(issues, [])
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

    func testAuditReportRejectsBlankMetadataDuplicateIDsAndNarrowIcons() {
        let invalidContract = QuillCodeNativeHitTargetContract(
            id: "",
            family: .topBar,
            surface: "",
            label: "",
            kind: .icon,
            minWidth: nil,
            minHeight: 20,
            testID: "",
            commandID: "",
            source: ""
        )

        XCTAssertTrue(invalidContract.validationIssues.contains("hit target contract has an empty id"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty surface label"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty accessible label"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty source"))
        XCTAssertEqual(invalidContract.collisionScope, "top-bar")
        XCTAssertTrue(invalidContract.validationIssues.contains(" icon target should declare an explicit minimum width"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" minHeight 20.0 is below 44.0"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty test id"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty command id"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" does not declare a stable test id, command id, or focus target"))

        let blankScopeContract = QuillCodeNativeHitTargetContract(
            id: "blank.scope",
            family: .topBar,
            surface: "Top bar",
            label: "More",
            kind: .icon,
            minWidth: 44,
            collisionScope: "",
            testID: "quillcode-more",
            source: "SwiftUI"
        )
        XCTAssertTrue(blankScopeContract.validationIssues.contains("blank.scope has an empty collision scope"))

        let report = QuillCodeNativeHitTargetAuditReport(
            minimumHitTarget: 44,
            minimumTargetClearance: 6,
            pressScale: 0.96,
            surfacePolicies: [
                QuillCodeNativeSurfaceTargetPolicy(family: .topBar, requiredKinds: [.icon])
            ],
            designSystemContracts: [],
            surfaceContracts: [invalidContract],
            clickProbes: [],
            missingDesignKinds: [],
            coveredSurfaceFamilies: [],
            missingSurfaceFamilies: [],
            missingRequiredSurfaceKinds: ["top-bar:icon"],
            coveredFocusTargets: [],
            missingRequiredFocusTargets: [],
            missingRequiredSurfaceActions: ["top-bar:press"],
            missingRequiredSurfaceFocusTargets: ["composer:composer.message"],
            unexpectedSurfaceKinds: ["top-bar:top-bar.overflow:textButton"],
            unexpectedSurfaceActions: ["top-bar:top-bar.overflow:link"],
            unexpectedSurfaceFocusTargets: ["composer:composer.input:composer.message"],
            missingRequiredCommandIDs: [],
            missingClickProbeContractIDs: ["top-bar.overflow"],
            clickProbeValidationIssues: ["top-bar.overflow click probe selector drift"],
            duplicateContractIDs: ["top-bar.overflow"],
            validationIssues: invalidContract.validationIssues
        )

        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.duplicateContractIDs, ["top-bar.overflow"])
        XCTAssertEqual(report.dictionary["missingRequiredSurfaceKinds"] as? [String], ["top-bar:icon"])
        XCTAssertEqual(report.dictionary["missingRequiredSurfaceActions"] as? [String], ["top-bar:press"])
        XCTAssertEqual(report.dictionary["missingRequiredSurfaceFocusTargets"] as? [String], ["composer:composer.message"])
        XCTAssertEqual(report.dictionary["unexpectedSurfaceKinds"] as? [String], ["top-bar:top-bar.overflow:textButton"])
        XCTAssertEqual(report.dictionary["unexpectedSurfaceActions"] as? [String], ["top-bar:top-bar.overflow:link"])
        XCTAssertEqual(report.dictionary["unexpectedSurfaceFocusTargets"] as? [String], ["composer:composer.input:composer.message"])
        XCTAssertEqual(report.dictionary["missingClickProbeContractIDs"] as? [String], ["top-bar.overflow"])
        XCTAssertEqual(report.dictionary["clickProbeValidationIssues"] as? [String], ["top-bar.overflow click probe selector drift"])
        XCTAssertEqual(report.dictionary["duplicateContractIDs"] as? [String], ["top-bar.overflow"])
        XCTAssertEqual((invalidContract.dictionary["testID"] as? String), "")
        XCTAssertEqual((invalidContract.dictionary["commandID"] as? String), "")
        XCTAssertEqual((invalidContract.dictionary["collisionScope"] as? String), "top-bar")
    }

    func testClickProbeValidationRejectsSelectorSemanticAndGeometryDrift() {
        let contract = QuillCodeNativeHitTargetContract(
            id: "composer.send",
            family: .composer,
            surface: "Composer",
            label: "Send message",
            kind: .icon,
            minWidth: 44,
            testID: "quillcode-send-button",
            source: "SwiftUI"
        )
        let probe = QuillCodeNativeHitTargetProbe(
            contractID: "composer.send",
            family: .topBar,
            label: "Send message",
            kind: .textButton,
            action: .link,
            allowsNestedInteractiveChildren: true,
            requiresUnblockedInterior: false,
            selectorKind: .testID,
            selector: "quillcode-wrong-button",
            requiredMinWidth: 20,
            requiredMinHeight: 20,
            requiredPeerClearance: 2,
            samplePoints: [
                QuillCodeNativeHitTargetProbePoint(name: "center", x: 0.5, y: 0.5),
                QuillCodeNativeHitTargetProbePoint(name: "leading-interior", x: 0.2, y: 0.5),
                QuillCodeNativeHitTargetProbePoint(name: "", x: 0.5, y: 0.5),
                QuillCodeNativeHitTargetProbePoint(name: "outside", x: 1.2, y: 0.5)
            ]
        )

        let issues = QuillCodeNativeHitTargetAudit.validateClickProbes(
            contracts: [contract],
            probes: [probe]
        )

        XCTAssertTrue(issues.contains("composer.send click probe selector quillcode-wrong-button does not match test-id contract selector"))
        XCTAssertTrue(issues.contains("composer.send click probe kind textButton does not match icon"))
        XCTAssertTrue(issues.contains("composer.send click probe action link does not match press"))
        XCTAssertTrue(issues.contains("composer.send click probe family top-bar does not match composer"))
        XCTAssertTrue(issues.contains("composer.send click probe collision scope does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe nested-child policy does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe interior-blocking policy does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe requiredMinWidth 20.0 is below 44.0"))
        XCTAssertTrue(issues.contains("composer.send click probe requiredMinHeight 20.0 is below 44.0"))
        XCTAssertTrue(issues.contains("composer.send click probe requiredPeerClearance 2.0 is below 6.0"))
        XCTAssertTrue(issues.contains("composer.send click probe has an unnamed sample point"))
        XCTAssertTrue(issues.contains("composer.send click probe has unknown sample point outside"))
        XCTAssertTrue(issues.contains("composer.send click probe sample point leading-interior has unexpected coordinates"))
        XCTAssertTrue(issues.contains("composer.send click probe sample point outside is outside the target interior"))
        XCTAssertTrue(issues.contains("composer.send click probe is missing sample points: bottom-edge, bottom-interior, leading-edge, top-edge, top-interior, trailing-edge, trailing-interior"))
    }

    private func makeWorkspaceSurfaceWithRepresentativePanes() -> WorkspaceSurface {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Native target audit", messages: [
            .init(role: .user, content: "run whoami")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))
        var surface = model.surface()
        surface.transcript.thinking = TranscriptThinkingSurface(
            id: "thinking-native-target-audit",
            title: "Thinking",
            subtitle: "Running: host.shell.run running",
            traceLines: [
                "Queued: host.shell.run queued",
                "Running: host.shell.run running"
            ]
        )

        surface.terminal.isVisible = true
        surface.terminal.draft = "pwd"
        surface.terminal.entries = [
            TerminalCommandSurface(entry: TerminalCommandState(
                command: "pwd",
                stdout: "/tmp/QuillCode\n",
                stderr: "",
                exitCode: 0,
                ok: true
            ))
        ]

        var browser = BrowserState(isVisible: true, addressDraft: "localhost:5173")
        browser.comments = [
            BrowserCommentState(url: "http://localhost:5173", text: "Looks good")
        ]
        surface.browser = BrowserSurface(browser: browser)

        surface.extensions = WorkspaceExtensionsSurface(
            isVisible: true,
            manifests: [mcpManifest()],
            mcpServerStatuses: ["mcp:filesystem": .ready],
            mcpServerProbeSummaries: ["mcp:filesystem": mcpProbe()]
        )

        surface.memories = WorkspaceMemoriesSurface(
            isVisible: true,
            notes: [
                MemoryNote(
                    id: "global-preferences",
                    scope: .global,
                    title: "Preferences",
                    content: "Prefer small reviewable changes.",
                    relativePath: "memories/preferences.md",
                    byteCount: 32
                )
            ]
        )

        surface.automations = WorkspaceAutomationsSurface(
            isVisible: true,
            automations: [automation()],
            createThreadFollowUpCommand: .automationCreateThreadFollowUp(isEnabled: true),
            createWorkspaceScheduleCommand: .automationCreateWorkspaceSchedule(isEnabled: true)
        )

        return surface
    }

    private func mcpManifest() -> ProjectExtensionManifest {
        ProjectExtensionManifest(
            id: "mcp:filesystem",
            kind: .mcpServer,
            name: "Filesystem",
            summary: "Expose workspace files.",
            relativePath: ".quillcode/mcp/filesystem.json",
            transport: .stdio,
            launchExecutable: "quill-mcp",
            launchCommand: "quill-mcp --root .",
            updateCommand: "quill-mcp update"
        )
    }

    private func mcpProbe() -> MCPServerProbeSummary {
        MCPServerProbeSummary(
            protocolVersion: "2024-11-05",
            serverName: "Filesystem",
            serverVersion: "1.0",
            toolDescriptors: [
                MCPToolDescriptor(name: "read_file", description: "Read a file", requiredArguments: ["path"])
            ],
            resourceNames: ["README"],
            resourceURIs: ["file://README.md"],
            promptNames: ["review"]
        )
    }

    private func automation() -> QuillAutomation {
        QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            title: "Morning check",
            detail: "Check the workspace.",
            kind: .workspaceSchedule,
            status: .active,
            scheduleKind: .cron,
            scheduleDescription: "Every morning",
            nextRunAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func packageRoot(filePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftSourceFiles(in directory: URL) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys)
        )
        guard let enumerator else { return [] }

        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true, url.pathExtension == "swift" else { return nil }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    private func sourceHitTargetContractIssues(in fileURL: URL, sourceRoot: URL) throws -> [String] {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = source.components(separatedBy: .newlines)
        let interactivePattern = try NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9_])(Button|Link|NavigationLink|Menu|DisclosureGroup|TextField|SecureField|TextEditor|Picker|Toggle|Slider|Stepper)\s*(?:\(|\{)"#
        )
        let geometryMarkers = [
            ".quillCodeTextButtonTarget",
            ".quillCodeFormActionTarget",
            ".quillCodeTextEntryTarget",
            ".quillCodeSegmentedControlTarget",
            ".quillCodeAdjustableControlTarget",
            ".quillCodeLinkTarget",
            ".quillCodeSwitchRowTarget",
            ".quillCodeOwnedGestureTarget",
            ".quillCodeIconButtonTarget",
            ".quillCodeFullRowButtonTarget",
            ".quillCodeCapsuleButtonTarget"
        ]
        let platformMenuItemMarker = ".quillCodePlatformMenuItemTarget"

        return lines.enumerated().compactMap { index, line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = interactivePattern.firstMatch(in: line, range: range),
                  let kindRange = Range(match.range(at: 1), in: line) else { return nil }
            let kind = String(line[kindRange])
            let snippet = interactiveControlSnippet(
                from: index,
                in: lines,
                interactivePattern: interactivePattern
            )
            let markers = kind == "Menu"
                ? geometryMarkers
                : geometryMarkers + [platformMenuItemMarker]
            let relativePath = fileURL.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            let sourceLocation = "\(relativePath):\(index + 1)"
            let controlSummary = "`\(line.trimmingCharacters(in: .whitespaces))`"
            guard markers.contains(where: snippet.contains) else {
                return "\(sourceLocation) missing QuillCode hit-target marker near \(controlSummary)"
            }
            if ["Button", "Menu"].contains(kind),
               !snippet.contains(platformMenuItemMarker),
               !snippet.contains(".buttonStyle(QuillCodePressableButtonStyle"),
               !snippet.contains(".buttonStyle(QuillCodeActionButtonStyle") {
                return "\(sourceLocation) missing QuillCode press/action button style near \(controlSummary)"
            }
            return nil
        }
    }

    private func interactiveControlSnippet(
        from startIndex: Int,
        in lines: [String],
        interactivePattern: NSRegularExpression
    ) -> String {
        let startIndent = leadingWhitespaceCount(lines[startIndex])
        var endIndex = min(startIndex + 64, lines.endIndex)
        if startIndex + 1 < endIndex {
            for candidateIndex in (startIndex + 1)..<endIndex {
                let line = lines[candidateIndex]
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                let startsPeerControl = interactivePattern.firstMatch(in: line, range: range) != nil
                    && leadingWhitespaceCount(line) <= startIndent
                if startsPeerControl {
                    endIndex = candidateIndex
                    break
                }
            }
        }
        return lines[startIndex..<endIndex].joined(separator: "\n")
    }

    private func leadingWhitespaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }
}
