import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceCommandPlanTests: XCTestCase {
    func testToolCommandsUseCanonicalToolNames() {
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
            WorkspaceCommandPlan(commandID: "git-worktree-list"),
            .runTool(name: ToolDefinition.gitWorktreeList.name)
        )
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
            WorkspaceCommandPlan(commandID: "git-pr-review"),
            .setDraft("Review the current pull request: approve")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "git-worktree-remove"),
            .setDraft("Remove git worktree at ")
        )
    }

    func testPrefixCommandsParseStructuredValues() {
        let id = UUID()
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "local-env:bootstrap"),
            .localEnvironmentAction("local-env:bootstrap")
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
            WorkspaceCommandPlan(commandID: "extension-update:plugin:github"),
            .updateExtension(id: "plugin:github")
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "thread-selection-toggle:\(id.uuidString)"),
            .toggleThreadSelection(id: id)
        )
        XCTAssertEqual(
            WorkspaceCommandPlan(commandID: "activity-toggle-section:tools"),
            .toggleActivitySection(.tools)
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
        XCTAssertNil(WorkspaceCommandPlan(commandID: "activity-toggle-section:not-real"))
        XCTAssertNil(WorkspaceCommandPlan(commandID: "slash-command:9999"))
    }
}
