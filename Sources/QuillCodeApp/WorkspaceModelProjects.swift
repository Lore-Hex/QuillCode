import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func addProject(path: URL, name: String? = nil) -> UUID {
        let previousLocation = currentNavigationLocation
        let standardized = path.standardizedFileURL
        let result = WorkspaceProjectEngine.upsertLocalProject(
            path: standardized,
            name: name,
            metadata: WorkspaceProjectMetadataLoader.loadLocal(from: standardized),
            projects: &root.projects
        )
        root.selectedProjectID = result.projectID
        syncTerminalSessionToSelectedProject()
        refreshFileMentionIndex()
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        recordNavigationTransition(from: previousLocation)
        return result.projectID
    }

    @discardableResult
    public func addSSHProject(_ address: String, name: String? = nil) -> UUID? {
        let previousLocation = currentNavigationLocation
        switch WorkspaceProjectEngine.upsertSSHProject(address: address, name: name, projects: &root.projects) {
        case .failure(let error):
            setLastError(error.message)
            return nil
        case .success(let result):
            root.selectedProjectID = result.projectID
            syncTerminalSessionToSelectedProject()
            refreshFileMentionIndex()
            saveProjects()
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            recordNavigationTransition(from: previousLocation)
            return result.projectID
        }
    }

    public func selectProject(_ id: UUID?, recordsNavigation: Bool = true) {
        _ = returnFromSideConversation()
        guard let selection = WorkspaceProjectEngine.selectionAfterSelectingProject(
            id,
            projects: root.projects,
            threads: root.threads
        ) else { return }
        let previousLocation = currentNavigationLocation
        root.selectedProjectID = selection.projectID
        syncTerminalSessionToSelectedProject()
        refreshProjectMetadata(selection.projectID)
        touchProject(selection.projectID)
        root.selectedThreadID = selection.threadID
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        if recordsNavigation {
            recordNavigationTransition(from: previousLocation)
        }
    }

    public func refreshSelectedProjectInstructions() {
        refreshSelectedProjectContext()
    }

    public func refreshSelectedProjectContext() {
        let projectID = selectedThread?.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        let refreshedContext = workspaceThreadContext(projectID)
        mutateSelectedThread { thread in
            thread.instructions = refreshedContext.instructions
            thread.memories = refreshedContext.memories
        }
        saveProjects()
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
    public func moveProjectToTop(_ id: UUID) -> Bool {
        guard WorkspaceProjectEngine.touchProject(id, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func moveProjectToBottom(_ id: UUID) -> Bool {
        guard WorkspaceProjectEngine.moveProjectToBottom(id, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func moveProject(_ id: UUID, direction: WorkspaceProjectMoveDirection) -> Bool {
        guard WorkspaceProjectEngine.moveProject(id, direction: direction, projects: &root.projects) else {
            return false
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func moveProject(_ sourceID: UUID, before targetID: UUID) -> Bool {
        guard WorkspaceProjectEngine.moveProject(sourceID, before: targetID, projects: &root.projects) else {
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
    public func runProjectExtensionUpdate(id: String, workspaceRoot: URL) -> Bool {
        runProjectExtensionCommand(
            id: id,
            workspaceRoot: workspaceRoot,
            planToolCall: WorkspaceExtensionToolCallPlanner.update,
            successNotice: { "Updated extension \($0.name)" },
            failureNotice: { "Extension update failed for \($0.name)" }
        )
    }

    @discardableResult
    public func runProjectExtensionInstall(id: String, workspaceRoot: URL) -> Bool {
        runProjectExtensionCommand(
            id: id,
            workspaceRoot: workspaceRoot,
            planToolCall: WorkspaceExtensionToolCallPlanner.install,
            successNotice: { "Installed extension \($0.name)" },
            failureNotice: { "Extension install failed for \($0.name)" }
        )
    }

    @discardableResult
    private func runProjectExtensionCommand(
        id: String,
        workspaceRoot: URL,
        planToolCall: (ProjectExtensionManifest) -> ToolCall?,
        successNotice: (ProjectExtensionManifest) -> String,
        failureNotice: (ProjectExtensionManifest) -> String
    ) -> Bool {
        refreshProjectMetadata(root.selectedProjectID)
        guard let manifest = selectedProject?.extensionManifests.first(where: { $0.id == id }),
              let toolCall = planToolCall(manifest)
        else {
            return false
        }

        let result = runToolCall(
            toolCall,
            workspaceRoot: workspaceRoot
        )
        refreshProjectMetadata(root.selectedProjectID)
        appendNotice(result.ok ? successNotice(manifest) : failureNotice(manifest))
        return result.ok
    }

    @discardableResult
    public func removeProject(_ id: UUID) -> Bool {
        let previousLocation = currentNavigationLocation
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
        recordNavigationTransition(from: previousLocation)
        pruneNavigationHistory()
        return true
    }
}
