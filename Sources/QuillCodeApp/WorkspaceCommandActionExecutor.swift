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
        case .presentCodeReview:
            presentCodeReview()
            return codeReviewRequest != nil
        case .presentAutoReviewDenials:
            isAutoReviewDenialsPresented = true
            return true
        case .dismissAutoReviewDenials:
            isAutoReviewDenialsPresented = false
            return true
        case .newChat:
            _ = newChat()
            return true
        case .newIncognitoChat:
            _ = newIncognitoChat()
            return true
        case .quickChat:
            _ = startQuickChat()
            return true
        case .workspaceBack:
            return navigateBackInWorkspace()
        case .workspaceForward:
            return navigateForwardInWorkspace()
        case .selectAdjacentTask(let offset):
            return selectAdjacentSidebarThread(offset: offset)
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
        case .toggleReviewPanel:
            return toggleReviewPanel(workspaceRoot: workspaceRoot)
        case .increaseTextScale:
            return increaseTextScale()
        case .decreaseTextScale:
            return decreaseTextScale()
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
        case .showSkills:
            showExtensions(focusedOn: .skill)
            return true
        case .showHooks:
            showExtensions(focusedOn: .hook)
            return true
        case .stopWorkflowRecording:
            Task { await prepareStoppedWorkflowRecordingForComposer() }
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
        case .moveProjectToTop(let projectID):
            return moveProjectToTop(projectID)
        case .moveProjectToBottom(let projectID):
            return moveProjectToBottom(projectID)
        case .moveProject(let projectID, let direction):
            return moveProject(projectID, direction: direction)
        case .setDraft(let draft):
            setDraft(draft)
            return true
        case .removeProject(let projectID):
            return removeProject(projectID)
        case .duplicateThread(let threadID):
            return duplicateThread(threadID) != nil
        case .newWorktreeThread:
            return newWorktreeThread() != nil
        case .restoreManagedWorktree(let threadID):
            return restoreManagedWorktree(threadID: threadID)
        case .handoffSelectedThread:
            return handoffSelectedThread()
        case .finishSelectedWorktree:
            return finishSelectedWorktreeInLocal()
        case .publishSelectedWorktreeBranch:
            return publishSelectedWorktreeBranch()
        case .refreshSelectedPullRequest:
            return refreshSelectedPullRequest()
        case .landSelectedPullRequest:
            return landSelectedPullRequest()
        case .cleanUpSelectedMergedWorktree:
            return cleanUpSelectedMergedWorktree()
        case .setThreadPinned(let threadID, let isPinned):
            return setPinThread(threadID, isPinned: isPinned)
        case .clearThread(let threadID):
            return clearThread(threadID)
        case .revertLatestTurn:
            return runLatestTurnRevert(workspaceRoot: workspaceRoot)
        case .archiveThread(let threadID):
            return archiveThread(threadID)
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
            return startCompactContext(workspaceRoot: workspaceRoot)
        case .disconnectAll:
            return disconnectAll()
        case .sideConversationReturn:
            return returnFromSideConversation()
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
