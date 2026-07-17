import Foundation
import QuillCodeCore
import QuillCodeTools

enum WorkspaceCommandPlan: Equatable {
    case localEnvironmentAction(String)
    case editMemory(id: String)
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
    case readMCPResource(serverID: String, index: Int)
    case getMCPPrompt(serverID: String, index: Int)
    case installExtension(id: String)
    case updateExtension(id: String)
    case setHookTrust(id: String, decision: ProjectHookTrustDecision)
    case toggleThreadSelection(id: UUID)
    case setSidebarFilter(SidebarSavedFilterKind)
    case setSidebarSavedSearch(UUID)
    case deleteSidebarSavedSearch(UUID)
    case moveSidebarSavedSearch(UUID, SidebarSavedSearchMoveDirection)
    case newBrowserTab
    case selectBrowserTab(id: UUID)
    case closeBrowserTab(id: UUID)
    case toggleActivitySection(ActivitySectionKind)
    case openActivitySource(path: String, lineNumber: Int?)
    case editActivitySource(path: String, lineNumber: Int?)
    case applyInstructionDiagnostic(id: String, selectedReferenceIndex: Int)
    case resolveInstructionDiagnostic(id: String)
    case dismissInstructionDiagnostic(id: String)
    case resolveSubagentApproval(WorkspaceSubagentApprovalCommand)
    case retryAutoReviewDenial(requestID: String)
    case setDraft(String)
    case runTool(name: String)
    case runToolCall(ToolCall)
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
        if let call = Self.toolCallByCommandID[commandID] {
            self = .runToolCall(call)
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
        "git-fetch": ToolDefinition.gitFetch.name,
        "git-pull": ToolDefinition.gitPull.name,
        "git-branch-list": ToolDefinition.gitBranchList.name,
        "git-worktree-list": ToolDefinition.gitWorktreeList.name
    ].merging(WorkspacePullRequestCommandCatalog.toolNameByCommandID) { local, _ in local }

    private static let toolCallByCommandID: [String: ToolCall] = [
        "git-worktree-prune": WorkspaceWorktreeToolCallPlanner.prune(.init(dryRun: true, verbose: true)),
        "git-pr-fill": ToolCall(
            name: ToolDefinition.gitPullRequestCreate.name,
            argumentsJSON: ToolArguments.json(["fill": true])
        )
    ]

    private static let draftByCommandID: [String: String] = [
        "memory-add": "/remember ",
        "add-ssh-project": "/ssh user@host:/absolute/path",
        "git-worktree-create": "Create a git worktree named ",
        "git-branch-switch": "/branch switch ",
        "git-worktree-open": "Open git worktree at ",
        "git-worktree-remove": "Remove git worktree at ",
        "automation-create-monitor": "/monitor ",
        "workflow-recording-create": "Create a reusable skill by recording this workflow: "
    ].merging(WorkspacePullRequestCommandCatalog.draftByCommandID) { local, _ in local }

    private static func prefixPlan(_ commandID: String) -> WorkspaceCommandPlan? {
        if let requestID = commandID.value(after: Self.autoReviewDenialRetryPrefix) {
            return .retryAutoReviewDenial(requestID: requestID)
        }
        if let command = WorkspaceSubagentApprovalCommand(commandID: commandID) {
            return .resolveSubagentApproval(command)
        }
        if commandID.value(after: "local-env:") != nil {
            return .localEnvironmentAction(commandID)
        }
        if let id = commandID.value(after: "memory-edit:") {
            return .editMemory(id: id)
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
        if let reference = commandID.mcpReference(after: "mcp-resource:") {
            return .readMCPResource(serverID: reference.serverID, index: reference.index)
        }
        if let reference = commandID.mcpReference(after: "mcp-prompt:") {
            return .getMCPPrompt(serverID: reference.serverID, index: reference.index)
        }
        if let id = commandID.value(after: "extension-install:") {
            return .installExtension(id: id)
        }
        if let id = commandID.value(after: "extension-update:") {
            return .updateExtension(id: id)
        }
        if let id = commandID.value(after: "hook-trust:") {
            return .setHookTrust(id: id, decision: .trusted)
        }
        if let id = commandID.value(after: "hook-disable:") {
            return .setHookTrust(id: id, decision: .disabled)
        }
        if let id = commandID.uuidValue(after: "thread-selection-toggle:") {
            return .toggleThreadSelection(id: id)
        }
        if let rawFilter = commandID.value(after: "sidebar-filter:"),
           let filter = SidebarSavedFilterKind(rawValue: rawFilter) {
            return .setSidebarFilter(filter)
        }
        if let id = commandID.uuidValue(after: "sidebar-saved-search:") {
            return .setSidebarSavedSearch(id)
        }
        if let id = commandID.uuidValue(after: "sidebar-saved-search-delete:") {
            return .deleteSidebarSavedSearch(id)
        }
        if let id = commandID.uuidValue(after: "sidebar-saved-search-move-up:") {
            return .moveSidebarSavedSearch(id, .up)
        }
        if let id = commandID.uuidValue(after: "sidebar-saved-search-move-down:") {
            return .moveSidebarSavedSearch(id, .down)
        }
        if commandID == "browser-tab-new" {
            return .newBrowserTab
        }
        if let id = commandID.uuidValue(after: "browser-tab-select:") {
            return .selectBrowserTab(id: id)
        }
        if let id = commandID.uuidValue(after: "browser-tab-close:") {
            return .closeBrowserTab(id: id)
        }
        if let rawKind = commandID.value(after: "activity-toggle-section:"),
           let section = ActivitySectionKind(rawValue: rawKind) {
            return .toggleActivitySection(section)
        }
        if let command = WorkspaceActivitySourceCommand(commandID: commandID) {
            switch command.action {
            case .open:
                return .openActivitySource(path: command.path, lineNumber: command.lineNumber)
            case .edit:
                return .editActivitySource(path: command.path, lineNumber: command.lineNumber)
            }
        }
        if let command = WorkspaceInstructionDiagnosticCommand(commandID: commandID) {
            switch command.action {
            case .apply(let selectedReferenceIndex):
                return .applyInstructionDiagnostic(
                    id: command.diagnosticID,
                    selectedReferenceIndex: selectedReferenceIndex
                )
            case .resolve:
                return .resolveInstructionDiagnostic(id: command.diagnosticID)
            case .dismiss:
                return .dismissInstructionDiagnostic(id: command.diagnosticID)
            }
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

    static let autoReviewDenialRetryPrefix = "auto-review-denial-retry:"

    static func autoReviewDenialRetryCommandID(_ requestID: String) -> String {
        autoReviewDenialRetryPrefix + requestID
    }
}

enum WorkspaceCommandAction: String, Equatable {
    case codeReview = "code-review"
    case autoReviewDenials = "auto-review-denials"
    case dismissAutoReviewDenials = "auto-review-denials-dismiss"
    case newChat = "new-chat"
    case quickChat = "quick-chat"
    case workspaceBack = "workspace-back"
    case workspaceForward = "workspace-forward"
    case previousTask = "previous-task"
    case nextTask = "next-task"
    case cycleMode = "cycle-mode"
    case focusComposer = "focus-composer"
    case toggleSidebar = "toggle-sidebar"
    case toggleTerminal = "toggle-terminal"
    case toggleBottomPanel = "toggle-bottom-panel"
    case toggleReviewPanel = "toggle-review-panel"
    case increaseFontSize = "increase-font-size"
    case decreaseFontSize = "decrease-font-size"
    case clearTerminal = "terminal-clear"
    case toggleBrowser = "toggle-browser"
    case browserBack = "browser-back"
    case browserForward = "browser-forward"
    case browserReload = "browser-reload"
    case toggleExtensions = "toggle-extensions"
    case showSkills = "show-skills"
    case showHooks = "show-hooks"
    case workflowRecordingStop = "workflow-recording-stop"
    case toggleMemories = "toggle-memories"
    case toggleActivity = "toggle-activity"
    case toggleAutomations = "toggle-automations"
    case pullRequestReviewDraft = "git-pr-review"
    case createThreadFollowUp = "automation-create-thread-follow-up"
    case createWorkspaceSchedule = "automation-create-workspace-schedule"
    case createThreadFollowUpTomorrow = "automation-create-thread-follow-up-tomorrow"
    case createWorkspaceScheduleTomorrow = "automation-create-workspace-schedule-tomorrow"
    case projectNewChat = "project-new-chat"
    case projectRefreshContext = "project-refresh-context"
    case projectInit = "project-init"
    case projectMoveToTop = "project-move-to-top"
    case projectMoveUp = "project-move-up"
    case projectMoveDown = "project-move-down"
    case projectMoveToBottom = "project-move-to-bottom"
    case projectRename = "project-rename"
    case projectRemove = "project-remove"
    case threadRename = "thread-rename"
    case threadDuplicate = "thread-duplicate"
    case threadNewWorktree = "thread-new-worktree"
    case threadRestoreWorktree = "thread-restore-worktree"
    case threadHandoff = "thread-handoff"
    case threadFinishWorktree = "thread-finish-worktree"
    case threadCreateBranch = "thread-create-branch"
    case threadPublishBranch = "thread-publish-branch"
    case threadRefreshPullRequest = "thread-refresh-pull-request"
    case threadLandPullRequest = "thread-land-pull-request"
    case threadCleanupMergedWorktree = "thread-cleanup-merged-worktree"
    case threadPin = "thread-pin"
    case threadUnpin = "thread-unpin"
    case threadClear = "thread-clear"
    case threadRevertLatest = "thread-revert-latest"
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
    case sidebarSavedSearchCreate = "sidebar-saved-search-create"
    case retryLastTurn = "retry-last-turn"
    case forkFromLast = "fork-from-last"
    case forkWithSummary = "fork-with-summary"
    case forkFullContext = "fork-full-context"
    case compactContext = "compact-context"
    case disconnectAll = "disconnect-all"
    case sideConversationReturn = "side-conversation-return"
    // Morning-triage inbox keyboard triage (issue #877): j / k / Enter / a / d.
    case attentionNext = "attention-next"
    case attentionPrevious = "attention-previous"
    case attentionOpen = "attention-open"
    case attentionAcknowledge = "attention-acknowledge"
    case attentionDismiss = "attention-dismiss"
    // Appended at the end (never mid-enum — discriminant shifts corrupt incremental builds).
    case newIncognitoChat = "new-incognito-chat"
}

private extension String {
    func value(after prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }

    func uuidValue(after prefix: String) -> UUID? {
        value(after: prefix).flatMap(UUID.init(uuidString:))
    }

    func mcpReference(after prefix: String) -> (serverID: String, index: Int)? {
        guard let payload = value(after: prefix),
              let separator = payload.lastIndex(of: ":")
        else { return nil }

        let serverID = String(payload[..<separator])
        let rawIndex = String(payload[payload.index(after: separator)...])
        guard !serverID.isEmpty, let index = Int(rawIndex), index >= 0 else { return nil }
        return (serverID, index)
    }
}
