import XCTest
import QuillCodeAgent
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
        XCTAssertEqual(surface.topBar.modelLabel, TrustedRouterDefaults.defaultModel)
        XCTAssertEqual(surface.topBar.selectedModelID, TrustedRouterDefaults.defaultModel)
        XCTAssertTrue(surface.topBar.modelCategories.contains { $0.category == "Recommended" })
        XCTAssertTrue(surface.topBar.modelCategories.flatMap(\.models).contains { $0.id == TrustedRouterDefaults.defaultModel && $0.isSelected })
        XCTAssertEqual(surface.topBar.modeLabel, "Auto")
        XCTAssertEqual(surface.topBar.instructionLabel, "No project instructions")
        XCTAssertEqual(surface.topBar.instructionSources, [])
        XCTAssertEqual(surface.projects.items.count, 1)
        XCTAssertEqual(surface.projects.items[0].name, "QuillCode")
        XCTAssertEqual(surface.projects.items[0].path, "/tmp/QuillCode")
        XCTAssertTrue(surface.projects.items[0].isSelected)
        XCTAssertEqual(surface.sidebar.items.count, 1)
        XCTAssertEqual(surface.sidebar.items[0].title, "Run whoami")
        XCTAssertTrue(surface.sidebar.items[0].isSelected)
        XCTAssertEqual(surface.sidebar.items[0].actions.map(\.kind), [.pin, .archive])
        XCTAssertEqual(surface.transcript.messages.count, 2)
        XCTAssertEqual(surface.composer.placeholder, "Message QuillCode")
        XCTAssertTrue(surface.composer.canSend)
        XCTAssertEqual(surface.commands.map(\.id), [
            "new-chat",
            "search",
            "add-project",
            "toggle-terminal",
            "toggle-browser",
            "git-pr-create",
            "git-worktree-list",
            "git-worktree-create",
            "git-worktree-remove",
            "stop-all",
            "settings",
            "command-palette",
            "computer-use-setup"
        ])
        XCTAssertEqual(surface.settings.apiBaseURL, TrustedRouterDefaults.defaultAPIBaseURL)
        XCTAssertFalse(surface.settings.developerOverrideEnabled)
        XCTAssertFalse(surface.settings.hasStoredAPIKey)
        XCTAssertEqual(surface.settings.apiKeyStatusLabel, "No API key saved")
        XCTAssertFalse(surface.terminal.isVisible)
        XCTAssertEqual(surface.terminal.cwdLabel, "/tmp/QuillCode")
        XCTAssertFalse(surface.browser.isVisible)
    }

    func testSurfaceGroupsCustomModelCatalogByCategory() {
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            config: AppConfig(defaultModel: "acme/code-pro"),
            topBar: TopBarState(model: "acme/code-pro")
        ))
        model.setModelCatalog([
            .init(id: "trustedrouter/fusion", provider: "trustedrouter", displayName: "Fusion", category: "Recommended"),
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "acme/fast", provider: "acme", displayName: "Fast", category: "Coding")
        ])

        let surface = model.surface()

        XCTAssertEqual(surface.topBar.modelLabel, "acme/Code Pro")
        XCTAssertEqual(surface.topBar.modelCategories.map(\.category), ["Recommended", "Coding"])
        let coding = surface.topBar.modelCategories.first { $0.category == "Coding" }
        XCTAssertEqual(coding?.models.map(\.id), ["acme/code-pro", "acme/fast"])
        XCTAssertTrue(coding?.models.first?.isSelected == true)
    }

    func testSurfaceIncludesLocalEnvironmentActionCommands() {
        let project = ProjectRef(
            name: "QuillCode",
            path: "/tmp/QuillCode",
            localActions: [
                LocalEnvironmentAction(
                    id: "local-env:.quillcode/actions/bootstrap.sh",
                    title: "Bootstrap",
                    relativePath: ".quillcode/actions/bootstrap.sh",
                    command: "sh '.quillcode/actions/bootstrap.sh'"
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
        XCTAssertEqual(current?.models.first?.displayName, "edge-model")
        XCTAssertTrue(current?.models.first?.isSelected == true)
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

    func testSidebarSearchFiltersByThreadTitleSubtitleAndTranscriptContent() {
        let selectedThread = ChatThread(title: "Run whoami", model: "trustedrouter/fusion")
        var otherThread = ChatThread(title: "Review git diff", model: "z-ai/glm-5.2", isPinned: true)
        otherThread.messages = [
            .init(role: .user, content: "Can you inspect the browser preview?")
        ]
        let surface = SidebarSurface(
            items: [
                SidebarItemSurface(item: SidebarItem(thread: selectedThread), selectedThreadID: selectedThread.id),
                SidebarItemSurface(item: SidebarItem(thread: otherThread), selectedThreadID: selectedThread.id)
            ],
            selectedThreadID: selectedThread.id
        )

        XCTAssertEqual(surface.filteredItems(matching: "").map(\.title), ["Run whoami", "Review git diff"])
        XCTAssertEqual(surface.filteredItems(matching: "who").map(\.title), ["Run whoami"])
        XCTAssertEqual(surface.filteredItems(matching: "GLM").map(\.title), ["Review git diff"])
        XCTAssertEqual(surface.filteredItems(matching: "browser preview").map(\.title), ["Review git diff"])
        XCTAssertTrue(surface.filteredItems(matching: "workspace manager").isEmpty)
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
        let staleComment = WorkspaceReviewCommentState(path: "README.md", text: "This file is no longer in the diff.")
        let thread = ChatThread(
            title: "Review changes",
            events: [
                ThreadEvent(kind: .toolQueued, summary: "host.git.diff queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                ThreadEvent(kind: .toolCompleted, summary: "host.git.diff completed", payloadJSON: try JSONHelpers.encodePretty(result)),
                ThreadEvent(kind: .reviewComment, summary: "Commented on Sources/App.swift", payloadJSON: try JSONHelpers.encodePretty(matchingComment)),
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
        XCTAssertTrue(html.contains(#"data-testid="sidebar""#))
        XCTAssertTrue(html.contains(#"data-testid="add-project-button""#))
        XCTAssertTrue(html.contains(#"data-testid="project-item""#))
        XCTAssertTrue(html.contains(#"data-testid="transcript""#))
        XCTAssertTrue(html.contains(#"data-testid="composer""#))
        XCTAssertTrue(html.contains(#"data-testid="project-instructions-status""#))
        XCTAssertTrue(html.contains("1 instruction file loaded"))
        XCTAssertTrue(html.contains("AGENTS.md"))
        XCTAssertTrue(html.contains("Unsafe &lt;title&gt;"))
        XCTAssertTrue(html.contains("Unsafe &lt;project&gt;"))
        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
    }

    func testHTMLRendererIncludesToolCardOutput() async throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="tool-card""#))
        XCTAssertTrue(html.contains(#"data-status="done""#))
        XCTAssertTrue(html.contains("host.shell.run"))
        XCTAssertTrue(html.contains(#"data-testid="tool-card-output""#))
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
        XCTAssertTrue(html.contains("renderer-ok"))
    }

    func testHTMLRendererIncludesVisibleBrowserPane() throws {
        let model = QuillCodeWorkspaceModel()
        model.toggleBrowser()
        XCTAssertTrue(model.openBrowserPreview("localhost:5173"))
        XCTAssertTrue(model.addBrowserComment("Inspect responsive state"))

        let html = WorkspaceHTMLRenderer.render(model.surface())

        XCTAssertTrue(html.contains(#"data-testid="browser-pane""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-preview""#))
        XCTAssertTrue(html.contains(#"data-testid="browser-current-url""#))
        XCTAssertTrue(html.contains("http://localhost:5173"))
        XCTAssertTrue(html.contains(#"data-testid="browser-comment""#))
        XCTAssertTrue(html.contains("Inspect responsive state"))
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

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeSurfaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
