import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func addProject(path: URL, name: String? = nil) -> UUID {
        let standardized = path.standardizedFileURL
        let result = WorkspaceProjectEngine.upsertLocalProject(
            path: standardized,
            name: name,
            metadata: WorkspaceProjectMetadataLoader.loadLocal(from: standardized),
            projects: &root.projects
        )
        root.selectedProjectID = result.projectID
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return result.projectID
    }

    @discardableResult
    public func addSSHProject(_ address: String, name: String? = nil) -> UUID? {
        switch WorkspaceProjectEngine.upsertSSHProject(address: address, name: name, projects: &root.projects) {
        case .failure(let error):
            setLastError(error.message)
            return nil
        case .success(let result):
            root.selectedProjectID = result.projectID
            syncTerminalSessionToSelectedProject()
            saveProjects()
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return result.projectID
        }
    }

    public func selectProject(_ id: UUID?) {
        guard let selection = WorkspaceProjectEngine.selectionAfterSelectingProject(
            id,
            projects: root.projects,
            threads: root.threads
        ) else { return }
        root.selectedProjectID = selection.projectID
        syncTerminalSessionToSelectedProject()
        refreshProjectMetadata(selection.projectID)
        touchProject(selection.projectID)
        root.selectedThreadID = selection.threadID
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    @discardableResult
    public func renameProject(_ id: UUID, to name: String) -> Bool {
        guard WorkspaceProjectEngine.renameProject(id, to: name, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func refreshProjectContext(_ id: UUID) -> Bool {
        guard let project = root.projects.first(where: { $0.id == id }) else {
            return false
        }
        if project.isRemote {
            guard refreshRemoteProjectContext(id) else {
                return false
            }
        } else {
            refreshProjectMetadata(id)
        }
        if selectedThread?.projectID == id || root.selectedProjectID == id {
            let refreshedContext = workspaceThreadContext(id)
            mutateSelectedThread { thread in
                guard thread.projectID == id else { return }
                thread.instructions = refreshedContext.instructions
                thread.memories = refreshedContext.memories
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: "Refreshed project context",
                    payloadJSON: id.uuidString
                ))
            }
        }
        touchProject(id)
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func removeProject(_ id: UUID) -> Bool {
        var projects = root.projects
        var threads = root.threads
        guard let result = WorkspaceProjectEngine.removeProject(
            id,
            projects: &projects,
            threads: &threads,
            selectedProjectID: root.selectedProjectID
        ) else {
            return false
        }
        root.projects = projects
        root.threads = threads
        for threadID in result.changedThreadIDs {
            guard let thread = root.threads.first(where: { $0.id == threadID }) else { continue }
            threadPersistence.save(thread)
        }
        root.selectedProjectID = result.selectedProjectID
        syncTerminalSessionToSelectedProject()
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }
}
