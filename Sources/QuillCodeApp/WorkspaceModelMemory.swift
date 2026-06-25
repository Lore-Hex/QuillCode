import Foundation
import QuillCodeCore

extension QuillCodeWorkspaceModel {
    @discardableResult
    func deleteGlobalMemory(id: String) -> Bool {
        guard let mutation = WorkspaceMemoryEngine.deleteGlobal(id: id, directory: globalMemoryDirectory) else {
            return false
        }
        applyGlobalMemoryMutation(mutation)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    func runRememberSlashCommand(_ content: String, originalPrompt: String) {
        let mutation = WorkspaceMemoryEngine.saveGlobal(
            content: content,
            userText: originalPrompt,
            directory: globalMemoryDirectory
        )
        applyGlobalMemoryMutation(mutation)
    }

    @discardableResult
    func prepareEditGlobalMemory(id: String) -> Bool {
        guard let note = root.globalMemories.first(where: { $0.id == id && $0.scope == .global }) else {
            let mutation = WorkspaceMemoryEngine.updateGlobal(
                id: id,
                content: "",
                userText: "Edit memory",
                directory: globalMemoryDirectory
            )
            applyGlobalMemoryMutation(mutation)
            return true
        }
        setDraft("/remember-edit \(note.id)\n\(note.content)")
        return true
    }

    func runEditMemorySlashCommand(id: String, content: String, originalPrompt: String) {
        let mutation = WorkspaceMemoryEngine.updateGlobal(
            id: id,
            content: content,
            userText: originalPrompt,
            directory: globalMemoryDirectory
        )
        applyGlobalMemoryMutation(mutation)
    }

    func refreshGlobalMemories() {
        root.globalMemories = WorkspaceProjectContextRefresher.globalMemories(directory: globalMemoryDirectory)
    }

    func applyGlobalMemoryMutation(_ mutation: WorkspaceMemoryMutation) {
        appendLocalCommandTranscript(mutation.transcript)
        if let updatedGlobalMemories = mutation.updatedGlobalMemories {
            root.globalMemories = updatedGlobalMemories
        }
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
