import Foundation

extension QuillCodeWorkspaceModel {
    func runSlashCommandDispatchAction(_ action: WorkspaceSlashCommandDispatchAction, workspaceRoot: URL) {
        switch action {
        case .appendTranscript(let transcript):
            appendLocalCommandTranscript(transcript)
        case .newChat:
            _ = newChat()
        case .setMode(let mode, let userText):
            setMode(mode)
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.mode(
                userText: userText,
                mode: mode
            ))
        case .setModel(let model, let userText):
            let modelID = setModel(model)
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.model(
                userText: userText,
                model: modelID
            ))
        case .renameThread(let title, let userText):
            let succeeded = root.selectedThreadID.map { renameThread($0, to: title) } ?? false
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.renameThread(
                userText: userText,
                requestedTitle: title,
                succeeded: succeeded
            ))
        case .renameProject(let name, let userText):
            let succeeded = root.selectedProjectID.map { renameProject($0, to: name) } ?? false
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.renameProject(
                userText: userText,
                requestedName: name,
                succeeded: succeeded
            ))
        case .addSSHProject(let address, let userText):
            appendSSHProjectTranscript(address: address, userText: userText)
        case .remember(let content, let userText):
            runRememberSlashCommand(content, originalPrompt: userText)
        case .editMemory(let id, let content, let userText):
            runEditMemorySlashCommand(id: id, content: content, originalPrompt: userText)
        case .threadFollowUp(let scheduleText, let userText):
            runThreadFollowUpSlashCommand(scheduleText, originalPrompt: userText)
        case .workspaceSchedule(let scheduleText, let userText):
            runWorkspaceScheduleSlashCommand(scheduleText, originalPrompt: userText)
        case .workspaceCommand(let commandID, let userText):
            if !runWorkspaceCommand(commandID, workspaceRoot: workspaceRoot) {
                appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed(
                    userText: userText
                ))
            }
        case .worktreeCreate(let request, _):
            createWorktree(request, workspaceRoot: workspaceRoot)
        case .worktreeOpen(let request, _):
            openWorktree(request, workspaceRoot: workspaceRoot)
        case .worktreeRemove(let request, _):
            removeWorktree(request, workspaceRoot: workspaceRoot)
        case .worktreePrune(let request, _):
            pruneWorktrees(request, workspaceRoot: workspaceRoot)
        case .toolCall(let call):
            _ = runToolCall(call, workspaceRoot: workspaceRoot)
        case .environmentAction(let query, let userText):
            runEnvironmentSlashCommand(query, originalPrompt: userText, workspaceRoot: workspaceRoot)
        }
    }

    private func appendSSHProjectTranscript(address: String, userText: String) {
        if let projectID = addSSHProject(address),
           let project = root.projects.first(where: { $0.id == projectID }) {
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.sshProjectAdded(
                userText: userText,
                projectName: project.name,
                displayPath: project.displayPath
            ))
        } else {
            appendLocalCommandTranscript(WorkspaceSlashCommandTranscriptPlanner.sshProjectFailed(
                userText: userText,
                message: lastError
            ))
        }
    }
}
