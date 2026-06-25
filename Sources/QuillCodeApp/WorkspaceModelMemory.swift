import Foundation
import QuillCodeCore

extension QuillCodeWorkspaceModel {
    @discardableResult
    func deleteGlobalMemory(id: String) -> Bool {
        guard let mutation = WorkspaceMemoryEngine.deleteGlobal(id: id, directory: globalMemoryDirectory) else {
            return false
        }
        applyMemoryMutation(mutation)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    func deleteMemory(id: String) -> Bool {
        if id.hasPrefix("project:") {
            let project = editableProjectMemory()
            let mutation = if project?.isRemote == true {
                WorkspaceMemoryEngine.deleteRemoteProject(
                    id: id,
                    project: project,
                    executor: sshRemoteShellExecutor
                )
            } else {
                WorkspaceMemoryEngine.deleteProject(
                    id: id,
                    projectRoot: editableProjectMemoryRoot()
                )
            }
            applyProjectMemoryMutation(mutation)
        } else {
            guard let mutation = WorkspaceMemoryEngine.deleteGlobal(id: id, directory: globalMemoryDirectory) else {
                return false
            }
            applyMemoryMutation(mutation)
        }
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
        if let note = editableMemoryNote(id: id) {
            setDraft("/remember-edit \(note.id)\n\(note.content)")
            return true
        }

        if id.hasPrefix("project:") {
            let mutation = WorkspaceMemoryEngine.updateProject(
                id: id,
                content: "",
                userText: "Edit memory",
                projectRoot: editableProjectMemoryRoot()
            )
            applyProjectMemoryMutation(mutation)
        } else {
            let mutation = WorkspaceMemoryEngine.updateGlobal(
                id: id,
                content: "",
                userText: "Edit memory",
                directory: globalMemoryDirectory
            )
            applyMemoryMutation(mutation)
        }
        return true
    }

    func runEditMemorySlashCommand(id: String, content: String, originalPrompt: String) {
        if id.hasPrefix("project:") {
            let project = editableProjectMemory()
            let mutation = if project?.isRemote == true {
                WorkspaceMemoryEngine.updateRemoteProject(
                    id: id,
                    content: content,
                    userText: originalPrompt,
                    project: project,
                    executor: sshRemoteShellExecutor
                )
            } else {
                WorkspaceMemoryEngine.updateProject(
                    id: id,
                    content: content,
                    userText: originalPrompt,
                    projectRoot: editableProjectMemoryRoot()
                )
            }
            applyProjectMemoryMutation(mutation)
        } else {
            let mutation = WorkspaceMemoryEngine.updateGlobal(
                id: id,
                content: content,
                userText: originalPrompt,
                directory: globalMemoryDirectory
            )
            applyMemoryMutation(mutation)
        }
    }

    func refreshGlobalMemories() {
        root.globalMemories = WorkspaceProjectContextRefresher.globalMemories(directory: globalMemoryDirectory)
    }

    func applyMemoryMutation(_ mutation: WorkspaceMemoryMutation) {
        appendLocalCommandTranscript(mutation.transcript)
        if let updatedGlobalMemories = mutation.updatedGlobalMemories {
            root.globalMemories = updatedGlobalMemories
        }
        applyMemoryContextNotice(mutation)
    }

    func applyProjectMemoryMutation(_ mutation: WorkspaceMemoryMutation) {
        appendLocalCommandTranscript(mutation.transcript)
        if let projectID = editableProjectMemoryID(),
           let updatedProjectMemories = mutation.updatedProjectMemories,
           let index = root.projects.firstIndex(where: { $0.id == projectID }) {
            root.projects[index].memories = updatedProjectMemories
        }
        applyMemoryContextNotice(mutation)
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

    private func editableMemoryNote(id: String) -> MemoryNote? {
        if id.hasPrefix("project:") {
            return editableProjectMemory()?.memories.first { $0.id == id && $0.scope == .project }
        }
        return root.globalMemories.first { $0.id == id && $0.scope == .global }
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
