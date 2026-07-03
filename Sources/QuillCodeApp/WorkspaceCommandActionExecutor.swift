import Foundation

extension QuillCodeWorkspaceModel {
    @discardableResult
    func runWorkspaceCommandAction(_ action: WorkspaceCommandAction, workspaceRoot: URL) -> Bool {
        guard let effect = WorkspaceCommandActionPlanner(
            selectedProjectID: root.selectedProjectID,
            selectedProject: selectedProject,
            selectedThreadID: root.selectedThreadID,
            selectedThread: selectedThread
        ).effect(for: action) else {
            return false
        }
        return runWorkspaceCommandActionEffect(effect, workspaceRoot: workspaceRoot)
    }

    @discardableResult
    func runWorkspaceCommandActionEffect(_ effect: WorkspaceCommandActionEffect, workspaceRoot: URL) -> Bool {
        switch effect {
        case .newChat:
            _ = newChat()
            return true
        case .workspaceBack:
            return navigateBackInWorkspace()
        case .workspaceForward:
            return navigateForwardInWorkspace()
        case .cycleMode:
            return cycleMode()
        case .focusComposer:
            return focusComposer()
        case .toggleSidebar:
            toggleSidebar()
            return true
        case .toggleTerminal:
            toggleTerminal()
            return true
        case .clearTerminal:
            return clearTerminalHistory()
        case .toggleBrowser:
            toggleBrowser()
            return true
        case .browserBack:
            return goBackInBrowser()
        case .browserForward:
            return goForwardInBrowser()
        case .browserReload:
            return reloadBrowserPreview()
        case .toggleExtensions:
            toggleExtensions()
            return true
        case .toggleMemories:
            toggleMemories()
            return true
        case .toggleActivity:
            toggleActivity()
            return true
        case .toggleAutomations:
            toggleAutomations()
            return true
        case .openPullRequestReviewDraft:
            presentPullRequestReviewDraft()
            return true
        case .createThreadFollowUp:
            return createThreadFollowUpAutomation() != nil
        case .createWorkspaceSchedule:
            return createWorkspaceScheduleAutomation() != nil
        case .createThreadFollowUpTomorrow:
            return createTomorrowMorningThreadFollowUpAutomation() != nil
        case .createWorkspaceScheduleTomorrow:
            return createTomorrowMorningWorkspaceScheduleAutomation() != nil
        case .newProjectThread(let projectID):
            _ = newChat(projectID: projectID)
            return true
        case .refreshProjectContext(let projectID):
            return refreshProjectContext(projectID)
        case .initProject(let projectID):
            return runInitProject(projectID)
        case .setDraft(let draft):
            setDraft(draft)
            return true
        case .removeProject(let projectID):
            return removeProject(projectID)
        case .duplicateThread(let threadID):
            return duplicateThread(threadID) != nil
        case .clearThread(let threadID):
            return clearThread(threadID)
        case .revertLatestTurn:
            return runLatestTurnRevert(workspaceRoot: workspaceRoot)
        case .archiveThread(let threadID):
            archiveThread(threadID)
            return true
        case .unarchiveThread(let threadID):
            return unarchiveThread(threadID)
        case .deleteThread(let threadID):
            return deleteThread(threadID)
        case .sidebarBulkAction(let kind):
            return performSidebarBulkAction(kind)
        case .retryLastTurn:
            return prepareRetryLastUserTurn()
        case .forkThread(let strategy):
            return startForkThread(strategy: strategy)
        case .compactContext:
            return startCompactContext()
        case .disconnectAll:
            return disconnectAll()
        case .attentionNext:
            attentionMoveDown()
            return true
        case .attentionPrevious:
            attentionMoveUp()
            return true
        case .attentionOpen:
            attentionOpenSelected()
            return true
        case .attentionAcknowledge:
            attentionAcknowledgeSelected()
            return true
        case .attentionDismiss:
            attentionDismissSelected()
            return true
        }
    }
}
