import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceHTMLChromeRendererTests: XCTestCase {
    private func makeTempDirectory(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("html-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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
        var thread = ChatThread(
            title: "Unsafe <title>",
            goal: ThreadGoal(objective: "Ship <safely>")
        )
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
        XCTAssertTrue(html.contains(#"data-testid="top-bar-navigation""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-back""#))
        XCTAssertTrue(html.contains(#"data-command-id="workspace-back""#))
        XCTAssertTrue(html.contains(#"title="Back unavailable""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-forward""#))
        XCTAssertTrue(html.contains(#"data-command-id="workspace-forward""#))
        XCTAssertTrue(html.contains(#"title="Forward unavailable""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-clusters""#))
        XCTAssertTrue(html.contains(#"data-sidebar-visible="true""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-primary-cluster""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-subtitle""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-goal""#))
        XCTAssertTrue(html.contains(#"data-tone="active""#))
        XCTAssertTrue(html.contains("Ship &lt;safely&gt;"))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-status-metadata""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-context-cluster""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-status-button""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-status-menu""#))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-status-popover""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-compose-zone""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-threads-zone""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-projects-zone""#))
        assertCommandButton(html, testID: "new-chat-button", commandID: "new-chat", title: "New chat")
        assertCommandButton(html, testID: "sidebar-search-button", commandID: "search", title: "Search")
        assertCommandButton(html, testID: "extensions-button", commandID: "toggle-extensions", title: "Plugins")
        assertCommandButton(html, testID: "automations-button", commandID: "toggle-automations", title: "Automations")
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-menu""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-button""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-section" data-command-group="navigate""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-tools-section-title">Navigate"#))
        assertCommandButton(html, testID: "command-palette-button", commandID: "command-palette", title: "Command palette")
        XCTAssertTrue(html.contains(#"role="menuitem""#))
        XCTAssertFalse(html.contains(#"data-testid="sidebar-tools-section" data-command-group="extensions""#))
        XCTAssertFalse(html.contains(#"data-testid="sidebar-tools-section-title">Extensions"#))
        XCTAssertFalse(html.contains(#"data-testid="sidebar-tools-section" data-command-group="automate""#))
        XCTAssertFalse(html.contains(#"data-testid="sidebar-tools-section-title">Automate"#))
        XCTAssertFalse(html.contains(#"data-testid="sidebar-search-button" role="menuitem""#))
        XCTAssertFalse(html.contains(#"data-testid="extensions-button" role="menuitem""#))
        XCTAssertFalse(html.contains(#"data-testid="automations-button" role="menuitem""#))
        XCTAssertTrue(html.contains(#"data-testid="settings-button""#))
        XCTAssertFalse(html.contains(#"class="sidebar-utility-strip""#))
        XCTAssertFalse(html.contains(#"class="sidebar-workspace-actions""#))
        assertCommandButton(html, testID: "add-project-button", commandID: "add-project", title: "+")
        XCTAssertTrue(html.contains(#"data-testid="project-item""#))
        XCTAssertTrue(html.contains(#"data-testid="project-selection-badge">Current</small>"#))
        XCTAssertTrue(html.contains(#"aria-label="Current project, Unsafe &lt;project&gt;, Local, /tmp/unsafe""#))
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
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-toggle-sidebar""#))
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-search""#))
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-settings""#))
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-keyboard-shortcuts""#))
        XCTAssertTrue(idleHTML.contains(#"data-testid="top-bar-overflow-search""#))
        XCTAssertTrue(idleHTML.contains(#"class="hit-target-row" data-hit-target-kind="row" data-hit-target-action="press" data-hit-target-source="explicit""#))
        XCTAssertTrue(idleHTML.contains(#"role="menuitem""#))
        XCTAssertFalse(idleHTML.contains(#"data-testid="top-bar-overflow-stop-all""#))
        XCTAssertFalse(idleHTML.contains(#"data-testid="top-bar-overflow-disconnect-all""#))
        XCTAssertFalse(idleHTML.contains(#"data-testid="top-bar-stop-button""#))

        let activeHTML = WorkspaceHTMLRenderer.render(activeRunModel().surface())
        XCTAssertFalse(activeHTML.contains(#"data-testid="top-bar-overflow-stop-all""#))
        XCTAssertFalse(activeHTML.contains(#"data-testid="top-bar-overflow-disconnect-all""#))
        XCTAssertTrue(activeHTML.contains(#"data-testid="top-bar-stop-button""#))
        XCTAssertTrue(activeHTML.contains(#"aria-label="Stop active work""#))

        let remoteConnection = ProjectConnection.ssh(path: "/srv/quill", host: "feather.local", user: "quill")
        let remoteProject = ProjectRef(name: "Feather", path: remoteConnection.path, connection: remoteConnection)
        let remoteHTML = WorkspaceHTMLRenderer.render(
            QuillCodeWorkspaceModel(root: QuillCodeRootState(
                projects: [remoteProject],
                selectedProjectID: remoteProject.id
            )).surface()
        )
        XCTAssertTrue(remoteHTML.contains(#"data-testid="top-bar-overflow-disconnect-all""#))
    }

    func testHTMLRendererShowsWorktreeTopBarStatusAndDanglingWarning() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/quillcode")
        var thread = ChatThread(title: "Feature", projectID: project.id)
        let worktree = try makeTempDirectory("worktree")
        thread.worktree = WorktreeBinding(path: worktree.path, branch: "feature/ui", base: "main")
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="top-bar-worktree""#))
        XCTAssertTrue(html.contains(#"data-tone="normal""#))
        XCTAssertTrue(html.contains("Worktree feature/ui"))
        XCTAssertTrue(html.contains("Base: main."))
        XCTAssertTrue(html.contains(worktree.path))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-worktree-branch""#))
        XCTAssertTrue(html.contains("⑂ ui"))

        var dangling = thread
        dangling.worktree = WorktreeBinding(
            path: "/tmp/quillcode-missing-\(UUID().uuidString)",
            branch: "feature/gone"
        )
        let warningHTML = WorkspaceHTMLRenderer.render(QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [dangling],
            selectedThreadID: dangling.id
        )).surface())

        XCTAssertTrue(warningHTML.contains(#"data-testid="top-bar-worktree""#))
        XCTAssertTrue(warningHTML.contains(#"data-tone="warning""#))
        XCTAssertTrue(warningHTML.contains("Worktree feature/gone"))
        XCTAssertTrue(warningHTML.contains("Runs fall back to the project root"))
    }

    func testHTMLRendererShowsLocalHandoffStatusInTopBarAndSidebar() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/quillcode")
        let worktree = try makeTempDirectory("local-associated-worktree")
        var thread = ChatThread(title: "Managed task", projectID: project.id)
        thread.worktree = WorktreeBinding(
            path: worktree.path,
            branch: "",
            base: "main",
            location: .local
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="top-bar-worktree""#))
        XCTAssertTrue(html.contains(">Local</span>"))
        XCTAssertTrue(html.contains("local checkout"))
        XCTAssertTrue(html.contains(worktree.path))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-worktree-local""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-handoff-button""#))
        XCTAssertTrue(html.contains(#"aria-label="Hand off to Worktree""#))
        XCTAssertTrue(html.contains(#"data-command-id="thread-handoff""#))
    }

    func testHTMLRendererShowsSavedWorktreeAndRestoreAction() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/quillcode")
        var thread = ChatThread(title: "Archived task", projectID: project.id)
        thread.worktree = WorktreeBinding(
            path: "/tmp/quillcode-missing-\(UUID().uuidString)",
            branch: "",
            snapshot: WorktreeSnapshotReference(
                headCommit: String(repeating: "a", count: 40),
                fileCount: 1,
                byteCount: 24
            )
        )
        let html = WorkspaceHTMLRenderer.render(QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        )).surface())

        XCTAssertTrue(html.contains("Worktree saved"))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-worktree-snapshot""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-restore-worktree-button""#))
        XCTAssertTrue(html.contains(#"data-command-id="thread-restore-worktree""#))
        XCTAssertFalse(html.contains(#"data-testid="sidebar-worktree-warning""#))
    }

    func testHTMLRendererShowsCreateBranchOnlyForDetachedWorktreeTask() throws {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/quillcode")
        let worktree = try makeTempDirectory("detached-create-branch")
        var thread = ChatThread(title: "Detached task", projectID: project.id)
        thread.worktree = WorktreeBinding(
            path: worktree.path,
            branch: "",
            base: "main",
            location: .worktree
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let detachedHTML = WorkspaceHTMLRenderer.render(model.surface())
        XCTAssertTrue(detachedHTML.contains(#"data-testid="top-bar-create-branch-button""#))
        XCTAssertTrue(detachedHTML.contains(#"data-command-id="thread-create-branch""#))

        model.root.threads[0].worktree?.branch = "feature/owned"
        let ownedHTML = WorkspaceHTMLRenderer.render(model.surface())
        XCTAssertFalse(ownedHTML.contains(#"data-testid="top-bar-create-branch-button""#))
        XCTAssertFalse(ownedHTML.contains(#"data-testid="top-bar-handoff-button""#))
    }

    func testHTMLRendererHidesSidebarAndExpandsWorkspaceGrid() {
        let model = QuillCodeWorkspaceModel(chrome: WorkspaceChromeState(isSidebarVisible: false))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-sidebar-visible="false""#))
        XCTAssertTrue(html.contains(#"sidebar-hidden""#))
        XCTAssertFalse(html.contains(#"data-testid="sidebar""#))
        XCTAssertTrue(html.contains(#"data-testid="transcript""#))
        XCTAssertTrue(html.contains(#"data-testid="top-bar-overflow-toggle-sidebar""#))
    }

    func testHTMLRendererKeepsActivityGridWhenSidebarIsHidden() {
        let model = QuillCodeWorkspaceModel(
            chrome: WorkspaceChromeState(isSidebarVisible: false),
            activity: ActivityState(isVisible: true)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"class="workspace-grid sidebar-hidden with-activity""#))
        XCTAssertFalse(html.contains(#"data-testid="sidebar""#))
        XCTAssertTrue(html.contains(#"data-testid="activity-pane""#))
    }

    func testHTMLRendererShowsStopButtonDuringActiveSend() {
        let model = activeRunModel()

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="top-bar-stop-button""#))
        XCTAssertTrue(html.contains(#"data-testid="stop-button""#))
        XCTAssertTrue(html.contains(">Stop</button>"))
        XCTAssertTrue(html.contains(#"<textarea class="hit-target-text-entry" data-hit-target-kind="text-entry" data-hit-target-action="text-input" data-hit-target-source="explicit" id="message""#))
        XCTAssertTrue(html.contains(#"aria-label="Message""#))
        XCTAssertTrue(html.contains(#"rows="1""#))
        XCTAssertTrue(html.contains("disabled"))
        XCTAssertFalse(html.contains(#"data-testid="send-button""#))
    }

    private func activeRunModel() -> QuillCodeWorkspaceModel {
        let thread = ChatThread(title: "Running")
        return QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            composer: ComposerState(isSending: true),
            agentRuns: WorkspaceAgentRunRegistry(statusesByThreadID: [thread.id: "Working"])
        )
    }

    func testHTMLRendererSendButtonUsesTextHitTargetForItsLabel() {
        let html = WorkspaceHTMLRenderer.render(QuillCodeWorkspaceModel().surface())

        // The "Send" label is a word, not a glyph, so it must use a text hit
        // target that grows with its content. A fixed icon-sized (44pt square)
        // target clips the label, matching the active-send "Stop" sibling.
        XCTAssertTrue(html.contains(
            #"class="hit-target-text" data-hit-target-kind="text" data-hit-target-action="press" data-hit-target-source="explicit" data-testid="send-button""#
        ))
        XCTAssertTrue(html.contains(">Send</button>"))
        XCTAssertFalse(html.contains(
            #"data-hit-target-kind="icon" data-hit-target-action="press" data-hit-target-source="explicit" data-testid="send-button""#
        ))
    }

    func testHTMLRendererIncludesEmptyStarterActions() {
        let html = WorkspaceHTMLRenderer.render(QuillCodeWorkspaceModel().surface())

        XCTAssertTrue(html.contains(#"data-testid="transcript-empty""#))
        XCTAssertTrue(html.contains(#"data-testid="empty-starter-actions""#))
        XCTAssertTrue(html.contains(#"data-testid="empty-starter-action" data-action-id="review-changes""#))
        XCTAssertTrue(html.contains(#"Review the current git diff and call out risks, missing tests, and next steps."#))
        XCTAssertTrue(html.contains("Run tests"))
        XCTAssertTrue(html.contains("Explain project"))
    }

    func testHTMLRendererIncludesOptimisticThinkingSurface() {
        let thread = ChatThread(
            messages: [.init(role: .user, content: "run tests")],
            events: [
                .init(kind: .message, summary: "run tests"),
                .init(kind: .toolQueued, summary: "host.shell.run queued")
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            composer: ComposerState(isSending: true)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains("run tests"))
        XCTAssertTrue(html.contains(#"data-testid="thinking-indicator""#))
        XCTAssertTrue(html.contains(#"data-testid="thinking-title">Thinking"#))
        XCTAssertTrue(html.contains(#"data-testid="thinking-subtitle">Queued: Shell command queued"#))
        XCTAssertTrue(html.contains(#"data-testid="thinking-trace""#))
        XCTAssertFalse(html.contains(#"data-testid="transcript-empty""#))
    }

    func testHTMLRendererUsesMultilineComposer() {
        let model = QuillCodeWorkspaceModel(composer: ComposerState(
            draft: "first line\nsecond line"
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"<textarea class="hit-target-text-entry" data-hit-target-kind="text-entry" data-hit-target-action="text-input" data-hit-target-source="explicit" id="message""#))
        XCTAssertTrue(html.contains(#"aria-label="Message""#))
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
        XCTAssertTrue(html.contains(#"data-testid="context-fork-summary""#))
        XCTAssertTrue(html.contains(#"data-testid="context-fork-full""#))
        XCTAssertTrue(html.contains(#"data-testid="context-compact""#))
    }

    func testHTMLRendererIncludesContextSummaryProgress() throws {
        let thread = ChatThread(
            title: "Long context",
            messages: [
                .init(role: .user, content: String(repeating: "token ", count: 26_000))
            ],
            events: [
                ThreadEvent(
                    kind: .notice,
                    summary: WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary)
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="context-banner-progress""#))
        XCTAssertTrue(html.contains(#"data-testid="context-banner-progress-title">Summarizing fork"#))
        XCTAssertTrue(html.contains(#"data-active-command-id="fork-with-summary""#))
        XCTAssertTrue(html.contains(#"data-testid="context-fork-summary""#))
        XCTAssertTrue(html.contains(#"data-command-id="fork-with-summary""#))
        XCTAssertTrue(html.contains(#"disabled aria-disabled="true">Fork summary"#))
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
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-label">Recovery route"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-value">retry-last-turn"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-label">Recovery reason"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-value">empty-response"#))
        XCTAssertTrue(html.contains(#"data-testid="runtime-diagnostic-label">Recovery command"#))
    }

    func testHTMLRendererGroupsPinnedTodayAndArchivedChats() {
        var pinned = ChatThread(title: "Pinned chat", model: TrustedRouterDefaults.prometheusModel)
        pinned.isPinned = true
        let recent = ChatThread(title: "Recent chat", model: "z-ai/glm-5.2")
        var archived = ChatThread(title: "Archived chat", model: TrustedRouterDefaults.prometheusModel)
        archived.isArchived = true
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [recent, pinned, archived],
            selectedThreadID: recent.id
        ))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="sidebar-filter-bar""#))
        XCTAssertTrue(html.contains(#"data-command-id="sidebar-filter:all""#))
        XCTAssertTrue(html.contains(#"data-command-id="sidebar-filter:pinned""#))
        XCTAssertTrue(html.contains(#"data-command-id="sidebar-filter:recent""#))
        XCTAssertTrue(html.contains(#"data-command-id="sidebar-filter:archived""#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Pinned"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Today"#))
        XCTAssertTrue(html.contains(#"data-testid="sidebar-section-title">Archived"#))
        XCTAssertTrue(html.contains("Pinned chat"))
        XCTAssertTrue(html.contains("Recent chat"))
        XCTAssertTrue(html.contains("Archived chat"))
    }

    private func assertCommandButton(
        _ html: String,
        testID: String,
        commandID: String,
        title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(html.contains(#"data-testid="\#(testID)""#), file: file, line: line)
        XCTAssertTrue(html.contains(#"data-command-id="\#(commandID)""#), file: file, line: line)
        XCTAssertTrue(html.contains(#">\#(title)</button>"#), file: file, line: line)
    }
}
