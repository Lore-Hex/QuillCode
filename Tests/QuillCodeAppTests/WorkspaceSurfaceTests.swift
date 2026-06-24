import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

@MainActor
final class WorkspaceSurfaceTests: XCTestCase {
    func testSurfaceIncludesTopBarSidebarComposerAndCommands() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Run whoami", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .assistant, content: "Output:\njperla")
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))
        model.setDraft("git status")

        let surface = model.surface()

        XCTAssertEqual(surface.topBar.primaryTitle, "Run whoami")
        XCTAssertEqual(surface.topBar.modelLabel, TrustedRouterDefaults.fastModelDisplayName)
        XCTAssertEqual(surface.topBar.selectedModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertTrue(surface.topBar.modelCategories.contains { $0.category == "Recommended" })
        XCTAssertTrue(surface.topBar.modelCategories.flatMap(\.models).contains { $0.id == TrustedRouterDefaults.defaultModel && $0.isSelected })
        let recommendedModelIDs = surface.topBar.modelCategories
            .first { $0.category == "Recommended" }?
            .models
            .prefix(3)
            .map(\.id) ?? []
        XCTAssertEqual(recommendedModelIDs, TrustedRouterDefaults.recommendedModelIDs)
        let defaultOption = surface.topBar.modelCategories
            .flatMap(\.models)
            .first { $0.id == TrustedRouterDefaults.defaultModel }
        XCTAssertEqual(defaultOption?.metadataSummary, "Fast everyday agent")
        XCTAssertTrue(defaultOption?.metadataDetails.contains("Default model") == true)
        XCTAssertTrue(defaultOption?.metadataDetails.contains("Recommended by QuillCode") == true)
        XCTAssertEqual(surface.topBar.modeLabel, "Auto")
        XCTAssertEqual(surface.topBar.instructionLabel, "No project instructions")
        XCTAssertEqual(surface.topBar.instructionSources, [])
        XCTAssertEqual(surface.topBar.memoryLabel, "No memories")
        XCTAssertEqual(surface.topBar.memorySources, [])
        XCTAssertEqual(surface.projects.items.count, 1)
        XCTAssertEqual(surface.projects.items[0].name, "QuillCode")
        XCTAssertEqual(surface.projects.items[0].path, "/tmp/QuillCode")
        XCTAssertEqual(surface.projects.items[0].connectionKindLabel, "Local")
        XCTAssertFalse(surface.projects.items[0].isRemote)
        XCTAssertTrue(surface.projects.items[0].isSelected)
        XCTAssertEqual(surface.projects.items[0].actions.map(\.kind), [.newChat, .refreshContext, .rename, .remove])
        XCTAssertTrue(surface.projects.items[0].actions.allSatisfy(\.isEnabled))
        XCTAssertEqual(surface.sidebar.items.count, 1)
        XCTAssertEqual(surface.sidebar.items[0].title, "Run whoami")
        XCTAssertTrue(surface.sidebar.items[0].isSelected)
        XCTAssertFalse(surface.sidebar.items[0].isBulkSelected)
        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectionLabel, "No chats selected")
        XCTAssertEqual(surface.sidebar.bulkActions.map(\.kind), [.select])
        XCTAssertEqual(surface.sidebar.items[0].actions.map(\.kind), [.rename, .duplicate, .pin, .archive, .delete])
        XCTAssertEqual(surface.transcript.messages.count, 2)
        XCTAssertEqual(surface.composer.placeholder, "Message QuillCode")
        XCTAssertTrue(surface.composer.canSend)
        XCTAssertEqual(surface.composer.slashSuggestions, [])
        XCTAssertEqual(surface.commands.map(\.id), [
            "new-chat",
            "thread-rename",
            "thread-duplicate",
            "thread-archive",
            "thread-unarchive",
            "thread-delete",
            "thread-selection-start",
            "thread-selection-select-all",
            "thread-selection-clear",
            "thread-bulk-pin",
            "thread-bulk-unpin",
            "thread-bulk-archive",
            "thread-bulk-unarchive",
            "thread-bulk-delete",
            "fork-from-last",
            "compact-context",
            "retry-last-turn",
            "search",
            "find-in-chat",
            "add-project",
            "add-ssh-project",
            "project-new-chat",
            "project-refresh-context",
            "project-rename",
            "project-remove",
            "toggle-terminal",
            "terminal-clear",
            "toggle-browser",
            "browser-back",
            "browser-forward",
            "browser-reload",
            "toggle-activity",
            "toggle-automations",
            "automation-create-thread-follow-up",
            "automation-create-workspace-schedule",
            "automation-create-thread-follow-up-after:600",
            "automation-create-thread-follow-up-after:3600",
            "automation-create-thread-follow-up-tomorrow",
            "automation-create-thread-follow-up-every:daily",
            "automation-create-workspace-schedule-after:600",
            "automation-create-workspace-schedule-after:3600",
            "automation-create-workspace-schedule-tomorrow",
            "automation-create-workspace-schedule-every:daily",
            "toggle-memories",
            "memory-add",
            "toggle-extensions",
            "git-status",
            "git-diff",
            "git-pr-create",
            "git-pr-view",
            "git-pr-checks",
            "git-pr-diff",
            "git-pr-checkout",
            "git-pr-reviewers",
            "git-pr-comment",
            "git-pr-review",
            "git-pr-labels",
            "git-pr-merge",
            "git-worktree-list",
            "git-worktree-create",
            "git-worktree-remove",
            "stop-all",
            "settings",
            "command-palette",
            "keyboard-shortcuts",
            "computer-use-setup",
            "computer-use-open-screen-recording",
            "computer-use-open-accessibility",
            "computer-use-refresh"
        ])
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "find-in-chat" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.settings.apiBaseURL, TrustedRouterDefaults.defaultAPIBaseURL)
        XCTAssertFalse(surface.settings.developerOverrideEnabled)
        XCTAssertFalse(surface.settings.hasStoredAPIKey)
        XCTAssertEqual(surface.settings.authMode, .oauth)
        XCTAssertEqual(surface.settings.signInURL, TrustedRouterDefaults.loopbackCallbackURL)
        XCTAssertEqual(surface.settings.apiKeyStatusLabel, "Not signed in")
        XCTAssertEqual(surface.settings.computerUseStatus.message, "Needs Screen Recording + Accessibility")
        XCTAssertEqual(surface.settings.computerUseSetupCommand.id, "computer-use-setup")
        XCTAssertEqual(surface.settings.computerUseScreenRecordingCommand.id, "computer-use-open-screen-recording")
        XCTAssertEqual(surface.settings.computerUseAccessibilityCommand.id, "computer-use-open-accessibility")
        XCTAssertEqual(surface.settings.computerUseRefreshCommand.id, "computer-use-refresh")
        XCTAssertEqual(surface.settings.computerUseStatusLabel, "Setup needed")
        XCTAssertEqual(
            surface.settings.computerUseSetupSummary,
            "Computer Use needs macOS privacy permissions before QuillCode can inspect or control the desktop."
        )
        XCTAssertEqual(
            surface.settings.computerUseNextAction,
            "Open Screen Recording first, enable QuillCode, then open Accessibility."
        )
        XCTAssertEqual(surface.settings.computerUseRequirements.map(\.title), ["Screen Recording", "Accessibility"])
        XCTAssertEqual(surface.settings.computerUseRequirements.map(\.statusLabel), ["Required", "Required"])
        XCTAssertEqual(surface.settings.computerUseRequirements.map(\.isGranted), [false, false])
        XCTAssertEqual(surface.settings.computerUseRequirements.first?.command.id, "computer-use-open-screen-recording")
        XCTAssertFalse(surface.terminal.isVisible)
        XCTAssertEqual(surface.terminal.cwdLabel, "/tmp/QuillCode")
        XCTAssertFalse(surface.browser.isVisible)
        XCTAssertFalse(surface.extensions.isVisible)
        XCTAssertFalse(surface.memories.isVisible)
        XCTAssertFalse(surface.activity.isVisible)
    }

    func testSurfaceMarksSSHProjectsAndEnablesRemoteGitCommands() throws {
        let connection = ProjectConnection.ssh(
            path: "/srv/quill",
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(
            name: "Feather",
            path: connection.path,
            connection: connection
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id
        ))

        let surface = model.surface()
        let item = try XCTUnwrap(surface.projects.items.first)

        XCTAssertEqual(item.name, "Feather")
        XCTAssertEqual(item.path, "ssh://quill@feather.local:2222/srv/quill")
        XCTAssertEqual(item.connectionKindLabel, "SSH Remote")
        XCTAssertTrue(item.isRemote)
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .rename, .remove])
        XCTAssertEqual(item.actions.first { $0.kind == .refreshContext }?.isEnabled, true)
        XCTAssertNil(item.actions.first { $0.kind == .refreshContext }?.disabledReason)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-status" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-diff" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-view" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checks" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-diff" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checkout" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-reviewers" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-comment" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-labels" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-merge" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-list" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-remove" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "add-ssh-project" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "add-ssh-project" }?.title, "Project: Add SSH Remote...")
        XCTAssertEqual(surface.terminal.cwdLabel, "ssh://quill@feather.local:2222/srv/quill")
    }

    func testSidebarBulkSelectionArchivesAndDeletesChats() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let first = ChatThread(title: "Run whoami", projectID: project.id)
        let second = ChatThread(title: "Check diff", projectID: project.id)
        let fallback = ChatThread(title: "Review tests", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [first, second, fallback],
            selectedThreadID: first.id
        ))

        model.startSidebarSelection(selecting: first.id)
        model.toggleSidebarThreadSelection(second.id)

        var surface = model.surface()
        XCTAssertTrue(surface.sidebar.isSelectionMode)
        XCTAssertEqual(surface.sidebar.selectionLabel, "2 chats selected")
        XCTAssertEqual(Set(surface.sidebar.items.filter(\.isBulkSelected).map(\.id)), [first.id, second.id])
        XCTAssertEqual(surface.sidebar.bulkActions.first { $0.kind == .archive }?.isEnabled, true)

        XCTAssertTrue(model.performSidebarBulkAction(.archive))
        surface = model.surface()

        XCTAssertFalse(surface.sidebar.isSelectionMode)
        XCTAssertEqual(Set(surface.sidebar.archivedItems.map(\.id)), [first.id, second.id])
        XCTAssertEqual(surface.sidebar.selectedThreadID, fallback.id)

        model.selectAllSidebarThreads()
        surface = model.surface()
        XCTAssertEqual(surface.sidebar.selectionLabel, "3 chats selected")
        XCTAssertTrue(model.performSidebarBulkAction(.delete))

        surface = model.surface()
        XCTAssertEqual(surface.sidebar.items.count, 0)
        XCTAssertNil(surface.sidebar.selectedThreadID)
        XCTAssertFalse(surface.sidebar.isSelectionMode)
    }

    func testActivitySurfaceSummarizesThreadToolsSourcesAndArtifacts() throws {
        let instruction = ProjectInstruction(
            path: ".quillcode/AGENTS.md",
            title: "AGENTS.md",
            content: "Use the repo patterns.",
            byteCount: 22
        )
        let memory = MemoryNote(
            id: "global-note",
            scope: .global,
            title: "Prefers concise diffs",
            content: "Keep changes reviewable.",
            relativePath: "preferences.md",
            byteCount: 24
        )
        let call = ToolCall(
            id: "tool-activity",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"whoami"}"#
        )
        let result = ToolResult(
            ok: true,
            stdout: "quill\n",
            artifacts: ["/tmp/quillcode-activity.png"]
        )
        let thread = ChatThread(
            title: "Run command",
            messages: [
                .init(role: .user, content: "run whoami"),
                .init(role: .assistant, content: "Output:\nquill")
            ],
            events: [
                .init(kind: .message, summary: "run whoami"),
                .init(kind: .toolQueued, summary: "host.shell.run queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                .init(kind: .toolRunning, summary: "host.shell.run running"),
                .init(kind: .toolCompleted, summary: "host.shell.run completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                .init(kind: .message, summary: "Output:\nquill")
            ],
            instructions: [instruction],
            memories: [memory]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [thread],
                selectedThreadID: thread.id
            ),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertTrue(activity.isVisible)
        XCTAssertEqual(activity.taskTitle, "run whoami")
        XCTAssertEqual(activity.tools.map(\.title), [ToolDefinition.shellRun.name])
        XCTAssertEqual(activity.tools.first?.statusLabel, ToolCardStatus.done.rawValue)
        XCTAssertEqual(activity.artifacts.map(\.label), ["quillcode-activity.png"])
        XCTAssertEqual(activity.sources.map(\.title), ["AGENTS.md", "Prefers concise diffs"])
        XCTAssertEqual(activity.finalAnswer, "Output: quill")
        XCTAssertEqual(activity.planItems.map(\.title), [
            "Understand request",
            "Load context",
            "Use tools",
            "Review results",
            "Answer user"
        ])
        XCTAssertEqual(activity.planItems.map(\.statusLabel), ["Done", "Done", "Done", "Done", "Done"])
        XCTAssertTrue(activity.planItems.contains { $0.title == "Use tools" && $0.detail.contains(ToolDefinition.shellRun.name) })
        XCTAssertTrue(activity.handoffSummary?.contains("Thread: Run command") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Latest request: run whoami") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Tools: 1 tool (\(ToolDefinition.shellRun.name))") == true)
        XCTAssertTrue(activity.handoffSummary?.contains("Artifacts: 1 artifact (quillcode-activity.png)") == true)
        XCTAssertTrue(activity.recentSteps.contains { $0.title == "Tool completed" && $0.statusLabel == "Done" })
        XCTAssertEqual(activity.sections.map(\.kind), [.plan, .recent, .handoff, .tools, .sources, .artifacts, .latestAnswer])
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.items.map(\.title), activity.planItems.map(\.title))
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.countLabel, "5 items")
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.bodyText, activity.handoffSummary)
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.countLabel, "1 summary")
        XCTAssertEqual(activity.sections.first { $0.kind == .tools }?.items.map(\.title), [ToolDefinition.shellRun.name])
        XCTAssertEqual(activity.sections.first { $0.kind == .artifacts }?.artifacts.map(\.label), ["quillcode-activity.png"])
        XCTAssertEqual(activity.sections.first { $0.kind == .latestAnswer }?.bodyText, "Output: quill")
        XCTAssertEqual(activity.sections.first { $0.kind == .tools }?.toggleCommandID, "activity-toggle-section:tools")
    }

    func testActivitySurfacePrefersModelAuthoredPlan() throws {
        let update = AgentPlanUpdate(
            explanation: "The model is planning the work directly.",
            plan: [
                AgentPlanItem(step: "Inspect current state", status: .completed),
                AgentPlanItem(step: "Apply focused change", status: .inProgress, detail: "Keep the diff small."),
                AgentPlanItem(step: "Run validation", status: .pending)
            ]
        )
        let result = ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        let thread = ChatThread(
            title: "Plan work",
            messages: [.init(role: .user, content: "plan the work")],
            events: [
                .init(
                    kind: .toolCompleted,
                    summary: "\(ToolDefinition.planUpdate.name) completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertEqual(activity.planItems.map(\.title), [
            "Inspect current state",
            "Apply focused change",
            "Run validation"
        ])
        XCTAssertEqual(activity.planItems.map(\.statusLabel), ["Done", "Running", "Pending"])
        XCTAssertEqual(activity.planItems[0].detail, "The model is planning the work directly.")
        XCTAssertEqual(activity.planItems[1].detail, "Keep the diff small.")
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.countLabel, "3 items")
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.items.map(\.kind), [
            "authored-plan",
            "authored-plan",
            "authored-plan"
        ])
    }

    func testActivityCommandTogglesActivityPane() {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.surface().activity.isVisible)
        XCTAssertTrue(model.runWorkspaceCommand("toggle-activity", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertTrue(model.surface().activity.isVisible)
    }

    func testAutomationsCommandTogglesAutomationsPaneWithoutActivity() {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.surface().automations.isVisible)
        XCTAssertFalse(model.surface().activity.isVisible)
        XCTAssertTrue(model.runWorkspaceCommand("toggle-automations", workspaceRoot: URL(fileURLWithPath: "/tmp")))

        let surface = model.surface()
        XCTAssertTrue(surface.automations.isVisible)
        XCTAssertFalse(surface.activity.isVisible)
        XCTAssertEqual(surface.automations.title, "Automations")
        XCTAssertEqual(surface.automations.workflows.map(\.title), [
            "Thread follow-ups",
            "Workspace schedules",
            "Monitors"
        ])
    }

    func testAutomationsSurfaceUsesConfiguredAutomationRowsWhenPresent() {
        let model = QuillCodeWorkspaceModel(automations: AutomationsState(items: [
            QuillAutomation(
                title: "Nightly repo check",
                detail: "Run tests and summarize failures.",
                kind: .workspaceSchedule,
                scheduleKind: .cron,
                scheduleDescription: "Every weekday at 6:00 PM"
            ),
            QuillAutomation(
                title: "Paused PR monitor",
                detail: "Watch the launch PR after review starts.",
                kind: .monitor,
                status: .paused,
                scheduleKind: .event,
                scheduleDescription: "PR events"
            )
        ]))

        let automations = model.surface().automations

        XCTAssertEqual(automations.statusLabel, "1 active · 1 paused")
        XCTAssertEqual(automations.workflows.map(\.title), ["Nightly repo check", "Paused PR monitor"])
        XCTAssertEqual(automations.workflows.map(\.statusLabel), ["Active", "Paused"])
        XCTAssertEqual(automations.workflows.first?.scheduleLabel, "Every weekday at 6:00 PM")
        XCTAssertEqual(automations.workflows.first?.runActionTitle, "Run now")
        XCTAssertTrue(automations.workflows.first?.runCommandID?.hasPrefix("automation-run:") == true)
        XCTAssertEqual(automations.workflows.first?.primaryActionTitle, "Pause")
        XCTAssertTrue(automations.workflows.first?.primaryCommandID?.hasPrefix("automation-pause:") == true)
        XCTAssertTrue(automations.workflows.first?.deleteCommandID?.hasPrefix("automation-delete:") == true)
        XCTAssertEqual(automations.workflows.last?.primaryActionTitle, "Resume")
        XCTAssertTrue(automations.workflows.last?.primaryCommandID?.hasPrefix("automation-resume:") == true)
    }

    func testThreadFollowUpAutomationsExposeRunNowAction() {
        let model = QuillCodeWorkspaceModel(automations: AutomationsState(items: [
            QuillAutomation(
                title: "Launch follow-up",
                detail: "Resume the launch thread.",
                kind: .threadFollowUp,
                scheduleKind: .heartbeat,
                scheduleDescription: "Manual follow-up",
                threadID: UUID()
            ),
            QuillAutomation(
                title: "Paused follow-up",
                detail: "Resume later.",
                kind: .threadFollowUp,
                status: .paused,
                scheduleKind: .heartbeat,
                scheduleDescription: "Manual follow-up",
                threadID: UUID()
            )
        ]))

        let automations = model.surface().automations

        XCTAssertEqual(automations.workflows.first?.runActionTitle, "Run now")
        XCTAssertTrue(automations.workflows.first?.runCommandID?.hasPrefix("automation-run:") == true)
        XCTAssertNil(automations.workflows.last?.runActionTitle)
        XCTAssertNil(automations.workflows.last?.runCommandID)
    }

    func testAutomationsSurfaceExposesCreateCommandsForSelectedThreadAndProject() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Ship QuillCode", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let automations = model.surface().automations

        XCTAssertEqual(automations.createThreadFollowUpCommand?.id, "automation-create-thread-follow-up")
        XCTAssertEqual(automations.createThreadFollowUpCommand?.category, WorkspaceCommandPalette.automationsCategory)
        XCTAssertEqual(automations.createThreadFollowUpCommand?.isEnabled, true)
        XCTAssertEqual(automations.scheduleThreadFollowUpCommands.map(\.id), [
            "automation-create-thread-follow-up-after:600",
            "automation-create-thread-follow-up-after:3600",
            "automation-create-thread-follow-up-tomorrow",
            "automation-create-thread-follow-up-every:daily"
        ])
        XCTAssertEqual(automations.scheduleThreadFollowUpCommands.map(\.isEnabled), [true, true, true, true])
        XCTAssertEqual(model.surface().commands.first { $0.id == "automation-create-thread-follow-up" }?.isEnabled, true)
        XCTAssertEqual(
            model.surface().commands
                .filter { $0.id.hasPrefix("automation-create-thread-follow-up-after:") }
                .map(\.isEnabled),
            [true, true]
        )
        XCTAssertEqual(automations.createWorkspaceScheduleCommand?.id, "automation-create-workspace-schedule")
        XCTAssertEqual(automations.createWorkspaceScheduleCommand?.category, WorkspaceCommandPalette.automationsCategory)
        XCTAssertEqual(automations.createWorkspaceScheduleCommand?.isEnabled, true)
        XCTAssertEqual(automations.scheduleWorkspaceScheduleCommands.map(\.id), [
            "automation-create-workspace-schedule-after:600",
            "automation-create-workspace-schedule-after:3600",
            "automation-create-workspace-schedule-tomorrow",
            "automation-create-workspace-schedule-every:daily"
        ])
        XCTAssertEqual(automations.scheduleWorkspaceScheduleCommands.map(\.isEnabled), [true, true, true, true])
        XCTAssertEqual(model.surface().commands.first { $0.id == "automation-create-workspace-schedule" }?.isEnabled, true)
        XCTAssertEqual(
            model.surface().commands
                .filter { $0.id.hasPrefix("automation-create-workspace-schedule-after:") }
                .map(\.isEnabled),
            [true, true]
        )
        XCTAssertEqual(model.surface().commands.first { $0.id == "automation-create-workspace-schedule-tomorrow" }?.isEnabled, true)
    }

    func testActivitySectionToggleCollapsesSharedSurfaceSection() throws {
        let call = ToolCall(
            id: "tool-activity",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"whoami"}"#
        )
        let result = ToolResult(ok: true, stdout: "quill\n")
        let thread = ChatThread(
            title: "Run command",
            messages: [.init(role: .user, content: "run whoami")],
            events: [
                .init(kind: .toolQueued, summary: "host.shell.run queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                .init(kind: .toolCompleted, summary: "host.shell.run completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, false)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:tools", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, true)
        XCTAssertTrue(model.surface().activity.isVisible)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:handoff", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .handoff }?.isCollapsed, true)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:plan", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .plan }?.isCollapsed, true)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:tools", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, false)
        XCTAssertFalse(model.runWorkspaceCommand("activity-toggle-section:not-real", workspaceRoot: URL(fileURLWithPath: "/tmp")))
    }

    func testSidebarSearchExcludesHiddenToolFeedback() {
        let thread = ChatThread(title: "Visible thread", messages: [
            .init(role: .user, content: "run whoami"),
            .init(role: .tool, content: #"{"result":"secret internal feedback"}"#),
            .init(role: .assistant, content: "Output:\nquill")
        ])

        let item = SidebarItem(thread: thread)
        let sidebar = SidebarSurface(
            items: [SidebarItemSurface(item: item, selectedThreadID: thread.id)],
            selectedThreadID: thread.id
        )

        XCTAssertEqual(sidebar.filteredItems(matching: "secret internal feedback"), [])
        XCTAssertEqual(sidebar.filteredItems(matching: "whoami").map(\.id), [thread.id])
    }

    func testComposerShowsFilteredSlashSuggestions() {
        let model = QuillCodeWorkspaceModel()

        model.setDraft("/")
        var suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.prefix(3).map(\.usage), ["/help", "/status", "/new"])

        model.setDraft("/workt")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/worktrees")
        XCTAssertEqual(suggestions.first?.insertText, "/worktrees")

        model.setDraft("/fol")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/follow-up when")
        XCTAssertEqual(suggestions.first?.insertText, "/follow-up in ")

        model.setDraft("/workspace-c")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/workspace-check when")
        XCTAssertEqual(suggestions.first?.insertText, "/workspace-check in ")

        model.setDraft("/project r")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.prefix(2).map(\.usage), ["/project refresh", "/project rename name"])

        model.setDraft("/pr l")
        suggestions = model.surface().composer.slashSuggestions
        XCTAssertEqual(suggestions.first?.usage, "/pr labels add|remove label")
        XCTAssertEqual(suggestions.first?.insertText, "/pr labels add ")

        model.setDraft("run /help")
        XCTAssertEqual(model.surface().composer.slashSuggestions, [])
    }

    func testSettingsSurfaceShowsTrustedRouterAccount() {
        let config = AppConfig(
            authMode: .oauth,
            trustedRouterAccount: TrustedRouterAccountProfile(
                userID: "usr_123",
                email: "quill@example.com"
            )
        )
        let settings = WorkspaceSettingsSurface(config: config, hasStoredAPIKey: true)

        XCTAssertEqual(settings.apiKeyStatusLabel, "Signed in")
        XCTAssertEqual(settings.loginStatusLabel, "Signed in as quill@example.com")
        XCTAssertEqual(settings.accountLabel, "quill@example.com")
    }

    func testSettingsSurfaceDecodesOlderComputerUsePayload() throws {
        let data = """
        {
          "apiBaseURL": "https://api.trustedrouter.com/v1",
          "authMode": "oauth",
          "developerOverrideEnabled": false,
          "hasStoredAPIKey": false,
          "signInURL": "http://localhost:3000/callback",
          "apiKeyStatusLabel": "Not signed in",
          "loginStatusLabel": "TrustedRouter login required",
          "computerUseStatus": {
            "available": false,
            "screenRecordingGranted": true,
            "accessibilityGranted": false,
            "message": "Needs Accessibility"
          },
          "computerUseSetupCommand": {
            "id": "computer-use-setup",
            "title": "Computer Use setup",
            "isEnabled": true
          },
          "computerUseScreenRecordingCommand": {
            "id": "computer-use-open-screen-recording",
            "title": "Open Screen Recording settings",
            "isEnabled": false
          },
          "computerUseAccessibilityCommand": {
            "id": "computer-use-open-accessibility",
            "title": "Open Accessibility settings",
            "isEnabled": true
          },
          "computerUseRefreshCommand": {
            "id": "computer-use-refresh",
            "title": "Refresh Computer Use status",
            "isEnabled": true
          }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(WorkspaceSettingsSurface.self, from: data)

        XCTAssertEqual(settings.computerUseStatusLabel, "Accessibility needed")
        XCTAssertEqual(
            settings.computerUseNextAction,
            "Open Accessibility, enable QuillCode, then refresh status."
        )
        XCTAssertEqual(settings.computerUseRequirements.map(\.title), ["Screen Recording", "Accessibility"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.statusLabel), ["Granted", "Required"])
        XCTAssertEqual(settings.computerUseRequirements.map(\.command.isEnabled), [false, true])
    }

    func testRuntimeIssueDecodesOlderPayloadWithoutDiagnostics() throws {
        let data = """
        {
          "severity": "warning",
          "title": "Old issue",
          "message": "Older renderer payload",
          "actionLabel": "Retry"
        }
        """.data(using: .utf8)!

        let issue = try JSONDecoder().decode(RuntimeIssueSurface.self, from: data)

        XCTAssertEqual(issue.title, "Old issue")
        XCTAssertEqual(issue.actionLabel, "Retry")
        XCTAssertTrue(issue.diagnostics.isEmpty)
    }

    func testShortcutRegistryLabelsSurfaceCommands() {
        let model = QuillCodeWorkspaceModel()
        let commandsByID = Dictionary(uniqueKeysWithValues: model.surface().commands.map { ($0.id, $0) })

        for shortcut in WorkspaceShortcutRegistry.shortcuts {
            XCTAssertEqual(
                commandsByID[shortcut.commandID]?.shortcut,
                shortcut.displayLabel,
                shortcut.commandID
            )
        }
    }

    func testShortcutRegistryHasNoDuplicateBindings() {
        let bindings = WorkspaceShortcutRegistry.shortcuts.map {
            "\($0.modifiers.map(\.rawValue).joined(separator: "+"))+\($0.key)"
        }

        XCTAssertEqual(Set(bindings).count, bindings.count)
    }

    func testCommandPaletteRanksByShortcutKeywordsAndTitle() {
        let model = QuillCodeWorkspaceModel()
        let commands = model.surface().commands

        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "shell").first?.id,
            "toggle-terminal"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "cmd+k").first?.id,
            "search"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "cmd+f").first?.id,
            "find-in-chat"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "create pull").first?.id,
            "git-pr-create"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "checks").first?.id,
            "git-pr-checks"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "pr diff").first?.id,
            "git-pr-diff"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "checkout pull").first?.id,
            "git-pr-checkout"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "request reviewers").first?.id,
            "git-pr-reviewers"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "comment pull").first?.id,
            "git-pr-comment"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "approve pr").first?.id,
            "git-pr-review"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "label pr").first?.id,
            "git-pr-labels"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "merge pull").first?.id,
            "git-pr-merge"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "cmd+/").first?.id,
            "keyboard-shortcuts"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "shortcuts").first?.id,
            "keyboard-shortcuts"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: ">shell").first?.id,
            "toggle-terminal"
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "/mode").first?.title,
            "/mode auto|review|read-only"
        )
        XCTAssertFalse(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "")
                .contains { $0.id.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) }
        )
        XCTAssertTrue(
            WorkspaceCommandPalette.rankedCommands(commands, matching: "mode")
                .contains { $0.id.hasPrefix(SlashCommandCatalog.commandPaletteIDPrefix) }
        )
        XCTAssertEqual(
            WorkspaceCommandPalette.groupedCommands(commands, matching: "/").map(\.title),
            [WorkspaceCommandPalette.slashCategory]
        )
    }

    func testCommandPaletteGroupsFilteredResultsByCategory() {
        let model = QuillCodeWorkspaceModel()
        let groups = WorkspaceCommandPalette.groupedCommands(model.surface().commands, matching: ">worktree")

        XCTAssertEqual(groups.map(\.title), [WorkspaceCommandPalette.gitCategory])
        XCTAssertEqual(groups.first?.commands.map(\.id), [
            "git-worktree-list",
            "git-worktree-create",
            "git-worktree-remove"
        ])
    }

    func testWorkspaceCommandSurfaceDecodesOlderPayloadWithoutCategoryMetadata() throws {
        let data = #"{"id":"search","title":"Search","shortcut":"Cmd+K","isEnabled":true}"#.data(using: .utf8)!

        let command = try JSONDecoder().decode(WorkspaceCommandSurface.self, from: data)

        XCTAssertEqual(command.category, WorkspaceCommandPalette.workspaceCategory)
        XCTAssertEqual(command.keywords, [])
    }

    func testContextBannerDecodesOlderPayloadWithoutCompactCommand() throws {
        let data = """
        {
          "usedPercent": 88,
          "title": "Approaching context limit",
          "subtitle": "Older turns may drop out soon.",
          "newThreadCommand": {"id":"new-chat","title":"New thread"},
          "forkCommand": {"id":"fork-from-last","title":"Fork from last","isEnabled":true}
        }
        """.data(using: .utf8)!

        let banner = try JSONDecoder().decode(ContextBannerSurface.self, from: data)

        XCTAssertEqual(banner.usedPercent, 88)
        XCTAssertEqual(banner.compactCommand.id, "compact-context")
        XCTAssertEqual(banner.compactCommand.title, "Compact context")
        XCTAssertEqual(banner.compactCommand.category, WorkspaceCommandPalette.threadCategory)
        XCTAssertEqual(banner.compactCommand.isEnabled, true)
    }

    func testSurfaceGroupsCustomModelCatalogByCategory() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "acme/code-pro"),
            topBar: TopBarState(model: "acme/code-pro")
        ))
        model.setModelCatalog([
            .init(id: TrustedRouterDefaults.synthModel, provider: "trustedrouter", displayName: TrustedRouterDefaults.synthModelDisplayName, category: "Recommended"),
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "acme/fast", provider: "acme", displayName: "Fast", category: "Coding")
        ])

        let surface = model.surface()

        XCTAssertEqual(surface.topBar.modelLabel, "acme/Code Pro")
        XCTAssertEqual(surface.topBar.modelCategories.map(\.category), ["Recommended", "Safety", "Coding"])
        let recommended = surface.topBar.modelCategories.first { $0.category == "Recommended" }
        XCTAssertEqual(recommended?.models.prefix(3).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
        let coding = surface.topBar.modelCategories.first { $0.category == "Coding" }
        XCTAssertEqual(coding?.models.map(\.id), ["acme/code-pro", "acme/fast"])
        XCTAssertTrue(coding?.models.first?.isSelected == true)
    }

    func testTopBarFiltersModelCatalogByProviderCategoryAndModel() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: TrustedRouterDefaults.synthModel),
            topBar: TopBarState(model: TrustedRouterDefaults.synthModel)
        ))
        model.setModelCatalog([
            .init(id: TrustedRouterDefaults.synthModel, provider: "trustedrouter", displayName: TrustedRouterDefaults.synthModelDisplayName, category: "Recommended"),
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "moonshotai/kimi-k2.6", provider: "moonshotai", displayName: "Kimi K2.6", category: "Safety")
        ])

        let topBar = model.surface().topBar

        XCTAssertEqual(topBar.filteredModelCategories(matching: "coding").flatMap(\.models).map(\.id), ["acme/code-pro"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "moon k2").flatMap(\.models).map(\.id), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(
            topBar.filteredModelCategories(matching: "synth").flatMap(\.models).map(\.id),
            [TrustedRouterDefaults.synthModel, TrustedRouterDefaults.synthCodeModel]
        )
        XCTAssertEqual(
            topBar.filteredModelCategories(matching: "tr/synth-code").flatMap(\.models).map(\.id),
            [TrustedRouterDefaults.synthCodeModel]
        )
        XCTAssertEqual(topBar.filteredModelCategories(matching: "default model").flatMap(\.models).map(\.id), [TrustedRouterDefaults.synthModel])
        XCTAssertTrue(topBar.filteredModelCategories(matching: "does-not-exist").isEmpty)
    }

    func testSurfaceIncludesLocalEnvironmentActionCommands() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            localActions: [
                LocalEnvironmentAction(
                    id: "local-env:.quillcode/actions/bootstrap.sh",
                    title: "Bootstrap",
                    detail: "Install dependencies and warm caches.",
                    relativePath: ".quillcode/actions/bootstrap.sh",
                    command: "sh '.quillcode/actions/bootstrap.sh'",
                    environment: ["QUILL_ENV": "dev"],
                    workingDirectory: "app",
                    timeoutSeconds: 120
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id
        ))

        let command = model.surface().commands.first {
            $0.id == "local-env:.quillcode/actions/bootstrap.sh"
        }

        XCTAssertEqual(command?.title, "Run Bootstrap")
        XCTAssertEqual(command?.isEnabled, true)
        XCTAssertTrue(command?.keywords.contains("Install dependencies and warm caches.") == true)
        XCTAssertTrue(command?.keywords.contains("QUILL_ENV") == true)
        XCTAssertTrue(command?.keywords.contains("app") == true)
        XCTAssertTrue(command?.keywords.contains("120s") == true)
    }

    func testSurfaceIncludesProjectExtensionSummaryAndCommand() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "plugin:github",
                    kind: .plugin,
                    name: "GitHub",
                    summary: "PR workflow helpers.",
                    version: "1.2.0",
                    sourceURL: "https://github.com/Lore-Hex/quillcode-github",
                    relativePath: ".quillcode/plugins/github.json",
                    updateCommand: "git -C .quillcode/plugins/github pull --ff-only",
                    updateTimeoutSeconds: 300
                ),
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    summary: "Workspace MCP server.",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    transport: .stdio,
                    launchExecutable: "quill-mcp",
                    launchCommand: "quill-mcp --root .",
                    launchArguments: ["--root", "."]
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(isVisible: true)
        )

        let surface = model.surface()

        XCTAssertEqual(surface.extensions.subtitle, "1 plugin · 0 skills · 1 MCP server")
        XCTAssertEqual(surface.extensions.items.map(\.kindLabel), ["Plugin", "MCP"])
        XCTAssertEqual(surface.extensions.items.map(\.statusLabel), ["Discovered", "Stopped"])
        XCTAssertEqual(surface.extensions.items.first?.versionLabel, "v1.2.0")
        XCTAssertEqual(surface.extensions.items.first?.sourceURL, "https://github.com/Lore-Hex/quillcode-github")
        XCTAssertEqual(surface.extensions.items.first?.updateCommandID, "extension-update:plugin:github")
        XCTAssertEqual(surface.commands.first { $0.id == "extension-update:plugin:github" }?.title, "Update GitHub")
        XCTAssertEqual(surface.commands.first { $0.id == "extension-update:plugin:github" }?.isEnabled, true)
        XCTAssertEqual(surface.extensions.items.last?.transportLabel, "STDIO")
        XCTAssertEqual(surface.extensions.items.last?.launchCommand, "quill-mcp --root .")
        XCTAssertEqual(surface.extensions.items.last?.startCommandID, "mcp-start:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-start:mcp_server:filesystem" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-stop:mcp_server:filesystem" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-extensions" }?.category, WorkspaceCommandPalette.extensionsCategory)
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-extensions" }?.isEnabled, true)
    }

    func testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    transport: .stdio,
                    launchExecutable: "quill-mcp",
                    launchCommand: "quill-mcp --root .",
                    launchArguments: ["--root", "."]
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(
                isVisible: true,
                mcpServerStatuses: ["mcp_server:filesystem": .ready],
                mcpServerProbeSummaries: [
                    "mcp_server:filesystem": MCPServerProbeSummary(
                        protocolVersion: "2024-11-05",
                        serverName: "Fixture MCP",
                        serverVersion: "1.0.0",
                        toolDescriptors: [
                            MCPToolDescriptor(
                                name: "read_file",
                                description: "Read a file",
                                requiredArguments: ["path"],
                                schemaSummary: "required: path:string"
                            ),
                            MCPToolDescriptor(
                                name: "write_file",
                                requiredArguments: ["content", "path"],
                                optionalArguments: ["overwrite"],
                                schemaSummary: "required: content:string, path:string; optional: overwrite:boolean"
                            )
                        ],
                        resourceNames: ["README", "Project config"],
                        promptNames: ["summarize_project"]
                    )
                ]
            )
        )

        let surface = model.surface()

        XCTAssertEqual(surface.extensions.items.first?.statusLabel, "Ready")
        XCTAssertEqual(surface.extensions.items.first?.serverLabel, "Fixture MCP 1.0.0")
        XCTAssertEqual(surface.extensions.items.first?.protocolLabel, "MCP 2024-11-05")
        XCTAssertEqual(surface.extensions.items.first?.toolCountLabel, "2 tools")
        XCTAssertEqual(surface.extensions.items.first?.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(surface.extensions.items.first?.toolDescriptors.map(\.schemaSummary), [
            "required: path:string",
            "required: content:string, path:string; optional: overwrite:boolean"
        ])
        XCTAssertEqual(surface.extensions.items.first?.resourceCountLabel, "2 resources")
        XCTAssertEqual(surface.extensions.items.first?.resourceNames, ["README", "Project config"])
        XCTAssertEqual(surface.extensions.items.first?.promptCountLabel, "1 prompt")
        XCTAssertEqual(surface.extensions.items.first?.promptNames, ["summarize_project"])
        XCTAssertNil(surface.extensions.items.first?.startCommandID)
        XCTAssertEqual(surface.extensions.items.first?.stopCommandID, "mcp-stop:mcp_server:filesystem")
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-start:mcp_server:filesystem" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "mcp-stop:mcp_server:filesystem" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "stop-all" }?.isEnabled, true)
    }

    func testSurfaceIncludesMemorySummariesAndCommand() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            memories: [
                MemoryNote(
                    id: "project:.quillcode/memories/project.md",
                    scope: .project,
                    title: "Project",
                    content: "QuillCode should stay native Swift and document major decisions.",
                    relativePath: ".quillcode/memories/project.md",
                    byteCount: 63
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                globalMemories: [
                    MemoryNote(
                        id: "global:memories/preferences.md",
                        scope: .global,
                        title: "Preferences",
                        content: "Prefer focused tests and small reviewable commits.",
                        relativePath: "memories/preferences.md",
                        byteCount: 48
                    )
                ]
            ),
            memories: MemoriesState(isVisible: true)
        )

        let surface = model.surface()

        XCTAssertTrue(surface.memories.isVisible)
        XCTAssertEqual(surface.memories.globalCount, 1)
        XCTAssertEqual(surface.memories.projectCount, 1)
        XCTAssertEqual(surface.memories.items.map { $0.scope }, [MemoryScope.global, .project])
        XCTAssertEqual(surface.memories.items.first?.title, "Preferences")
        XCTAssertEqual(surface.topBar.memoryLabel, "2 memories")
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-memories" }?.category, WorkspaceCommandPalette.memoriesCategory)
    }

    func testStopAllCommandIsEnabledForTerminalRuns() {
        let model = QuillCodeWorkspaceModel(terminal: TerminalState(isRunning: true))

        let command = model.surface().commands.first { $0.id == "stop-all" }

        XCTAssertEqual(command?.isEnabled, true)
    }

    func testSurfaceIncludesBrowserPreviewState() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.toggleBrowser()
        XCTAssertTrue(model.openBrowserPreview("example.com", workspaceRoot: root))
        XCTAssertTrue(model.addBrowserComment("Looks aligned"))

        let surface = model.surface()

        XCTAssertTrue(surface.browser.isVisible)
        XCTAssertEqual(surface.browser.currentURL, "https://example.com")
        XCTAssertEqual(surface.browser.title, "example.com")
        XCTAssertEqual(surface.browser.statusLabel, "Comment added")
        XCTAssertEqual(surface.browser.snapshot?.sourceLabel, "Web page")
        XCTAssertEqual(surface.browser.snapshot?.inspectionDepth, .metadataOnly)
        XCTAssertEqual(surface.browser.snapshot?.inspectionDepthLabel, "Metadata only")
        XCTAssertEqual(
            surface.browser.snapshot?.summary,
            "Live DOM capture is not attached yet; QuillCode has URL metadata for this web page."
        )
        XCTAssertEqual(surface.browser.snapshot?.details, [
            "Host: example.com",
            "Scheme: HTTPS",
            "Path: /"
        ])
        XCTAssertEqual(surface.browser.comments.first?.text, "Looks aligned")
        XCTAssertTrue(surface.browser.canOpen)
        XCTAssertTrue(surface.commands.contains { $0.id == "toggle-browser" && $0.title == "Browser" })
    }

    func testSurfaceKeepsUnknownSelectedModelVisible() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "custom/edge-model"),
            topBar: TopBarState(model: "custom/edge-model"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let surface = model.surface()
        let current = surface.topBar.modelCategories.first { $0.category == "Current" }

        XCTAssertEqual(surface.topBar.modelLabel, "custom/edge-model")
        XCTAssertEqual(current?.models.first?.id, "custom/edge-model")
        XCTAssertEqual(current?.models.first?.displayName, "Edge Model")
        XCTAssertTrue(current?.models.first?.isSelected == true)
    }

    func testModelPickerShowsRecentModelsAndBadges() throws {
        let older = ChatThread(
            title: "Older model",
            model: "z-ai/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ChatThread(
            title: "Newer model",
            model: "moonshotai/kimi-k2.6",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: TrustedRouterDefaults.defaultModel),
            threads: [older, newer],
            selectedThreadID: newer.id,
            topBar: TopBarState(model: "moonshotai/kimi-k2.6"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let topBar = model.surface().topBar
        let recent = try XCTUnwrap(topBar.modelCategories.first)

        XCTAssertEqual(recent.category, "Recent")
        XCTAssertEqual(recent.models.map(\.id), ["moonshotai/kimi-k2.6", "z-ai/glm-5.2"])
        XCTAssertEqual(recent.models.first?.badges, ["Recent", "Current"])

        let defaultOption = try XCTUnwrap(topBar.modelCategories
            .flatMap(\.models)
            .first { $0.id == TrustedRouterDefaults.defaultModel })
        XCTAssertTrue(defaultOption.badges.contains("Default"))
        XCTAssertTrue(defaultOption.badges.contains("Recommended"))
        XCTAssertEqual(defaultOption.metadataSummary, "Fast everyday agent")
        XCTAssertEqual(defaultOption.detailTitle, "Nike 1.0")
        XCTAssertEqual(defaultOption.capabilitySummary, "Nike 1.0 is the fast default for coding, shell, and file-editing turns.")
        XCTAssertTrue(defaultOption.metadataDetails.contains("Provider: trustedrouter"))
        XCTAssertTrue(defaultOption.metadataDetails.contains("Model ID: trustedrouter/fast"))
        XCTAssertTrue(defaultOption.metadataDetails.contains("Category: Recommended"))
        XCTAssertEqual(defaultOption.metadataRows.map(\.label), ["Provider", "Model ID", "Category", "State"])
        XCTAssertEqual(defaultOption.metadataRows.first { $0.label == "State" }?.value, "Default, Recommended")

        XCTAssertEqual(topBar.filteredModelCategories(matching: "moon k2").flatMap(\.models).map(\.id), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "recent").first?.category, "Recent")
        XCTAssertEqual(topBar.filteredModelCategories(matching: "nike default").flatMap(\.models).map(\.id), [TrustedRouterDefaults.defaultModel])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "default state").flatMap(\.models).map(\.id), [TrustedRouterDefaults.defaultModel])
    }

    func testModelPickerShowsFavoriteModelsBeforeRecent() throws {
        let older = ChatThread(
            title: "Favorite model",
            model: "z-ai/glm-5.2",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = ChatThread(
            title: "Recent model",
            model: "moonshotai/kimi-k2.6",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(
                defaultModel: TrustedRouterDefaults.synthModel,
                favoriteModels: [" z-ai/glm-5.2 ", "z-ai/glm-5.2"]
            ),
            threads: [older, newer],
            selectedThreadID: newer.id,
            topBar: TopBarState(model: "moonshotai/kimi-k2.6"),
            modelCatalog: TrustedRouterModelCatalog.defaultModels
        ))

        let topBar = model.surface().topBar
        XCTAssertEqual(topBar.modelCategories.prefix(2).map(\.category), ["Favorites", "Recent"])

        let favorite = try XCTUnwrap(topBar.modelCategories.first)
        XCTAssertEqual(favorite.models.map(\.id), ["z-ai/glm-5.2"])
        XCTAssertTrue(favorite.models.first?.isFavorite == true)
        XCTAssertEqual(favorite.models.first?.badges, ["Favorite"])

        let recent = try XCTUnwrap(topBar.modelCategories.dropFirst().first)
        XCTAssertEqual(recent.models.map(\.id), ["moonshotai/kimi-k2.6"])

        XCTAssertEqual(topBar.filteredModelCategories(matching: "favorite").map(\.category), ["Favorites"])
        XCTAssertEqual(topBar.filteredModelCategories(matching: "glm").flatMap(\.models).map(\.id), ["z-ai/glm-5.2"])
    }

    func testModelOptionDecodesOlderPayloadWithoutBadges() throws {
        let data = """
        {
          "id": "tr/fusion",
          "provider": "trustedrouter",
          "displayName": "Old model label",
          "category": "Recommended",
          "isSelected": true
        }
        """.data(using: .utf8)!

        let option = try JSONDecoder().decode(ModelOptionSurface.self, from: data)

        XCTAssertEqual(option.id, TrustedRouterDefaults.synthModel)
        XCTAssertTrue(option.isSelected)
        XCTAssertFalse(option.isFavorite)
        XCTAssertTrue(option.badges.isEmpty)
        XCTAssertEqual(option.metadataSummary, "Deeper planning and review")
        XCTAssertEqual(option.detailTitle, "Synth")
        XCTAssertEqual(option.capabilitySummary, "Synth is the balanced model for deeper coding and review turns.")
        XCTAssertTrue(option.metadataDetails.contains("Provider: trustedrouter"))
        XCTAssertTrue(option.metadataDetails.contains("Model ID: /synth"))
        XCTAssertEqual(option.metadataRows.first { $0.label == "Model ID" }?.value, "/synth")
        XCTAssertTrue(option.metadataDetails.contains("Category: Recommended"))
        XCTAssertTrue(option.metadataDetails.contains("Current selection"))
        XCTAssertEqual(option.metadataRows.first { $0.label == "State" }?.value, "Current")
    }

    func testEmptySurfaceShowsCodexLikeEmptyState() {
        let surface = QuillCodeWorkspaceModel().surface()

        XCTAssertEqual(surface.topBar.primaryTitle, "QuillCode")
        XCTAssertEqual(surface.sidebar.items.count, 0)
        XCTAssertEqual(surface.transcript.emptyTitle, "Ask QuillCode to inspect, edit, or run this project.")
        XCTAssertFalse(surface.review.isVisible)
        XCTAssertFalse(surface.composer.canSend)
        XCTAssertTrue(surface.topBar.showsComputerUseSetup)
    }

    func testContextBannerAppearsNearEstimatedLimit() throws {
        let longMessage = "context " + String(repeating: "word ", count: 26_000)
        let thread = ChatThread(title: "Long context", messages: [
            .init(role: .user, content: longMessage)
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let surface = model.surface()
        let banner = try XCTUnwrap(surface.contextBanner)

        XCTAssertTrue(banner.usedPercent >= 80)
        XCTAssertTrue(banner.title.contains("Context"))
        XCTAssertEqual(banner.newThreadCommand.id, "new-chat")
        XCTAssertEqual(banner.forkCommand.id, "fork-from-last")
        XCTAssertEqual(banner.compactCommand.id, "compact-context")
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, true)
    }

    func testContextBannerHiddenForShortThreadAndForkDisabledWithoutMessages() {
        let thread = ChatThread(title: "Short")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let surface = model.surface()

        XCTAssertNil(surface.contextBanner)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, false)
    }

    func testSidebarSearchFiltersByThreadTitleSubtitleAndTranscriptContent() {
        let selectedThread = ChatThread(title: "Run whoami", model: TrustedRouterDefaults.synthModel)
        var otherThread = ChatThread(title: "Review git diff", model: "z-ai/glm-5.2", isPinned: true)
        otherThread.messages = [
            .init(role: .user, content: "Can you inspect the browser preview?")
        ]
        var archivedThread = ChatThread(title: "Old release plan", model: TrustedRouterDefaults.synthModel)
        archivedThread.isArchived = true
        let surface = SidebarSurface(
            items: [
                SidebarItemSurface(item: SidebarItem(thread: selectedThread), selectedThreadID: selectedThread.id),
                SidebarItemSurface(item: SidebarItem(thread: otherThread), selectedThreadID: selectedThread.id),
                SidebarItemSurface(item: SidebarItem(thread: archivedThread), selectedThreadID: selectedThread.id)
            ],
            selectedThreadID: selectedThread.id
        )

        XCTAssertEqual(surface.filteredItems(matching: "").map(\.title), ["Run whoami", "Review git diff", "Old release plan"])
        XCTAssertEqual(surface.filteredItems(matching: "who").map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.filteredItems(matching: "GLM").map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.filteredItems(matching: "browser preview").map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.filteredItems(matching: "archived").map(\.title), ["Old release plan"])
        XCTAssertTrue(surface.filteredItems(matching: "workspace manager").isEmpty)
        XCTAssertEqual(surface.pinnedItems.map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.recentItems.map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.recentSections().map(\.title), ["Today"])
        XCTAssertEqual(surface.archivedItems.map(\.title), ["Old release plan"])
        XCTAssertEqual(surface.archivedItems.first?.actions.map(\.kind), [.unarchive, .delete])
    }

    func testGitDiffReviewSurfaceSummarizesLatestCompletedDiff() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        index 1111111..2222222 100644
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,3 +1,4 @@
         import Foundation
        -let title = "Old"
        +let title = "QuillCode"
        +let subtitle = "Review"
        diff --git a/README.md b/README.md
        index 3333333..4444444 100644
        --- a/README.md
        +++ b/README.md
        @@ -1 +1 @@
        -Old README
        +New README
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let thread = ChatThread(
            title: "Review changes",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolRunning, summary: "host.git.diff running"),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let review = model.surface().review

        XCTAssertTrue(review.isVisible)
        XCTAssertEqual(review.files.map(\.path), ["Sources/App.swift", "README.md"])
        XCTAssertEqual(review.totalInsertions, 3)
        XCTAssertEqual(review.totalDeletions, 2)
        XCTAssertEqual(review.totalHunks, 2)
        XCTAssertEqual(review.subtitle, "2 files changed, +3 -2")
        XCTAssertEqual(review.files.first?.actions.map(\.kind), [.stage, .restore])
        XCTAssertEqual(review.files.first?.hunkItems.count, 1)
        XCTAssertEqual(review.files.first?.hunkItems.first?.actions.map(\.kind), [.stageHunk, .restoreHunk])
        XCTAssertTrue(review.files.first?.hunkItems.first?.patch.contains("diff --git a/Sources/App.swift b/Sources/App.swift") == true)
        let appLines = review.files.first?.hunkItems.first?.lines
        XCTAssertEqual(appLines?.map(\.kind), [.context, .deletion, .insertion, .insertion])
        XCTAssertEqual(appLines?.map(\.oldLineNumber), [1, 2, nil, nil])
        XCTAssertEqual(appLines?.map(\.newLineNumber), [1, nil, 2, 3])
    }

    func testGitDiffReviewSurfaceIncludesMatchingReviewComments() throws {
        let diff = """
        diff --git a/Sources/App.swift b/Sources/App.swift
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1 +1,2 @@
        +let title = "QuillCode"
         import Foundation
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let matchingComment = WorkspaceReviewCommentState(path: "Sources/App.swift", text: "Check the public API name.")
        let lineComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            lineKind: .insertion,
            text: "This line should stay public."
        )
        let rangeComment = WorkspaceReviewCommentState(
            path: "Sources/App.swift",
            lineNumber: 1,
            endLineNumber: 2,
            text: "Keep the title next to the import."
        )
        let staleComment = WorkspaceReviewCommentState(path: "README.md", text: "This file is no longer in the diff.")
        let thread = ChatThread(
            title: "Review changes",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift", payloadJSON: try JSONHelpers.encodePretty(matchingComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift:1", payloadJSON: try JSONHelpers.encodePretty(lineComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift:1-2", payloadJSON: try JSONHelpers.encodePretty(rangeComment)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on README.md", payloadJSON: try JSONHelpers.encodePretty(staleComment))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let review = model.surface().review

        XCTAssertEqual(review.files.count, 1)
        XCTAssertEqual(review.files.first?.comments.map(\.text), ["Check the public API name."])
        XCTAssertEqual(
            review.files.first?.hunkItems.first?.lines.first?.comments.map(\.text),
            ["This line should stay public.", "Keep the title next to the import."]
        )
        XCTAssertEqual(review.files.first?.hunkItems.first?.lines.first?.comments.last?.lineRangeLabel, "Lines 1-2")
    }

    func testGitDiffReviewSurfaceHidesStaleDiffWhenLatestDiffFailed() throws {
        let successfulCall = ToolCall(id: "git-diff-1", name: "host.git.diff", argumentsJSON: "{}")
        let failedCall = ToolCall(id: "git-diff-2", name: "host.git.diff", argumentsJSON: "{}")
        let successfulResult = ToolResult(ok: true, stdout: """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        @@ -1 +1 @@
        -old
        +new
        """)
        let failedResult = ToolResult(ok: false, error: "not a git repository")
        let thread = ChatThread(
            title: "Git diff",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(successfulCall)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(successfulResult)),
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(failedCall)),
                ThreadEvent(kind: .toolFailed, summary: "host.git.diff failed", payloadJSON: try JSONHelpers.encodePretty(failedResult))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertFalse(model.surface().review.isVisible)
    }

    func testHTMLRendererEscapesAndLabelsPrimaryRegions() {
        let project = ProjectRef(
            name: "Unsafe <project>",
            path: "/tmp/unsafe",
            lastOpenedAt: Date(),
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: "Project AGENTS.md",
                    content: "No <script> tags.",
                    byteCount: 17
                )
            ]
        )
        var thread = ChatThread(title: "Unsafe <title>")
        thread.messages = [
            .init(role: .user, content: "<script>alert(1)</script>")
        ]
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="top-bar""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-title-group""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-clusters""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-primary-cluster""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-subtitle""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-status-metadata""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-context-cluster""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-status-button""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-status-menu""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-status-popover""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-compose-zone""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-threads-zone""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-projects-zone""#))
        XCTAssertTrue(html.contains(#"data-testid="new-chat-button" data-primary="true" data-icon="new" data-command-id="new-chat">New chat"#))
        XCTAssertFalse(html.contains(#"data-testid="extensions-button" data-primary="true""#))
        XCTAssertFalse(html.contains(#"data-testid="automations-button" data-primary="true""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-menu""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-button""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-section" data-command-group="navigate""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-section-title">Navigate"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-section" data-command-group="extensions""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-section-title">Extensions"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-section" data-command-group="automate""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-section-title">Automate"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-search-button" role="menuitem" aria-label="Search" title="Search" data-icon="search" data-command-id="search">Search"#))
        XCTAssertTrue(html.contains(#"data-testid="extensions-button" role="menuitem" aria-label="Plugins" title="Plugins" data-icon="plugins" data-command-id="toggle-extensions">Plugins"#))
        XCTAssertTrue(html.contains(#"data-testid="automations-button" role="menuitem" aria-label="Automations" title="Automations" data-icon="automations" data-command-id="toggle-automations">Automations"#))
        XCTAssertTrue(html.contains(#"data-testid="settings-button""#))
        XCTAssertFalse(html.contains(#"class="sidebar-utility-strip""#))
        XCTAssertFalse(html.contains(#"class="sidebar-workspace-actions""#))
        XCTAssertTrue(html.contains(#"data-testid="add-project-button""#))
        XCTAssertTrue(html.contains(#"data-testid="project-item""#))
        XCTAssertTrue(html.contains(#"data-testid="transcript""#))
        XCTAssertTrue(html.contains(#"data-testid="composer""#))
        XCTAssertTrue(html.contains(#"data-testid="composer-surface""#))
        XCTAssertTrue(html.contains(#"class="composer-input-row""#))
        XCTAssertTrue(html.contains(#"class="composer-sr-only" for="message">Message"#))
        XCTAssertTrue(html.contains(#"data-testid="composer-controls""#))
        XCTAssertTrue(html.contains(#"data-testid="model-picker-button""#))
        XCTAssertTrue(html.contains(#"data-testid="mode-picker-button""#))
        XCTAssertTrue(html.contains(#"class="mode-dot""#))
        XCTAssertFalse(html.contains(#"class="mode-prefix">Mode"#))
        XCTAssertTrue(html.contains(#"data-testid="project-instructions-status""#))
        XCTAssertTrue(html.contains("1 instruction file loaded"))
        XCTAssertTrue(html.contains("AGENTS.md"))
        XCTAssertTrue(html.contains(#"data-testid="computer-use-status""#))
        XCTAssertTrue(html.contains("Unsafe &lt;title&gt;"))
        XCTAssertTrue(html.contains("Unsafe &lt;project&gt;"))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
    }

    func testHTMLRendererTopBarOverflowUsesCommandAvailability() {
        let idleHTML = WorkspaceHTMLRenderer.render(QuillCodeWorkspaceModel().surface())
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-command-palette""#))
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-search""#))
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-settings""#))
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-keyboard-shortcuts""#))
        XCTAssertFalse(idleHTML.contains(#"data-testid="top-bar-overflow-stop-all""#))
        XCTAssertFalse(idleHTML.contains(#"data-testid="top-bar-stop-button""#))

        let activeHTML = WorkspaceHTMLRenderer.render(
            QuillCodeWorkspaceModel(composer: ComposerState(isSending: true)).surface()
        )
        XCTAssertFalse(activeHTML.contains(#"data-testid="top-bar-overflow-stop-all""#))
        XCTAssertTrue(activeHTML.contains(#"data-testid="top-bar-stop-button""#))
        XCTAssertTrue(activeHTML.contains(#"aria-label="Stop active work""#))
    }

    func testHTMLRendererShowsStopButtonDuringActiveSend() {
        let model = QuillCodeWorkspaceModel(composer: ComposerState(isSending: true))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="top-bar-stop-button""#))
        XCTAssertTrue(html.contains(#"data-testid="stop-button""#))
        XCTAssertTrue(html.contains(">Stop</button>"))
        XCTAssertTrue(html.contains(#"<textarea id="message" aria-label="Message""#))
        XCTAssertTrue(html.contains(#"rows="1""#))
        XCTAssertTrue(html.contains("disabled"))
        XCTAssertFalse(html.contains(#"data-testid="send-button""#))
    }

    func testHTMLRendererUsesMultilineComposer() {
        let model = QuillCodeWorkspaceModel(composer: ComposerState(
            draft: "first line\nsecond line"
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"<textarea id="message" aria-label="Message""#))
        XCTAssertTrue(html.contains(#"rows="1""#))
        XCTAssertTrue(html.contains("first line\nsecond line</textarea>"))
        XCTAssertFalse(html.contains(#"<input id="message""#))
    }

    func testHTMLRendererIncludesContextBanner() throws {
        let thread = ChatThread(title: "Long context", messages: [
            .init(role: .user, content: String(repeating: "token ", count: 26_000))
        ])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="context-banner""#))
        XCTAssertTrue(html.contains(#"data-testid="context-new-thread""#))
        XCTAssertTrue(html.contains(#"data-testid="context-fork-last""#))
        XCTAssertTrue(html.contains(#"data-testid="context-compact""#))
    }

    func testHTMLRendererIncludesRuntimeIssue() throws {
        let model = QuillCodeWorkspaceModel()
        model.setAgentStatus("Failed", lastError: "TrustedRouter returned an empty response.")

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="runtime-issue""#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-issue-pill""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-activity-hairline""#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-issue-title">TrustedRouter returned no content"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-issue-action">Retry"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostics""#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-label">API base URL"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-label">Last error"#))
    }

    func testHTMLRendererGroupsPinnedTodayAndArchivedChats() {
        var pinned = ChatThread(title: "Pinned chat", model: TrustedRouterDefaults.synthModel)
        pinned.isPinned = true
        let recent = ChatThread(title: "Recent chat", model: "z-ai/glm-5.2")
        var archived = ChatThread(title: "Archived chat", model: TrustedRouterDefaults.synthModel)
        archived.isArchived = true
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [recent, pinned, archived],
            selectedThreadID: recent.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Pinned"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Today"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Archived"#))
        XCTAssertTrue(html.contains("Pinned chat"))
        XCTAssertTrue(html.contains("Recent chat"))
        XCTAssertTrue(html.contains("Archived chat"))
    }

    func testHTMLRendererIncludesToolCardOutput() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "QuillCode")
        model.selectProject(projectID)
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card""#))
        XCTAssertTrue(html.contains(#"data-status="done""#))
        XCTAssertTrue(html.contains(#"data-density="collapsed""#))
        XCTAssertTrue(html.contains(#"data-execution-context="local""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-execution-context""#))
        XCTAssertTrue(html.contains(#"data-execution-context-kind="local">Local"#))
        XCTAssertTrue(html.contains("host.shell.run"))
        XCTAssertTrue(html.contains(#"data-testid="message-copy""#))
        XCTAssertTrue(html.contains(#"data-testid="message-use-as-draft""#))
        XCTAssertTrue(html.contains(#"data-testid="message-retry""#))
        XCTAssertTrue(html.contains(#"data-command-id="retry-last-turn""#))
        XCTAssertTrue(html.contains(#"data-testid="message-feedback-up""#))
        XCTAssertTrue(html.contains(#"data-testid="message-feedback-down""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-copy""#))
        XCTAssertTrue(html.contains("Copy output"))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-output""#))
        XCTAssertTrue(html.contains("Show details"))
    }

    func testHTMLToolCardRendererIncludesApprovalActions() {
        let card = ToolCardState(
            id: "shell-review",
            title: ToolDefinition.shellRun.name,
            subtitle: "Ready to run · whoami",
            status: .review,
            inputJSON: ToolArguments.json(["cmd": "whoami"]),
            actions: [
                ToolCardActionSurface(
                    title: "Run",
                    kind: .approve,
                    requestID: "approval-html",
                    style: .primary
                ),
                ToolCardActionSurface(
                    title: "Skip",
                    kind: .deny,
                    requestID: "approval-html",
                    style: .secondary
                )
            ],
            isExpanded: true
        )

        let html = WorkspaceHTMLToolCardRenderer.render(card, timelineItemID: "timeline-approval")

        XCTAssertTrue(html.contains(#"data-testid="tool-card-actions""#))
        XCTAssertTrue(html.contains(#"data-review-state="ready""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-status">Ready"#))
        XCTAssertTrue(html.contains(#"aria-label="host.shell.run, ready to run, expanded"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-action" data-action-kind="approve" data-action-style="primary" data-request-id="approval-html">Run"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-action" data-action-kind="deny" data-action-style="secondary" data-request-id="approval-html">Skip"#))
        XCTAssertTrue(html.contains(#"data-timeline-id="timeline-approval""#))
    }

    func testHTMLRendererIncludesToolCardArtifacts() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifacts""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact-label""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-artifact-detail""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-previews""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-label""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-text-preview-content""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-details""#))
        XCTAssertTrue(html.contains(#"data-density="collapsed""#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-details" open"#))
        XCTAssertTrue(html.contains(#"data-kind="file""#))
        XCTAssertTrue(html.contains("hello.txt"))
        XCTAssertTrue(html.contains("hello world"))
    }

    func testHTMLRendererIncludesImageArtifactPreview() throws {
        let screenshotPath = "/tmp/quillcode-preview/screenshot.png"
        let call = ToolCall(name: ToolDefinition.computerScreenshot.name, argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: #"{"width":1280,"height":720}"#, artifacts: [screenshotPath])
        let thread = ChatThread(
            title: "Screenshot",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.computer.screenshot queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.computer.screenshot completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-previews""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview""#))
        XCTAssertTrue(html.contains(#"src="file:///tmp/quillcode-preview/screenshot.png""#))
        XCTAssertTrue(html.contains(#"alt="screenshot.png""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-type">Image · PNG"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-label">screenshot.png"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-image-preview-detail">/tmp/quillcode-preview"#))
    }

    func testHTMLRendererIncludesDocumentArtifactPreview() throws {
        let documentPath = "/tmp/quillcode-preview/reports/briefing.pdf"
        let call = ToolCall(name: ToolDefinition.fileWrite.name, argumentsJSON: #"{"path":"briefing.pdf"}"#)
        let result = ToolResult(ok: true, stdout: "Wrote briefing.pdf\n", artifacts: [documentPath])
        let thread = ChatThread(
            title: "Document artifact",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.file.write queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.file.write completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-previews""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview""#))
        XCTAssertTrue(html.contains(#"data-kind="pdf""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">PDF · PDF"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">briefing.pdf"#))
        XCTAssertTrue(html.contains(#"href="file:///tmp/quillcode-preview/reports/briefing.pdf""#))
    }

    func testHTMLRendererIncludesAppshotArtifactPreview() throws {
        let appshotPath = "/tmp/quillcode-preview/appshots/checkout.appshot.json"
        let call = ToolCall(name: "host.appshot.capture", argumentsJSON: #"{"name":"checkout"}"#)
        let result = ToolResult(ok: true, stdout: "Captured checkout.appshot.json\n", artifacts: [appshotPath])
        let thread = ChatThread(
            title: "Appshot artifact",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.appshot.capture queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.appshot.capture completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview""#))
        XCTAssertTrue(html.contains(#"data-kind="appshot""#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-type">Appshot · APPSHOT"#))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-document-preview-label">checkout.appshot.json"#))
        XCTAssertTrue(html.contains(#"href="file:///tmp/quillcode-preview/appshots/checkout.appshot.json""#))
        XCTAssertFalse(html.contains(#"data-testid="tool-card-text-preview-label">checkout.appshot.json"#))
    }

    func testHTMLRendererKeepsToolCardsInTranscriptOrder() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())
        let userIndex = try XCTUnwrap(html.range(of: "run whoami")?.lowerBound)
        let toolIndex = try XCTUnwrap(html.range(of: "host.shell.run")?.lowerBound)
        let answerIndex = try XCTUnwrap(html.range(of: "You are `")?.lowerBound)

        XCTAssertLessThan(userIndex, toolIndex)
        XCTAssertLessThan(toolIndex, answerIndex)
    }

    func testHTMLRendererIncludesVisibleTerminalPane() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.toggleTerminal()
        await model.runTerminalCommand("printf renderer-ok", workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="terminal-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="terminal-cwd""#))
        XCTAssertTrue(html.contains(#"data-testid="terminal-entry""#))
        XCTAssertTrue(html.contains(#"data-testid="terminal-clear""#))
        XCTAssertTrue(html.contains("renderer-ok"))
    }

    func testHTMLRendererLabelsRunningAndStoppedTerminalEntries() {
        let model = QuillCodeWorkspaceModel(terminal: TerminalState(
            isVisible: true,
            isRunning: true,
            entries: [
                TerminalCommandState(
                    command: "sleep 5",
                    stdout: "",
                    stderr: "",
                    exitCode: nil,
                    ok: false,
                    status: .running
                ),
                TerminalCommandState(
                    command: "sleep 10",
                    stdout: "",
                    stderr: "Command stopped.",
                    exitCode: nil,
                    ok: false,
                    status: .stopped
                )
            ]
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains("Running · running"))
        XCTAssertTrue(html.contains("Stopped · stopped"))
        XCTAssertTrue(html.contains(#"class="terminal-status running""#))
        XCTAssertTrue(html.contains(#"class="terminal-status stopped""#))
    }

    func testHTMLRendererIncludesVisibleBrowserPane() throws {
        let model = QuillCodeWorkspaceModel()
        model.toggleBrowser()
        XCTAssertTrue(model.openBrowserPreview("localhost:5173"))
        XCTAssertTrue(model.addBrowserComment("Inspect responsive state"))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="browser-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-back" disabled"#))
        XCTAssertTrue(html.contains(#"data-testid="browser-forward" disabled"#))
        XCTAssertTrue(html.contains(#"data-testid="browser-reload" "#))
        XCTAssertTrue(html.contains(#"data-testid="browser-current-url""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-snapshot""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-source""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-inspection-depth""#))
        XCTAssertTrue(html.contains(#"data-depth="metadata_only""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-snapshot-outline""#))
        XCTAssertTrue(html.contains("Page: localhost"))
        XCTAssertTrue(html.contains("Local web app"))
        XCTAssertTrue(html.contains("Metadata only"))
        XCTAssertTrue(html.contains("http://localhost:5173"))
        XCTAssertTrue(html.contains(#"data-testid="browser-comment""#))
        XCTAssertTrue(html.contains("Inspect responsive state"))
    }

    func testHTMLRendererIncludesVisibleExtensionsPane() throws {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            extensionManifests: [
                ProjectExtensionManifest(
                    id: "mcp_server:filesystem",
                    kind: .mcpServer,
                    name: "Filesystem MCP",
                    summary: "Workspace MCP server.",
                    relativePath: ".quillcode/mcp/filesystem.json",
                    transport: .stdio,
                    launchExecutable: "quill-mcp",
                    launchCommand: "quill-mcp --root .",
                    launchArguments: ["--root", "."]
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            extensions: ExtensionsState(
                isVisible: true,
                mcpServerStatuses: ["mcp_server:filesystem": .ready],
                mcpServerProbeSummaries: [
                    "mcp_server:filesystem": MCPServerProbeSummary(
                        protocolVersion: "2024-11-05",
                        serverName: "Fixture MCP",
                        serverVersion: "1.0.0",
                        toolDescriptors: [
                            MCPToolDescriptor(
                                name: "read_file",
                                description: "Read a file",
                                requiredArguments: ["path"],
                                schemaSummary: "required: path:string"
                            )
                        ]
                    )
                ]
            )
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="extensions-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-item""#))
        XCTAssertTrue(html.contains("Filesystem MCP"))
        XCTAssertTrue(html.contains(#"data-testid="extension-transport""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-stop""#))
        XCTAssertTrue(html.contains(#"data-testid="extension-mcp-tool-schema">required: path:string · Read a file"#))
        XCTAssertTrue(html.contains(".quillcode/mcp/filesystem.json"))
    }

    func testHTMLRendererIncludesVisibleMemoriesPane() throws {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            memories: [
                MemoryNote(
                    id: "project:.quillcode/memories/project.md",
                    scope: .project,
                    title: "Project",
                    content: "Use SwiftUI surfaces for visible state.",
                    relativePath: ".quillcode/memories/project.md",
                    byteCount: 38
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            memories: MemoriesState(isVisible: true)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="memories-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="memory-item""#))
        XCTAssertTrue(html.contains("Project"))
        XCTAssertTrue(html.contains(".quillcode/memories/project.md"))
    }

    func testHTMLRendererIncludesGitReviewPane() throws {
        let diff = """
        diff --git a/Package.swift b/Package.swift
        --- a/Package.swift
        +++ b/Package.swift
        @@ -1 +1,2 @@
        +// QuillCode
         import PackageDescription
        """
        let call = ToolCall(name: "host.git.diff", argumentsJSON: "{}")
        let result = ToolResult(ok: true, stdout: diff)
        let comment = WorkspaceReviewCommentState(path: "Package.swift", text: "Confirm package tools version.")
        let thread = ChatThread(
            title: "Git diff",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Package.swift", payloadJSON: try JSONHelpers.encodePretty(comment))
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="review-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="review-file""#))
        XCTAssertTrue(html.contains(#"data-testid="review-action""#))
        XCTAssertTrue(html.contains(#"data-testid="review-hunk""#))
        XCTAssertTrue(html.contains(#"data-testid="review-line""#))
        XCTAssertTrue(html.contains(#"data-testid="review-comment""#))
        XCTAssertTrue(html.contains(#"data-action="stage""#))
        XCTAssertTrue(html.contains(#"data-action="restore""#))
        XCTAssertTrue(html.contains(#"data-action="stage_hunk""#))
        XCTAssertTrue(html.contains(#"data-action="restore_hunk""#))
        XCTAssertTrue(html.contains("Package.swift"))
        XCTAssertTrue(html.contains("Confirm package tools version."))
        XCTAssertTrue(html.contains("Stage"))
        XCTAssertTrue(html.contains("Restore"))
        XCTAssertTrue(html.contains("1 file changed, +1 -0"))
    }

}
