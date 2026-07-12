import XCTest
import QuillCodeCore
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
            .prefix(TrustedRouterDefaults.recommendedModelIDs.count)
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
        XCTAssertEqual(
            surface.projects.items[0].actions.map(\.kind),
            [.newChat, .refreshContext, .moveToTop, .moveUp, .moveDown, .moveToBottom, .rename, .remove]
        )
        XCTAssertEqual(surface.projects.items[0].actions.first { $0.kind == .moveToTop }?.isEnabled, false)
        XCTAssertEqual(surface.projects.items[0].actions.first { $0.kind == .moveUp }?.isEnabled, false)
        XCTAssertEqual(surface.projects.items[0].actions.first { $0.kind == .moveDown }?.isEnabled, false)
        XCTAssertEqual(surface.projects.items[0].actions.first { $0.kind == .moveToBottom }?.isEnabled, false)
        XCTAssertEqual(
            surface.projects.items[0].actions.first { $0.kind == .moveToTop }?.disabledReason,
            "Already at the top"
        )
        XCTAssertEqual(surface.projects.items[0].actions.first { $0.kind == .moveUp }?.isEnabled, false)
        XCTAssertEqual(surface.projects.items[0].actions.first { $0.kind == .moveDown }?.isEnabled, false)
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
            "thread-new-worktree",
            "thread-create-branch",
            "thread-handoff",
            "sidebar-filter:all",
            "sidebar-filter:pinned",
            "sidebar-filter:recent",
            "sidebar-filter:archived",
            "thread-rename",
            "thread-duplicate",
            "thread-pin",
            "thread-unpin",
            "thread-clear",
            "thread-revert-latest",
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
            "fork-with-summary",
            "fork-full-context",
            "compact-context",
            "sidebar-saved-search-create",
            "retry-last-turn",
            "workspace-back",
            "workspace-forward",
            "search",
            "find-in-chat",
            "copy-conversation",
            "export-conversation-markdown",
            "cycle-mode",
            "focus-composer",
            "toggle-sidebar",
            "add-project",
            "add-ssh-project",
            "project-new-chat",
            "project-refresh-context",
            "project-init",
            "project-move-to-top",
            "project-move-up",
            "project-move-down",
            "project-move-to-bottom",
            "project-rename",
            "project-remove",
            "toggle-terminal",
            "terminal-clear",
            "toggle-browser",
            "browser-back",
            "browser-forward",
            "browser-reload",
            "open-browser-session",
            "toggle-activity",
            "toggle-automations",
            "automation-create-thread-follow-up",
            "automation-create-workspace-schedule",
            "automation-create-monitor",
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
            "show-skills",
            "git-status",
            "git-diff",
            "git-fetch",
            "git-pull",
            "git-branch-list",
            "git-branch-switch",
            "git-pr-create",
            "git-pr-fill",
            "git-pr-list",
            "git-pr-view",
            "git-pr-checks",
            "git-pr-diff",
            "git-pr-checkout",
            "git-pr-reviewers",
            "git-pr-comment",
            "git-pr-review",
            "git-pr-review-comment",
            "git-pr-review-reply",
            "git-pr-review-threads",
            "git-pr-review-thread",
            "git-pr-labels",
            "git-pr-lifecycle",
            "git-pr-merge",
            "git-worktree-list",
            "git-worktree-create",
            "git-worktree-open",
            "git-worktree-remove",
            "git-worktree-prune",
            "stop-all",
            "disconnect-all",
            "settings",
            "command-palette",
            "keyboard-shortcuts",
            "computer-use-setup",
            "computer-use-open-screen-recording",
            "computer-use-open-accessibility",
            "computer-use-refresh"
        ])
        XCTAssertEqual(surface.commands.first { $0.id == "fork-from-last" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-with-summary" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "fork-full-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "compact-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "find-in-chat" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "project-move-up" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "project-move-to-bottom" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "open-browser-session" }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-activity" }?.shortcut, "Cmd+Shift+A")
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-automations" }?.shortcut, "Cmd+Option+A")
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-memories" }?.shortcut, "Cmd+Shift+M")
        XCTAssertEqual(surface.commands.first { $0.id == "toggle-extensions" }?.shortcut, "Cmd+Shift+X")
        XCTAssertEqual(surface.commands.first { $0.id == "disconnect-all" }?.isEnabled, false)
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
        XCTAssertEqual(item.actions.map(\.kind), [.newChat, .refreshContext, .moveToTop, .moveUp, .moveDown, .moveToBottom, .rename, .remove])
        XCTAssertEqual(item.actions.first { $0.kind == .refreshContext }?.isEnabled, true)
        XCTAssertNil(item.actions.first { $0.kind == .refreshContext }?.disabledReason)
        XCTAssertEqual(item.actions.first { $0.kind == .moveToTop }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveUp }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveDown }?.isEnabled, false)
        XCTAssertEqual(item.actions.first { $0.kind == .moveToBottom }?.isEnabled, false)
        XCTAssertEqual(surface.commands.first { $0.id == "project-refresh-context" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-status" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-diff" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-fetch" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pull" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-view" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checks" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-diff" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-checkout" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-reviewers" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-comment" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review-comment" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review-reply" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review-threads" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-review-thread" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-labels" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-lifecycle" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-pr-merge" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-list" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-create" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-remove" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "git-worktree-prune" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "add-ssh-project" }?.isEnabled, true)
        XCTAssertEqual(surface.commands.first { $0.id == "add-ssh-project" }?.title, "Project: Add SSH Remote...")
        XCTAssertEqual(surface.commands.first { $0.id == "disconnect-all" }?.isEnabled, true)
        XCTAssertEqual(surface.terminal.cwdLabel, "ssh://quill@feather.local:2222/srv/quill")
    }

    func testDisconnectAllDetachesSelectedSSHProjectWithoutRemovingIt() throws {
        let connection = ProjectConnection.ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let thread = ChatThread(title: "Remote work", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertEqual(model.surface().commands.first { $0.id == "disconnect-all" }?.isEnabled, true)
        XCTAssertTrue(model.runWorkspaceCommand("disconnect-all", workspaceRoot: try makeTempDirectory()))
        XCTAssertNil(model.root.selectedProjectID)
        XCTAssertNil(model.root.selectedThreadID)
        XCTAssertEqual(model.root.projects, [project])
        XCTAssertEqual(model.root.threads.first?.projectID, project.id)
        XCTAssertEqual(model.surface().commands.first { $0.id == "disconnect-all" }?.isEnabled, false)
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

    func testStopAllCommandIsEnabledForTerminalRuns() {
        let model = QuillCodeWorkspaceModel(terminal: TerminalState(isRunning: true))

        let command = model.surface().commands.first { $0.id == "stop-all" }

        XCTAssertEqual(command?.isEnabled, true)
    }

    func testEmptySurfaceShowsCodexLikeEmptyState() {
        let surface = QuillCodeWorkspaceModel().surface()

        XCTAssertEqual(surface.topBar.primaryTitle, "QuillCode")
        XCTAssertEqual(surface.sidebar.items.count, 0)
        XCTAssertEqual(surface.transcript.emptyTitle, "Ask QuillCode to inspect, edit, or run this project.")
        XCTAssertEqual(surface.transcript.emptyStarterActions.map(\.title), [
            "Review changes",
            "Run tests",
            "Explain project"
        ])
        XCTAssertFalse(surface.review.isVisible)
        XCTAssertFalse(surface.composer.canSend)
        XCTAssertTrue(surface.topBar.showsComputerUseSetup)
    }

}
