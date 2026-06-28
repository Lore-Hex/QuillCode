import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class QuillCodeNativeHitTargetAuditTests: XCTestCase {
    func testAuditCoversDesignSystemCommandsAndVisibleSecondaryPanes() {
        var surface = makeWorkspaceSurfaceWithRepresentativePanes()

        let report = QuillCodeNativeHitTargetAudit.report(for: surface)

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.minimumHitTarget, 44)
        XCTAssertEqual(report.pressScale, 0.96)
        XCTAssertEqual(Set(report.designSystemContracts.map(\.kind)), Set(QuillCodeNativeHitTargetKind.allCases))
        XCTAssertEqual(report.missingDesignKinds, [])
        XCTAssertEqual(report.missingSurfaceFamilies, [])
        XCTAssertEqual(
            Set(report.coveredSurfaceFamilies),
            Set(QuillCodeInteractionSurfaceFamily.allCases.map(\.rawValue))
        )
        XCTAssertEqual(report.missingRequiredCommandIDs, [])
        XCTAssertEqual(report.validationIssues, [])

        let contractsByID = Dictionary(uniqueKeysWithValues: report.surfaceContracts.map { ($0.id, $0) })
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
            "transcript.tool-card",
            "transcript.tool-card-action",
            "transcript.context-banner-action",
            "command-palette.input",
            "command-palette.result",
            "search.input",
            "search.result",
            "settings.text-entry",
            "settings.action",
            "model-picker.option",
            "model-picker.option-action",
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
            "terminal.run",
            "terminal.clear",
            "browser.address",
            "browser.open",
            "browser.new-tab",
            "browser.comment",
            "browser.add-comment",
            "extensions.action",
            "extensions.mcp-reference",
            "memories.add",
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
        XCTAssertEqual(contractsByID["memories.edit"]?.kind, .icon)
        XCTAssertEqual(contractsByID["automations.create"]?.kind, .formAction)
        XCTAssertEqual(contractsByID["browser.comment"]?.kind, .textEntry)
        XCTAssertEqual(contractsByID["transcript.thinking-trace"]?.kind, .capsule)
        XCTAssertEqual(contractsByID["browser.comment"]?.action, .textInput)
        XCTAssertEqual(contractsByID["browser.new-tab"]?.action, .press)
        XCTAssertEqual(contractsByID["memories.edit"]?.requiresUnblockedInterior, true)
        XCTAssertEqual(contractsByID["model-picker.option"]?.allowsNestedInteractiveChildren, false)
        XCTAssertEqual(contractsByID["command-palette.input"]?.family, .commandPalette)
        XCTAssertEqual(contractsByID["search.result"]?.family, .search)
        XCTAssertEqual(contractsByID["menu-bar.action"]?.family, .menuBar)
        XCTAssertEqual(contractsByID["transcript.context-banner-action"]?.family, .contextBanner)

        surface.commands.removeAll { $0.id == "toggle-extensions" }
        let missingReport = QuillCodeNativeHitTargetAudit.report(for: surface)
        XCTAssertEqual(missingReport.missingRequiredCommandIDs, ["toggle-extensions"])
        XCTAssertFalse(missingReport.isValid)
    }

    func testAuditCoversEverySurfaceFamilyForPlainWorkspaceSnapshot() {
        let report = QuillCodeNativeHitTargetAudit.report(for: QuillCodeWorkspaceModel().surface())

        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.missingSurfaceFamilies, [])
        XCTAssertEqual(
            Set(report.coveredSurfaceFamilies),
            Set(QuillCodeInteractionSurfaceFamily.allCases.map(\.rawValue))
        )
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
