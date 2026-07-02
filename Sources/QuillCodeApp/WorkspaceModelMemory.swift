import Foundation
import QuillCodeCore

extension QuillCodeWorkspaceModel {
    @discardableResult
    func deleteGlobalMemory(id: String) -> Bool {
        guard WorkspaceMemoryWorkflow.scope(for: id) == .global else { return false }
        return deleteMemory(id: id)
    }

    @discardableResult
    func deleteMemory(id: String) -> Bool {
        guard let mutation = WorkspaceMemoryWorkflow.delete(
            id: id,
            context: memoryWorkflowContext()
        ) else {
            return false
        }
        applyMemoryMutation(mutation, for: id)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    func runRememberSlashCommand(_ content: String, originalPrompt: String) {
        let mutation = WorkspaceMemoryEngine.saveGlobal(
            content: content,
            userText: originalPrompt,
            directory: globalMemoryDirectory
        )
        applyMemoryMutation(mutation)
    }

    @discardableResult
    func prepareEditMemory(id: String) -> Bool {
        if let note = WorkspaceMemoryWorkflow.editableNote(
            id: id,
            globalMemories: root.globalMemories,
            project: editableProjectMemory()
        ) {
            setDraft("/remember-edit \(note.id)\n\(note.content)")
            return true
        }

        let mutation = WorkspaceMemoryWorkflow.update(
            id: id,
            content: "",
            userText: "Edit memory",
            context: memoryWorkflowContext()
        )
        applyMemoryMutation(mutation, for: id)
        return true
    }

    func runEditMemorySlashCommand(id: String, content: String, originalPrompt: String) {
        let mutation = WorkspaceMemoryWorkflow.update(
            id: id,
            content: content,
            userText: originalPrompt,
            context: memoryWorkflowContext()
        )
        applyMemoryMutation(mutation, for: id)
    }

    func refreshGlobalMemories() {
        root.globalMemories = WorkspaceProjectContextRefresher.globalMemories(directory: globalMemoryDirectory)
    }

    func applyMemoryMutation(_ mutation: WorkspaceMemoryMutation) {
        appendLocalCommandTranscript(mutation.transcript)
        if let updatedGlobalMemories = mutation.updatedGlobalMemories {
            root.globalMemories = updatedGlobalMemories
        }
        appendMemoryReviewEvent(mutation)
        applyMemoryContextNotice(mutation)
    }

    func applyProjectMemoryMutation(_ mutation: WorkspaceMemoryMutation) {
        appendLocalCommandTranscript(mutation.transcript)
        if let projectID = editableProjectMemoryID(),
           let updatedProjectMemories = mutation.updatedProjectMemories,
           let index = root.projects.firstIndex(where: { $0.id == projectID }) {
            root.projects[index].memories = updatedProjectMemories
        }
        appendMemoryReviewEvent(mutation)
        applyMemoryContextNotice(mutation)
    }

    private func appendMemoryReviewEvent(_ mutation: WorkspaceMemoryMutation) {
        guard let event = mutation.reviewEvent else { return }
        mutateSelectedThread { thread in
            thread.events.append(event)
        }
    }

    private func applyMemoryContextNotice(_ mutation: WorkspaceMemoryMutation) {
        guard let summary = mutation.noticeSummary,
              let relativePath = mutation.noticeRelativePath
        else {
            return
        }
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        let refreshedContext = workspaceThreadContext(projectID)
        let update = WorkspaceMemoryEngine.contextUpdate(
            memories: refreshedContext.memories,
            summary: summary,
            relativePath: relativePath
        )
        mutateSelectedThread { thread in
            thread.memories = update.memories
            thread.events.append(update.event)
        }
    }

    private func applyMemoryMutation(_ mutation: WorkspaceMemoryMutation, for id: String) {
        switch WorkspaceMemoryWorkflow.scope(for: id) {
        case .global:
            applyMemoryMutation(mutation)
        case .project:
            applyProjectMemoryMutation(mutation)
        }
    }

    private func editableProjectMemory() -> ProjectRef? {
        guard let projectID = editableProjectMemoryID() else { return nil }
        return root.projects.first { $0.id == projectID }
    }

    private func editableProjectMemoryID() -> UUID? {
        selectedThread?.projectID ?? root.selectedProjectID
    }

    private func editableProjectMemoryRoot() -> URL? {
        guard let project = editableProjectMemory(), !project.isRemote else { return nil }
        return URL(fileURLWithPath: project.path)
    }

    private func memoryWorkflowContext() -> WorkspaceMemoryWorkflowContext {
        WorkspaceMemoryWorkflowContext(
            globalMemoryDirectory: globalMemoryDirectory,
            editableProject: editableProjectMemory(),
            editableProjectRoot: editableProjectMemoryRoot(),
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    func refreshThreadMemoryContext(_ thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        WorkspaceProjectContextRefresher.syncThreadMemories(
            &thread,
            fallbackProjectID: root.selectedProjectID,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }
}
