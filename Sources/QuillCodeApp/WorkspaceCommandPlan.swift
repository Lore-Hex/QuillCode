import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceCommandPlan: Equatable {
    case localEnvironmentAction(String)
    case deleteMemory(id: String)
    case updateAutomationStatus(id: UUID, status: QuillAutomationStatus)
    case runAutomation(id: UUID)
    case deleteAutomation(id: UUID)
    case createThreadFollowUpAfter(TimeInterval)
    case createWorkspaceScheduleAfter(TimeInterval)
    case createThreadFollowUpEvery(QuillAutomationRecurrence)
    case createWorkspaceScheduleEvery(QuillAutomationRecurrence)
    case startMCPServer(id: String)
    case stopMCPServer(id: String)
    case updateExtension(id: String)
    case toggleThreadSelection(id: UUID)
    case toggleActivitySection(ActivitySectionKind)
    case setDraft(String)
    case runTool(name: String)
    case action(WorkspaceCommandAction)

    init?(commandID: String) {
        if let plan = Self.prefixPlan(commandID) {
            self = plan
            return
        }
        if let slashInsertText = SlashCommandCatalog.insertText(forCommandPaletteID: commandID) {
            self = .setDraft(slashInsertText)
            return
        }
        if let toolName = Self.toolNameByCommandID[commandID] {
            self = .runTool(name: toolName)
            return
        }
        if let draft = Self.draftByCommandID[commandID] {
            self = .setDraft(draft)
            return
        }
        if let action = WorkspaceCommandAction(rawValue: commandID) {
            self = .action(action)
            return
        }
        return nil
    }

    private static let toolNameByCommandID: [String: String] = [
        "git-status": ToolDefinition.gitStatus.name,
        "git-diff": ToolDefinition.gitDiff.name,
        "git-pr-view": ToolDefinition.gitPullRequestView.name,
        "git-pr-checks": ToolDefinition.gitPullRequestChecks.name,
        "git-pr-diff": ToolDefinition.gitPullRequestDiff.name,
        "git-worktree-list": ToolDefinition.gitWorktreeList.name
    ]

    private static let draftByCommandID: [String: String] = [
        "memory-add": "/remember ",
        "add-ssh-project": "/ssh user@host:/absolute/path",
        "git-pr-create": "Create a pull request titled ",
        "git-pr-checkout": "Checkout pull request ",
        "git-pr-reviewers": "Request reviewers for the current pull request: ",
        "git-pr-comment": "Comment on the current pull request: ",
        "git-pr-review": "Review the current pull request: approve",
        "git-pr-labels": "Label the current pull request: ",
        "git-pr-merge": "Merge the current pull request with squash",
        "git-worktree-create": "Create a git worktree named ",
        "git-worktree-remove": "Remove git worktree at "
    ]

    private static func prefixPlan(_ commandID: String) -> WorkspaceCommandPlan? {
        if commandID.value(after: "local-env:") != nil {
            return .localEnvironmentAction(commandID)
        }
        if let id = commandID.value(after: "memory-delete:") {
            return .deleteMemory(id: id)
        }
        if let id = commandID.uuidValue(after: "automation-pause:") {
            return .updateAutomationStatus(id: id, status: .paused)
        }
        if let id = commandID.uuidValue(after: "automation-resume:") {
            return .updateAutomationStatus(id: id, status: .active)
        }
        if let id = commandID.uuidValue(after: "automation-run:") {
            return .runAutomation(id: id)
        }
        if let id = commandID.uuidValue(after: "automation-delete:") {
            return .deleteAutomation(id: id)
        }
        if let rawSeconds = commandID.value(after: "automation-create-thread-follow-up-after:"),
           let seconds = TimeInterval(rawSeconds) {
            return .createThreadFollowUpAfter(seconds)
        }
        if let rawSeconds = commandID.value(after: "automation-create-workspace-schedule-after:"),
           let seconds = TimeInterval(rawSeconds) {
            return .createWorkspaceScheduleAfter(seconds)
        }
        if let rawRecurrence = commandID.value(after: "automation-create-thread-follow-up-every:"),
           let recurrence = commandRecurrence(rawRecurrence) {
            return .createThreadFollowUpEvery(recurrence)
        }
        if let rawRecurrence = commandID.value(after: "automation-create-workspace-schedule-every:"),
           let recurrence = commandRecurrence(rawRecurrence) {
            return .createWorkspaceScheduleEvery(recurrence)
        }
        if let id = commandID.value(after: "mcp-start:") {
            return .startMCPServer(id: id)
        }
        if let id = commandID.value(after: "mcp-stop:") {
            return .stopMCPServer(id: id)
        }
        if let id = commandID.value(after: "extension-update:") {
            return .updateExtension(id: id)
        }
        if let id = commandID.uuidValue(after: "thread-selection-toggle:") {
            return .toggleThreadSelection(id: id)
        }
        if let rawKind = commandID.value(after: "activity-toggle-section:"),
           let section = ActivitySectionKind(rawValue: rawKind) {
            return .toggleActivitySection(section)
        }
        return nil
    }

    private static func commandRecurrence(_ value: String) -> QuillAutomationRecurrence? {
        switch value {
        case "hourly":
            QuillAutomationRecurrence(interval: 1, unit: .hours)
        case "daily":
            QuillAutomationRecurrence(interval: 1, unit: .days)
        case "weekly":
            QuillAutomationRecurrence(interval: 1, unit: .weeks)
        default:
            nil
        }
    }
}

enum WorkspaceCommandAction: String, Equatable {
    case toggleTerminal = "toggle-terminal"
    case clearTerminal = "terminal-clear"
    case toggleBrowser = "toggle-browser"
    case browserBack = "browser-back"
    case browserForward = "browser-forward"
    case browserReload = "browser-reload"
    case toggleExtensions = "toggle-extensions"
    case toggleMemories = "toggle-memories"
    case toggleActivity = "toggle-activity"
    case toggleAutomations = "toggle-automations"
    case createThreadFollowUp = "automation-create-thread-follow-up"
    case createWorkspaceSchedule = "automation-create-workspace-schedule"
    case createThreadFollowUpTomorrow = "automation-create-thread-follow-up-tomorrow"
    case createWorkspaceScheduleTomorrow = "automation-create-workspace-schedule-tomorrow"
    case projectNewChat = "project-new-chat"
    case projectRefreshContext = "project-refresh-context"
    case projectRename = "project-rename"
    case projectRemove = "project-remove"
    case threadRename = "thread-rename"
    case threadDuplicate = "thread-duplicate"
    case threadArchive = "thread-archive"
    case threadUnarchive = "thread-unarchive"
    case threadDelete = "thread-delete"
    case threadSelectionStart = "thread-selection-start"
    case threadSelectionSelectAll = "thread-selection-select-all"
    case threadSelectionClear = "thread-selection-clear"
    case threadBulkPin = "thread-bulk-pin"
    case threadBulkUnpin = "thread-bulk-unpin"
    case threadBulkArchive = "thread-bulk-archive"
    case threadBulkUnarchive = "thread-bulk-unarchive"
    case threadBulkDelete = "thread-bulk-delete"
    case retryLastTurn = "retry-last-turn"
    case forkFromLast = "fork-from-last"
    case compactContext = "compact-context"
}

private extension String {
    func value(after prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }

    func uuidValue(after prefix: String) -> UUID? {
        value(after: prefix).flatMap(UUID.init(uuidString:))
    }
}
