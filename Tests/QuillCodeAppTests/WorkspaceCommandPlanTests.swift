import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceCommandPlanTests: XCTestCase {
    func testToolCommandsUseCanonicalToolNames() throws {
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-status"),
            .runTool(name: ToolDefinition.gitStatus.name)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-diff"),
            .runTool(name: ToolDefinition.gitDiff.name)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-view"),
            .runTool(name: ToolDefinition.gitPullRequestView.name)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-checks"),
            .runTool(name: ToolDefinition.gitPullRequestChecks.name)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-diff"),
            .runTool(name: ToolDefinition.gitPullRequestDiff.name)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-review-threads"),
            .runTool(name: ToolDefinition.gitPullRequestReviewThreads.name)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-worktree-list"),
            .runTool(name: ToolDefinition.gitWorktreeList.name)
        )
        guard case .runToolCall(let pruneCall) = WorkspaceCommandPlan(commandID: "git-worktree-prune") else {
            return XCTFail("Expected git worktree prune to dispatch an explicit tool call.")
        }
        let pruneArguments = try ToolArguments(pruneCall.argumentsJSON)
        XCTAssertEqual(pruneCall.name, ToolDefinition.gitWorktreePrune.name)
        XCTAssertEqual(pruneArguments.bool("dryRun"), true)
        XCTAssertEqual(pruneArguments.bool("verbose"), true)
    }

    func testDraftCommandsMapToComposerText() {
        XCTAssertEqual(WorkspaceCommandPlan(commandID: "memory-add"), .setDraft("/remember "))
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "add-ssh-project"),
            .setDraft("/ssh user@host:/absolute/path")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-create"),
            .setDraft("Create a pull request titled ")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-review-comment"),
            .setDraft("Comment on a pull request line: ")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-review-reply"),
            .setDraft("Reply to pull request review comment: ")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-review-thread"),
            .setDraft("Resolve pull request review thread: ")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-worktree-remove"),
            .setDraft("Remove git worktree at ")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-worktree-open"),
            .setDraft("Open git worktree at ")
        )
    }

    func testPullRequestReviewCommandOpensStructuredDraftAction() {
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-pr-review"),
            .action(.pullRequestReviewDraft)
        )
    }

    func testPrefixCommandsParseStructuredValues() {
        let id = UUID()
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "local-env:bootstrap"),
            .localEnvironmentAction("local-env:bootstrap")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "memory-edit:global-note"),
            .editMemory(id: "global-note")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "memory-delete:global-note"),
            .deleteMemory(id: "global-note")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-pause:\(id.uuidString)"),
            .updateAutomationStatus(id: id, status: .paused)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-resume:\(id.uuidString)"),
            .updateAutomationStatus(id: id, status: .active)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-run:\(id.uuidString)"),
            .runAutomation(id: id)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-delete:\(id.uuidString)"),
            .deleteAutomation(id: id)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "mcp-start:mcp_server:filesystem"),
            .startMCPServer(id: "mcp_server:filesystem")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "mcp-stop:mcp_server:filesystem"),
            .stopMCPServer(id: "mcp_server:filesystem")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "mcp-resource:mcp_server:filesystem:1"),
            .readMCPResource(serverID: "mcp_server:filesystem", index: 1)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "mcp-prompt:mcp_server:filesystem:0"),
            .getMCPPrompt(serverID: "mcp_server:filesystem", index: 0)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "extension-update:plugin:github"),
            .updateExtension(id: "plugin:github")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "extension-install:plugin:github"),
            .installExtension(id: "plugin:github")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "thread-selection-toggle:\(id.uuidString)"),
            .toggleThreadSelection(id: id)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "sidebar-filter:pinned"),
            .setSidebarFilter(.pinned)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "sidebar-saved-search:\(id.uuidString)"),
            .setSidebarSavedSearch(id)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "sidebar-saved-search-delete:\(id.uuidString)"),
            .deleteSidebarSavedSearch(id)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "sidebar-saved-search-move-up:\(id.uuidString)"),
            .moveSidebarSavedSearch(id, .up)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "sidebar-saved-search-move-down:\(id.uuidString)"),
            .moveSidebarSavedSearch(id, .down)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "browser-tab-new"),
            .newBrowserTab
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "browser-tab-select:\(id.uuidString)"),
            .selectBrowserTab(id: id)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "browser-tab-close:\(id.uuidString)"),
            .closeBrowserTab(id: id)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "activity-toggle-section:tools"),
            .toggleActivitySection(.tools)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "activity-instruction-dismiss:instruction-conflict"),
            .dismissInstructionDiagnostic(id: "instruction-conflict")
        )
    }

    func testAutomationScheduleCommandsParseTimeAndRecurrence() {
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-create-thread-follow-up-after:600"),
            .createThreadFollowUpAfter(600)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-create-workspace-schedule-after:3600"),
            .createWorkspaceScheduleAfter(3_600)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-create-thread-follow-up-every:hourly"),
            .createThreadFollowUpEvery(QuillAutomationRecurrence(interval: 1, unit: .hours))
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-create-workspace-schedule-every:daily"),
            .createWorkspaceScheduleEvery(QuillAutomationRecurrence(interval: 1, unit: .days))
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-create-workspace-schedule-every:weekly"),
            .createWorkspaceScheduleEvery(QuillAutomationRecurrence(interval: 1, unit: .weeks))
        )
    }

    func testStaticCommandsMapToActions() {
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "new-chat"),
            .action(.newChat)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "toggle-terminal"),
            .action(.toggleTerminal)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "automation-create-thread-follow-up"),
            .action(.createThreadFollowUp)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "project-refresh-context"),
            .action(.projectRefreshContext)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "thread-bulk-archive"),
            .action(.threadBulkArchive)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "fork-with-summary"),
            .action(.forkWithSummary)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "fork-full-context"),
            .action(.forkFullContext)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "compact-context"),
            .action(.compactContext)
        )
    }

    func testSlashCommandPaletteIDsMapToInsertText() throws {
        let modeCommand = try XCTUnwrap(
            SlashCommandCatalog.commandPaletteCommands().first { $0.title == "/mode auto|review|read-only" }
        )
        let modelCommand = try XCTUnwrap(
            SlashCommandCatalog.commandPaletteCommands().first { $0.title == "/model /synth" }
        )

        XCTAssertEqual(WorkspaceCommandPlan(commandID: modeCommand.id), .setDraft("/mode "))
        XCTAssertEqual(WorkspaceCommandPlan(commandID: modelCommand.id), .setDraft("/model "))
    }

    func testInvalidCommandsReturnNil() {
        XCTAssertNil(WorkspaceCommandPlan(commandID: "unknown-command"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "automation-pause:not-a-uuid"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "automation-create-thread-follow-up-after:soon"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "automation-create-workspace-schedule-every:yearly"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "mcp-resource:mcp_server:filesystem"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "mcp-resource:mcp_server:filesystem:not-a-number"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "mcp-prompt::0"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "browser-tab-select:not-a-uuid"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "browser-tab-close:not-a-uuid"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "sidebar-filter:not-real"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "sidebar-saved-search:not-a-uuid"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "sidebar-saved-search-delete:not-a-uuid"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "sidebar-saved-search-move-up:not-a-uuid"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "sidebar-saved-search-move-down:not-a-uuid"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "activity-toggle-section:not-real"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "slash-command:9999"))
    }
}
