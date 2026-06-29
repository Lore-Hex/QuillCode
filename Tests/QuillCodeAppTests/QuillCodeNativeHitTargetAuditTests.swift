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
            XCTAssertEqual(hitTargetCase.spec.allowsNestedInteractiveChildren, hitTargetCase.kind.allowsNestedInteractiveChildren)
            XCTAssertEqual(hitTargetCase.spec.requiresUnblockedInterior, hitTargetCase.kind.requiresUnblockedInterior)
            XCTAssertGreaterThanOrEqual(hitTargetCase.spec.minHeight, QuillCodeMetrics.minimumHitTarget)
        }
    }

    func testAuditCoversDesignSystemCommandsAndVisibleSecondaryPanes() {
        var surface = makeWorkspaceSurfaceWithRepresentativePanes()

        let report = QuillCodeNativeHitTargetAudit.report(for: surface)

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.minimumHitTarget, 44)
        XCTAssertEqual(report.pressScale, 0.96)
        XCTAssertEqual(Set(report.designSystemContracts.map(\.kind)), Set(QuillCodeNativeHitTargetKind.allCases))
        XCTAssertEqual(report.missingDesignKinds, [])
        XCTAssertEqual(report.missingSurfaceFamilies, [])
        XCTAssertEqual(report.missingRequiredSurfaceKinds, [])
        XCTAssertEqual(report.missingRequiredSurfaceActions, [])
        XCTAssertEqual(report.missingRequiredSurfaceFocusTargets, [])
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
        for requiredID in [
            "composer.input",
            "composer.send",
            "composer.model-picker",
            "composer.mode-picker",
            "top-bar.overflow",
            "sidebar.tools-menu",
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
        XCTAssertEqual(contractsByID["command.new-chat"]?.commandID, "new-chat")
        XCTAssertEqual(contractsByID["command.settings"]?.commandID, "settings")
        XCTAssertEqual(probesByContractID["composer.send"]?.selectorKind, .testID)
        XCTAssertEqual(probesByContractID["composer.send"]?.selector, "quillcode-send-button")
        XCTAssertEqual(probesByContractID["command.new-chat"]?.selectorKind, .commandID)
        XCTAssertEqual(probesByContractID["command.new-chat"]?.selector, "new-chat")
        XCTAssertEqual(probesByContractID["terminal.command"]?.selectorKind, .testID)
        XCTAssertEqual(probesByContractID["terminal.command"]?.selector, "quillcode-terminal-command")
        XCTAssertGreaterThanOrEqual(probesByContractID["composer.send"]?.requiredMinWidth ?? 0, 44)
        XCTAssertGreaterThanOrEqual(probesByContractID["composer.send"]?.requiredMinHeight ?? 0, 44)
        XCTAssertEqual(
            Set(probesByContractID["composer.send"]?.samplePoints.map(\.name) ?? []),
            Set(["center", "leading-interior", "trailing-interior", "top-interior", "bottom-interior"])
        )
        let expectedSamplePoints = [
            QuillCodeNativeHitTargetProbePoint(name: "center", x: 0.5, y: 0.5),
            QuillCodeNativeHitTargetProbePoint(name: "leading-interior", x: 0.18, y: 0.5),
            QuillCodeNativeHitTargetProbePoint(name: "trailing-interior", x: 0.82, y: 0.5),
            QuillCodeNativeHitTargetProbePoint(name: "top-interior", x: 0.5, y: 0.18),
            QuillCodeNativeHitTargetProbePoint(name: "bottom-interior", x: 0.5, y: 0.82)
        ]
        XCTAssertEqual(probesByContractID["composer.send"]?.samplePoints, expectedSamplePoints)
        for probe in report.clickProbes {
            let contract = contractsByID[probe.contractID]
            XCTAssertFalse(probe.selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThanOrEqual(probe.requiredMinWidth, 44)
            XCTAssertGreaterThanOrEqual(probe.requiredMinHeight, 44)
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

    func testAuditCoversEverySurfaceFamilyForPlainWorkspaceSnapshot() {
        let report = QuillCodeNativeHitTargetAudit.report(for: QuillCodeWorkspaceModel().surface())

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.missingSurfaceFamilies, [])
        XCTAssertEqual(report.missingRequiredSurfaceKinds, [])
        XCTAssertEqual(report.missingRequiredSurfaceActions, [])
        XCTAssertEqual(report.missingRequiredSurfaceFocusTargets, [])
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
        XCTAssertTrue(invalidContract.validationIssues.contains(" icon target should declare an explicit minimum width"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" minHeight 20.0 is below 44.0"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty test id"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" has an empty command id"))
        XCTAssertTrue(invalidContract.validationIssues.contains(" does not declare a stable test id, command id, or focus target"))

        let report = QuillCodeNativeHitTargetAuditReport(
            minimumHitTarget: 44,
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
        XCTAssertEqual(report.dictionary["missingClickProbeContractIDs"] as? [String], ["top-bar.overflow"])
        XCTAssertEqual(report.dictionary["clickProbeValidationIssues"] as? [String], ["top-bar.overflow click probe selector drift"])
        XCTAssertEqual(report.dictionary["duplicateContractIDs"] as? [String], ["top-bar.overflow"])
        XCTAssertEqual((invalidContract.dictionary["testID"] as? String), "")
        XCTAssertEqual((invalidContract.dictionary["commandID"] as? String), "")
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
        XCTAssertTrue(issues.contains("composer.send click probe nested-child policy does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe interior-blocking policy does not match contract"))
        XCTAssertTrue(issues.contains("composer.send click probe requiredMinWidth 20.0 is below 44.0"))
        XCTAssertTrue(issues.contains("composer.send click probe requiredMinHeight 20.0 is below 44.0"))
        XCTAssertTrue(issues.contains("composer.send click probe has an unnamed sample point"))
        XCTAssertTrue(issues.contains("composer.send click probe has unknown sample point outside"))
        XCTAssertTrue(issues.contains("composer.send click probe sample point leading-interior has unexpected coordinates"))
        XCTAssertTrue(issues.contains("composer.send click probe sample point outside is outside the target interior"))
        XCTAssertTrue(issues.contains("composer.send click probe is missing sample points: bottom-interior, top-interior, trailing-interior"))
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
}
